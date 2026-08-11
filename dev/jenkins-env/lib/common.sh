#!/usr/bin/env bash
set -euo pipefail

COMMON_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_ROOT_DIR="$(cd "$COMMON_SCRIPT_DIR/.." && pwd)"

CONTROLLER_A_URL="http://127.0.0.1:8081/jenkins"
CONTROLLER_B_URL="http://127.0.0.1:8082/jenkins"
CONTROLLER_C_URL="http://127.0.0.1:8083/jenkins"
CONTROLLER_D_URL="http://127.0.0.1:8084/jenkins"

CONTROLLER_A_INTERNAL_URL="http://jenkins-a:8080/jenkins"
CONTROLLER_B_INTERNAL_URL="http://jenkins-b:8080/jenkins"
CONTROLLER_C_INTERNAL_URL="http://jenkins-c:8080/jenkins"
CONTROLLER_D_INTERNAL_URL="http://jenkins-d:8080/jenkins"

JENKINS_USER="${JENKINS_USER:-admin}"
JENKINS_PASSWORD="${JENKINS_PASSWORD:-admin}"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

err() {
  printf '[%s] [ERROR] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

# ---------------------------------------------------------------------------
# Provenance: what exactly produced a report.
#
# The plugin commit comes from .deployed-plugin, written by start.sh when it built and deployed
# the hpi - NOT from the plugin repo's HEAD at report time, which drifts if anything is committed
# while a run is in flight (seen on 2026-08-08: a load report claimed a commit made mid-run).
#
# The harness commit matters too: the scenarios, thresholds and analysis live in this repo, so the
# same plugin can score differently across harness revisions. It must be committed as well, with one
# exception: dev/reports/ is where a run writes its own output, so that path is expected to be dirty.
# ---------------------------------------------------------------------------

deployed_plugin_desc() {
  local f="$COMMON_ROOT_DIR/.deployed-plugin"
  if [[ ! -r "$f" ]]; then
    echo "unknown"
    return
  fi
  local sha state
  sha="$(cut -f1 <"$f")"
  state="$(cut -f3 <"$f")"
  if [[ "$state" == "dirty" ]]; then
    echo "$sha + local changes"
  else
    echo "$sha"
  fi
}

deployed_plugin_subject() {
  local f="$COMMON_ROOT_DIR/.deployed-plugin"
  if [[ -r "$f" ]]; then
    cut -f2 <"$f"
  else
    echo ""
  fi
}

harness_desc() {
  local sha
  sha="$(git -C "$COMMON_ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  if [[ "$(harness_state)" == "dirty" ]]; then
    echo "$sha + local changes"
  else
    echo "$sha"
  fi
}

harness_state() {
  if [[ -n "$(git -C "$COMMON_ROOT_DIR" status --porcelain -- ':(exclude,top)dev/reports' 2>/dev/null)" ]]; then
    echo "dirty"
  else
    echo "clean"
  fi
}

# Refuses to run when the harness itself has uncommitted changes outside dev/reports/.
# Skipped in --debug mode, where the report is filed as not reproducible instead.
require_clean_harness() {
  if [[ "${DEBUG_MODE:-false}" == true ]]; then
    return 0
  fi
  local dirty
  # ":(exclude,top)" - a pathspec is relative to the working directory, and this one runs from
  # jenkins-env, so without "top" the exclusion silently matched nothing and every report tripped it.
  dirty="$(git -C "$COMMON_ROOT_DIR" status --porcelain -- ':(exclude,top)dev/reports' 2>/dev/null || true)"
  if [[ -n "$dirty" ]]; then
    err "The test harness has uncommitted changes outside dev/reports/:"
    printf '%s\n' "$dirty" | sed 's/^/          /' >&2
    err ""
    err "Scenarios, thresholds and analysis shape the result, so the harness commit recorded in the"
    err "report has to describe them. Commit or stash first, then re-run,"
    err "or pass --debug (report goes to reports/debug/ and is not reproducible)."
    exit 2
  fi
}

# poll_until <timeout_seconds> <command...>
#
# The one polling loop. Four helpers below used to carry their own copy of "run this every 2s until
# it works or the clock runs out", each with its own drift and its own idea of the interval.
# Returns 0 as soon as the command succeeds, 1 on timeout.
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-2}"

poll_until() {
  local timeout_seconds="$1"
  shift
  local elapsed=0

  _POLL_ABORT=""
  while ((elapsed < timeout_seconds)); do
    if "$@"; then
      return 0
    fi
    # A probe can end the wait early when it learns the answer will never come (a cancelled queue
    # item will not become executable no matter how long we look at it).
    [[ -n "$_POLL_ABORT" ]] && return 2
    sleep "$POLL_INTERVAL_SECONDS"
    elapsed=$((elapsed + POLL_INTERVAL_SECONDS))
  done

  return 1
}

wait_for_url() {
  local url="$1"
  local timeout_seconds="$2"
  poll_until "$timeout_seconds" curl -fsS -o /dev/null "$url"
}

# controller_url <a|b|c|d>
controller_url() {
  case "$1" in
    a) printf '%s' "$CONTROLLER_A_URL" ;;
    b) printf '%s' "$CONTROLLER_B_URL" ;;
    c) printf '%s' "$CONTROLLER_C_URL" ;;
    d) printf '%s' "$CONTROLLER_D_URL" ;;
    *) err "Unknown controller: $1"; return 1 ;;
  esac
}

# controller_internal_url <a|b|c|d> - the address controllers reach each other by, inside the
# compose network. A remote connection configured with the host-side URL would not resolve.
controller_internal_url() {
  case "$1" in
    a) printf '%s' "$CONTROLLER_A_INTERNAL_URL" ;;
    b) printf '%s' "$CONTROLLER_B_INTERNAL_URL" ;;
    c) printf '%s' "$CONTROLLER_C_INTERNAL_URL" ;;
    d) printf '%s' "$CONTROLLER_D_INTERNAL_URL" ;;
    *) err "Unknown controller: $1"; return 1 ;;
  esac
}

# wait_for_controllers <timeout> [keys...] - defaults to a b c.
wait_for_controllers() {
  local timeout_seconds="${1:-180}"
  shift || true
  local keys=("$@")
  ((${#keys[@]} == 0)) && keys=(a b c)

  local ok=true
  local key url
  for key in "${keys[@]}"; do
    url="$(controller_url "$key")"
    if wait_for_url "$url/login" "$timeout_seconds"; then
      log "Controller ready: $url"
    else
      err "Controller not ready within ${timeout_seconds}s: $url"
      ok=false
    fi
  done

  [[ "$ok" == true ]]
}

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    err "Required command is missing: $command_name"
    return 1
  fi
}

json_extract() {
  local json_text="$1"
  local dotted_path="$2"
  python3 - "$dotted_path" "$json_text" <<'PY'
import json
import sys

path = sys.argv[1]
data = json.loads(sys.argv[2])

cur = data
if path:
    for key in path.split('.'):
        if isinstance(cur, dict) and key in cur:
            cur = cur[key]
        else:
            cur = None
            break

if cur is None:
    print("")
elif isinstance(cur, (dict, list)):
    print(json.dumps(cur))
else:
    print(cur)
PY
}

get_crumb_header() {
  local base_url="$1"
  local cookie_jar="$2"
  local crumb_json

  if ! crumb_json="$(curl -fsS -u "$JENKINS_USER:$JENKINS_PASSWORD" -c "$cookie_jar" "$base_url/crumbIssuer/api/json" 2>/dev/null)"; then
    echo ""
    return 0
  fi

  local field
  local crumb
  field="$(json_extract "$crumb_json" 'crumbRequestField')"
  crumb="$(json_extract "$crumb_json" 'crumb')"

  if [[ -n "$field" && -n "$crumb" ]]; then
    printf '%s: %s' "$field" "$crumb"
  fi
}

jenkins_post() {
  local base_url="$1"
  local path="$2"
  shift 2

  local cookie_jar
  cookie_jar="$(mktemp)"
  local response_file
  response_file="$(mktemp)"

  local crumb_header
  crumb_header="$(get_crumb_header "$base_url" "$cookie_jar")"

  local http_status

  if [[ -n "$crumb_header" ]]; then
    http_status="$(curl -sS -u "$JENKINS_USER:$JENKINS_PASSWORD" -b "$cookie_jar" -H "$crumb_header" "$@" -o "$response_file" -w '%{http_code}' "$base_url$path")"
  else
    http_status="$(curl -sS -u "$JENKINS_USER:$JENKINS_PASSWORD" -b "$cookie_jar" "$@" -o "$response_file" -w '%{http_code}' "$base_url$path")"
  fi

  if [[ "$http_status" -ge 400 ]]; then
    err "Jenkins POST failed: $path (HTTP $http_status)"
    cat "$response_file" >&2
    rm -f "$cookie_jar" "$response_file"
    return 1
  fi

  cat "$response_file"
  rm -f "$cookie_jar" "$response_file"
}

run_groovy_script() {
  local base_url="$1"
  local script_text="$2"
  local tmp_script
  tmp_script="$(mktemp)"
  printf '%s\n' "$script_text" >"$tmp_script"
  jenkins_post "$base_url" "/scriptText" -X POST --data-urlencode "script@$tmp_script"
  rm -f "$tmp_script"
}

run_groovy_script_checked() {
  local base_url="$1"
  local script_text="$2"
  local expected_marker="$3"

  local output
  output="$(run_groovy_script "$base_url" "$script_text")"

  if [[ -n "$expected_marker" ]] && ! printf '%s' "$output" | grep -Fq "$expected_marker"; then
    err "Groovy script did not return expected marker: $expected_marker"
    printf '%s\n' "$output" >&2
    return 1
  fi

  if printf '%s' "$output" | grep -Eqi 'MultipleCompilationErrorsException|MissingMethodException|No such property|HTTP ERROR|Sign in to access'; then
    err "Groovy script output indicates failure"
    printf '%s\n' "$output" >&2
    return 1
  fi

  printf '%s\n' "$output"
}

configure_remote_server() {
  local base_url="$1"
  local resource_name="$2"
  local expose_label="${3:-remote-enabled}"
  local auth_mode="${4:-authenticated}"

  if [[ "$auth_mode" != "authenticated" && "$auth_mode" != "anonymous" ]]; then
    err "Invalid auth_mode for configure_remote_server: $auth_mode"
    return 1
  fi

  local auth_groovy
  if [[ "$auth_mode" == "authenticated" ]]; then
    auth_groovy='''
import hudson.security.FullControlOnceLoggedInAuthorizationStrategy
import hudson.security.HudsonPrivateSecurityRealm
import hudson.security.csrf.DefaultCrumbIssuer

if (!(j.getSecurityRealm() instanceof HudsonPrivateSecurityRealm)) {
  def realm = new HudsonPrivateSecurityRealm(false)
  realm.createAccount("admin", "admin")
  j.setSecurityRealm(realm)
}
def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
j.setAuthorizationStrategy(strategy)
j.setCrumbIssuer(new DefaultCrumbIssuer(false))
'''
  else
    auth_groovy='''
import hudson.security.AuthorizationStrategy
import hudson.security.SecurityRealm

j.setSecurityRealm(SecurityRealm.NO_AUTHENTICATION)
j.setAuthorizationStrategy(AuthorizationStrategy.UNSECURED)
j.setCrumbIssuer(null)
'''
  fi

  run_groovy_script_checked "$base_url" "
import jenkins.model.Jenkins
import org.jenkins.plugins.lockableresources.LockableResourcesManager

def j = Jenkins.get()
${auth_groovy}

def lrm = LockableResourcesManager.get()
lrm.setRemoteApiEnabled(true)
lrm.setExposeLabel(\"$expose_label\")

if (lrm.fromName(\"$resource_name\") == null) {
  lrm.createResourceWithLabel(\"$resource_name\", \"$expose_label\")
}
lrm.save()
j.save()
println(\"OK: configured remote server $base_url ($auth_mode)\")
" "OK: configured remote server $base_url ($auth_mode)" >/dev/null
}

verify_remote_server_config() {
  local base_url="$1"
  local resource_name="$2"
  local auth_mode="${3:-authenticated}"

  if [[ "$auth_mode" != "authenticated" && "$auth_mode" != "anonymous" ]]; then
    err "Invalid auth_mode for verify_remote_server_config: $auth_mode"
    return 1
  fi

  local check_output
  check_output="$(run_groovy_script_checked "$base_url" "
import jenkins.model.Jenkins
import hudson.security.SecurityRealm
import hudson.security.AuthorizationStrategy
import hudson.security.HudsonPrivateSecurityRealm
import hudson.security.FullControlOnceLoggedInAuthorizationStrategy
import org.jenkins.plugins.lockableresources.LockableResourcesManager

def j = Jenkins.get()
def unsecured = (j.getSecurityRealm() == SecurityRealm.NO_AUTHENTICATION) && (j.getAuthorizationStrategy() == AuthorizationStrategy.UNSECURED)
def authenticated = (j.getSecurityRealm() instanceof HudsonPrivateSecurityRealm) && (j.getAuthorizationStrategy() instanceof FullControlOnceLoggedInAuthorizationStrategy)

def lrm = LockableResourcesManager.get()
def resource = lrm.fromName(\"$resource_name\")
def hasResource = (resource != null)
def exposed = hasResource && resource.getLabelsAsList().contains(lrm.getExposeLabel())

println(\"crumbDisabled=\" + (j.getCrumbIssuer() == null))
println(\"unsecuredMode=\" + unsecured)
println(\"authenticatedMode=\" + authenticated)
println(\"remoteApiEnabled=\" + lrm.isRemoteApiEnabled())
println(\"resourceExists=\" + hasResource)
println(\"resourceExposed=\" + exposed)
" "remoteApiEnabled=")"

  if [[ "$auth_mode" == "anonymous" ]]; then
    if ! printf '%s' "$check_output" | grep -Fq "unsecuredMode=true"; then
      err "Remote server verification failed: unsecuredMode is not true"
      return 1
    fi
  else
    if ! printf '%s' "$check_output" | grep -Fq "authenticatedMode=true"; then
      err "Remote server verification failed: authenticatedMode is not true"
      return 1
    fi
  fi

  if ! printf '%s' "$check_output" | grep -Fq "remoteApiEnabled=true"; then
    err "Remote server verification failed: remoteApiEnabled is not true"
    return 1
  fi
  if ! printf '%s' "$check_output" | grep -Fq "resourceExists=true"; then
    err "Remote server verification failed: resource does not exist ($resource_name)"
    return 1
  fi
  if ! printf '%s' "$check_output" | grep -Fq "resourceExposed=true"; then
    err "Remote server verification failed: resource is not exposed ($resource_name)"
    return 1
  fi
}

configure_controller_b_remote_server() {
  local resource_name="${1:-board-a1}"
  local auth_mode="${2:-authenticated}"
  configure_remote_server "$CONTROLLER_B_URL" "$resource_name" "remote-enabled" "$auth_mode"
}

verify_controller_b_remote_server_config() {
  local resource_name="${1:-board-a1}"
  local auth_mode="${2:-authenticated}"
  verify_remote_server_config "$CONTROLLER_B_URL" "$resource_name" "$auth_mode"
}

set_controller_b_anonymous_read() {
  local enabled="$1"

  if [[ "$enabled" == "on" ]]; then
    configure_controller_b_remote_server "board-a1" "anonymous"
    return 0
  fi

  configure_controller_b_remote_server "board-a1" "authenticated"
}

configure_local_resource() {
  local base_url="$1"
  local resource_name="$2"

  run_groovy_script_checked "$base_url" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager

def lrm = LockableResourcesManager.get()
if (lrm.fromName(\"$resource_name\") == null) {
  lrm.createResource(\"$resource_name\")
}
lrm.save()
println(\"OK: configured local resource $resource_name\")
" "OK: configured local resource $resource_name" >/dev/null
}

configure_remote_client_for_server() {
  local base_url="$1"
  local client_id="$2"
  local server_id="$3"
  local remote_url="$4"
  local credentials_id="${5:-}"

  run_groovy_script_checked "$base_url" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
import org.jenkins.plugins.lockableresources.RemoteConnection

def lrm = LockableResourcesManager.get()
def remotes = new LinkedHashMap(lrm.getRemotesAsMap())
remotes.put(\"$server_id\", new RemoteConnection(\"$server_id\", \"$remote_url\", \"$credentials_id\"))
lrm.setClientId(\"$client_id\")
lrm.setRemotes(new ArrayList(remotes.values()))
lrm.save()
println(\"OK: configured remote client $client_id -> $server_id:$remote_url (credentialsId=$credentials_id)\")
" "OK: configured remote client $client_id -> $server_id:$remote_url (credentialsId=$credentials_id)" >/dev/null
}

verify_remote_client_for_server() {
  local base_url="$1"
  local expected_client_id="$2"
  local server_id="$3"
  local expected_remote_url="$4"
  local expected_credentials_id="${5:-}"

  local check_output
  check_output="$(run_groovy_script_checked "$base_url" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager

def lrm = LockableResourcesManager.get()
def remote = lrm.getRemotesAsMap().get(\"$server_id\")
println(\"clientId=\" + lrm.getClientId())
println(\"remoteExists=\" + (remote != null))
println(\"remoteUrl=\" + (remote == null ? \"\" : remote.getUrl()))
println(\"credentialsId=\" + (remote == null ? \"\" : remote.getCredentialsId()))
" "remoteExists=")"

  if ! printf '%s' "$check_output" | grep -Fq "clientId=$expected_client_id"; then
    err "Remote client verification failed: clientId mismatch (expected=$expected_client_id)"
    return 1
  fi
  if ! printf '%s' "$check_output" | grep -Fq "remoteExists=true"; then
    err "Remote client verification failed: remote connection for serverId=$server_id does not exist"
    return 1
  fi
  if ! printf '%s' "$check_output" | grep -Fq "remoteUrl=$expected_remote_url"; then
    err "Remote client verification failed: remoteUrl mismatch (expected=$expected_remote_url)"
    return 1
  fi
  if ! printf '%s' "$check_output" | grep -Fq "credentialsId=$expected_credentials_id"; then
    err "Remote client verification failed: credentialsId mismatch (expected=$expected_credentials_id)"
    return 1
  fi
}

configure_remote_client() {
  local base_url="$1"
  local client_id="$2"
  local remote_url="$3"
  local credentials_id="${4:-}"
  configure_remote_client_for_server "$base_url" "$client_id" "b" "$remote_url" "$credentials_id"
}

verify_remote_client_config() {
  local base_url="$1"
  local expected_client_id="$2"
  local expected_remote_url="$3"
  local expected_credentials_id="${4:-}"
  verify_remote_client_for_server "$base_url" "$expected_client_id" "b" "$expected_remote_url" "$expected_credentials_id"
}

upsert_username_password_credential() {
  local base_url="$1"
  local credentials_id="$2"
  local username="$3"
  local password="$4"

  run_groovy_script_checked "$base_url" "
import com.cloudbees.plugins.credentials.SystemCredentialsProvider
import com.cloudbees.plugins.credentials.CredentialsScope
import com.cloudbees.plugins.credentials.common.IdCredentials
import com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl
import com.cloudbees.plugins.credentials.domains.Domain

def provider = SystemCredentialsProvider.getInstance()
def store = provider.getStore()
def existing = provider.getCredentials().findAll { c -> (c instanceof IdCredentials) && c.getId() == \"$credentials_id\" }
existing.each { c -> store.removeCredentials(Domain.global(), c) }
store.addCredentials(Domain.global(), new UsernamePasswordCredentialsImpl(
  CredentialsScope.GLOBAL,
  \"$credentials_id\",
  \"E2E generated username/password credential\",
  \"$username\",
  \"$password\"
))
provider.save()
println(\"OK: upserted username/password credential $credentials_id\")
" "OK: upserted username/password credential $credentials_id" >/dev/null
}

issue_user_api_token() {
  local base_url="$1"
  local username="$2"
  local token_name="$3"

  local token_output
  token_output="$(run_groovy_script_checked "$base_url" "
import hudson.model.User
import jenkins.security.ApiTokenProperty

def user = User.getById(\"$username\", false)
if (user == null) {
  throw new IllegalStateException(\"User not found: $username\")
}

def apiTokenProperty = user.getProperty(ApiTokenProperty.class)
if (apiTokenProperty == null) {
  throw new IllegalStateException(\"ApiTokenProperty not found for user: $username\")
}

def generated = apiTokenProperty.tokenStore.generateNewToken(\"$token_name\")
user.save()
println(\"TOKEN=\" + generated.plainValue)
" "TOKEN=")"

  local token_value
  token_value="$(printf '%s\n' "$token_output" | awk -F= '/^TOKEN=/{print substr($0,7)}' | tail -n 1)"

  if [[ -z "$token_value" ]]; then
    err "Failed to issue API token for user=$username tokenName=$token_name"
    return 1
  fi

  printf '%s\n' "$token_value"
}

upsert_string_credential() {
  local base_url="$1"
  local credentials_id="$2"
  local secret_value="$3"

  run_groovy_script_checked "$base_url" "
import com.cloudbees.plugins.credentials.SystemCredentialsProvider
import com.cloudbees.plugins.credentials.common.IdCredentials
import com.cloudbees.plugins.credentials.domains.Domain
import jenkins.model.Jenkins

def cl = Jenkins.get().pluginManager.uberClassLoader
def stringCredentialsClass
def credentialsScopeClass
def secretClass

try {
  stringCredentialsClass = cl.loadClass(\"org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl\")
  credentialsScopeClass = cl.loadClass(\"com.cloudbees.plugins.credentials.CredentialsScope\")
  secretClass = cl.loadClass(\"hudson.util.Secret\")
} catch (ClassNotFoundException ex) {
  throw new IllegalStateException(\"plain-credentials plugin is required for type-mismatch test\")
}

def globalScope = credentialsScopeClass.getField(\"GLOBAL\").get(null)
def secret = secretClass.getMethod(\"fromString\", String.class).invoke(null, \"$secret_value\")
def ctor = stringCredentialsClass.getConstructor(credentialsScopeClass, String.class, String.class, secretClass)
def credential = ctor.newInstance(
  globalScope,
  \"$credentials_id\",
  \"E2E generated string credential\",
  secret
)

def provider = SystemCredentialsProvider.getInstance()
def store = provider.getStore()
def existing = provider.getCredentials().findAll { c -> (c instanceof IdCredentials) && c.getId() == \"$credentials_id\" }
existing.each { c -> store.removeCredentials(Domain.global(), c) }
store.addCredentials(Domain.global(), credential)
provider.save()
println(\"OK: upserted string credential $credentials_id\")
" "OK: upserted string credential $credentials_id" >/dev/null
}

upsert_pipeline_job() {
  local base_url="$1"
  local job_name="$2"
  local pipeline_script="$3"
  local pipeline_b64

  pipeline_b64="$(printf '%s' "$pipeline_script" | base64 | tr -d '\n')"

  run_groovy_script_checked "$base_url" "
import jenkins.model.Jenkins
import org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition
import org.jenkinsci.plugins.workflow.job.WorkflowJob

def j = Jenkins.get()
def name = \"$job_name\"
def script = new String(\"$pipeline_b64\".decodeBase64(), \"UTF-8\")

WorkflowJob job = j.getItem(name)
if (job == null) {
  job = j.createProject(WorkflowJob.class, name)
}
job.setDefinition(new CpsFlowDefinition(script, true))
job.save()
println(\"OK: upserted job $job_name\")
" "OK: upserted job $job_name" >/dev/null
}

trigger_job() {
  local base_url="$1"
  local job_name="$2"
  local headers_file
  headers_file="$(mktemp)"

  local cookie_jar
  cookie_jar="$(mktemp)"

  local crumb_header
  crumb_header="$(get_crumb_header "$base_url" "$cookie_jar")"

  if [[ -n "$crumb_header" ]]; then
    curl -sS -u "$JENKINS_USER:$JENKINS_PASSWORD" -b "$cookie_jar" -X POST -H "$crumb_header" -D "$headers_file" -o /dev/null \
      "$base_url/job/$job_name/build"
  else
    curl -sS -u "$JENKINS_USER:$JENKINS_PASSWORD" -b "$cookie_jar" -X POST -D "$headers_file" -o /dev/null \
      "$base_url/job/$job_name/build"
  fi

  local location
  location="$(awk 'BEGIN{IGNORECASE=1} /^Location:/{print $2}' "$headers_file" | tr -d '\r' | tail -n 1)"
  rm -f "$cookie_jar" "$headers_file"

  if [[ -z "$location" ]]; then
    err "Failed to get queue Location header for job: $job_name"
    return 1
  fi

  printf '%s\n' "$location"
}

_probe_queue_executable() {
  local queue_url="$1"
  local json
  json="$(curl -fsS -u "$JENKINS_USER:$JENKINS_PASSWORD" "$queue_url/api/json")" || return 1

  _POLL_RESULT="$(json_extract "$json" 'executable.url')"
  [[ -n "$_POLL_RESULT" ]] && return 0

  local cancelled
  cancelled="$(json_extract "$json" 'cancelled')"
  if [[ "$cancelled" == "True" || "$cancelled" == "true" ]]; then
    _POLL_ABORT="cancelled"
  fi
  return 1
}

wait_for_queue_executable() {
  local queue_url="$1"
  local timeout_seconds="$2"

  if poll_until "$timeout_seconds" _probe_queue_executable "$queue_url"; then
    printf '%s\n' "$_POLL_RESULT"
    return 0
  fi

  if [[ -n "$_POLL_ABORT" ]]; then
    err "Queue item was cancelled: $queue_url"
  else
    err "Timeout waiting queue executable: $queue_url"
  fi
  return 1
}

_probe_build_finished() {
  local build_url="$1"
  local json
  json="$(curl -fsS -u "$JENKINS_USER:$JENKINS_PASSWORD" "$build_url/api/json")" || return 1

  local building
  building="$(json_extract "$json" 'building')"
  [[ "$building" == "False" || "$building" == "false" ]] || return 1

  _POLL_RESULT="$(json_extract "$json" 'result')"
  return 0
}

wait_for_build_result() {
  local build_url="$1"
  local timeout_seconds="$2"

  if poll_until "$timeout_seconds" _probe_build_finished "$build_url"; then
    printf '%s\n' "$_POLL_RESULT"
    return 0
  fi

  err "Timeout waiting build completion: $build_url"
  return 1
}

_probe_console_contains() {
  curl -fsS -u "$JENKINS_USER:$JENKINS_PASSWORD" "$1/consoleText" 2>/dev/null | grep -Fq "$2"
}

wait_for_console_contains() {
  local build_url="$1"
  local needle="$2"
  local timeout_seconds="$3"
  poll_until "$timeout_seconds" _probe_console_contains "$build_url" "$needle"
}

save_console_log() {
  local build_url="$1"
  local output_file="$2"
  curl -fsS -u "$JENKINS_USER:$JENKINS_PASSWORD" "$build_url/consoleText" >"$output_file"
}

# console_value <console_file> <NAME> - the value a pipeline echoed as `NAME=...`.
# Values can contain '=' (and commas, for a multi-resource variable), so everything after the first
# '=' is the value.
console_value() {
  grep -E "^$2=" "$1" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r'
}

# abort_build <base_url> <build_url> - what a user pressing the red X does.
#
# Aborting is the most common way a lock's lifetime ends unexpectedly, and it is the one path that
# never runs the pipeline's own next line - so whether the lease is released depends entirely on the
# step's cleanup. Scenarios need to be able to cause it.
abort_build() {
  local base_url="$1"
  local build_url="${2%/}"

  local cookie_jar
  cookie_jar="$(mktemp)"
  local crumb_header
  crumb_header="$(get_crumb_header "$base_url" "$cookie_jar")"

  if [[ -n "$crumb_header" ]]; then
    curl -sS -u "$JENKINS_USER:$JENKINS_PASSWORD" -b "$cookie_jar" -H "$crumb_header" \
      -X POST -o /dev/null "$build_url/stop" || true
  else
    curl -sS -u "$JENKINS_USER:$JENKINS_PASSWORD" -b "$cookie_jar" \
      -X POST -o /dev/null "$build_url/stop" || true
  fi
  rm -f "$cookie_jar"
}

# wait_for_resource_free <controller_key> <resource> <timeout_seconds>
# Succeeds as soon as the resource carries no lock, lease or reservation.
wait_for_resource_free() {
  local key="$1"
  local name="$2"
  local timeout="$3"
  poll_until "$timeout" _probe_resource_free "$key" "$name"
}

_probe_resource_free() {
  local state
  state="$(resource_state "$1" "$2")" || return 1
  [[ "$(resource_field "$state" LOCKED)" == "false" &&
     -z "$(resource_field "$state" REMOTE_LOCK_ID)" ]]
}

trigger_and_resolve_build_url() {
  local base_url="$1"
  local job_name="$2"
  local queue_timeout="${3:-120}"

  local queue_url
  queue_url="$(trigger_job "$base_url" "$job_name")"
  wait_for_queue_executable "$queue_url" "$queue_timeout"
}

docker_compose() {
  docker compose -f "$COMMON_ROOT_DIR/docker-compose.yml" "$@"
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "$expected" != "$actual" ]]; then
    err "Assertion failed: $message (expected='$expected' actual='$actual')"
    return 1
  fi
}

assert_ge() {
  local actual="$1"
  local threshold="$2"
  local message="$3"
  if (( actual < threshold )); then
    err "Assertion failed: $message (actual=$actual threshold=$threshold)"
    return 1
  fi
}

scenario_not_implemented() {
  local name="$1"
  log "[SKIP] Scenario '$name' is not implemented yet (initial scaffold)."
  return 10
}

# ---------------------------------------------------------------------------
# M1A helpers
# ---------------------------------------------------------------------------

configure_forced_server_id() {
  local base_url="$1"
  local forced_server_id="$2"

  run_groovy_script_checked "$base_url" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager

def lrm = LockableResourcesManager.get()
lrm.setForcedServerId(\"$forced_server_id\")
lrm.save()
println(\"OK: forcedServerId set to '$forced_server_id' on $base_url\")
" "OK: forcedServerId set to" >/dev/null
}

configure_forced_server_id_empty() {
  local base_url="$1"

  run_groovy_script_checked "$base_url" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager

def lrm = LockableResourcesManager.get()
lrm.setForcedServerId(\"\")
lrm.save()
println(\"OK: forcedServerId cleared on $base_url\")
" "OK: forcedServerId cleared" >/dev/null
}

# ---------------------------------------------------------------------------
# Pair setup
#
# Standing a client up against a server takes five calls in a fixed order - expose the resource,
# verify it, issue a token on the server, store it as a credential on the client, point the client
# at the server - and every scenario but one repeated all five with its own prefix. The order is not
# arbitrary (the credential cannot exist before the token, the client config cannot be verified
# before it is written), so each copy was a chance to get it subtly wrong.
#
# setup_remote_pair <prefix> <client_key> <server_key> <resource> [auth_mode]
# Leaves the credentials id in REMOTE_PAIR_CREDENTIALS_ID.
# ---------------------------------------------------------------------------

setup_remote_pair() {
  local prefix="$1"
  local client_key="$2"
  local server_key="$3"
  local resource_name="$4"
  local auth_mode="${5:-authenticated}"

  local client_url server_url server_internal_url
  client_url="$(controller_url "$client_key")"
  server_url="$(controller_url "$server_key")"
  server_internal_url="$(controller_internal_url "$server_key")"

  REMOTE_PAIR_CREDENTIALS_ID="${prefix}-${client_key}-for-${server_key}"

  configure_remote_server "$server_url" "$resource_name" "remote-enabled" "$auth_mode"
  verify_remote_server_config "$server_url" "$resource_name" "$auth_mode"

  local token
  token="$(issue_user_api_token "$server_url" "admin" "e2e-${prefix}-${server_key}-token")"
  upsert_username_password_credential "$client_url" "$REMOTE_PAIR_CREDENTIALS_ID" "admin" "$token"

  configure_remote_client_for_server \
    "$client_url" "jenkins-${client_key}" "$server_key" "$server_internal_url" "$REMOTE_PAIR_CREDENTIALS_ID"
  verify_remote_client_for_server \
    "$client_url" "jenkins-${client_key}" "$server_key" "$server_internal_url" "$REMOTE_PAIR_CREDENTIALS_ID"
}

# expose_resource <server_key> <resource> - an additional exposed resource on an already configured
# server, for scenarios that need more than the one setup_remote_pair created.
expose_resource() {
  local server_key="$1"
  local resource_name="$2"
  configure_remote_server "$(controller_url "$server_key")" "$resource_name" "remote-enabled" "authenticated"
}

# ---------------------------------------------------------------------------
# The remote API, spoken directly
#
# Most scenarios drive the API through lock(), which is the right level for behaviour but the wrong
# one for boundaries: the client never sends a malformed body, never asks about a lease it does not
# own, and never posts a megabyte. The contract those cases exercise - which status code, which
# errorCode - is only reachable by making the request itself.
#
# Bodies are passed as files rather than strings, because one of the boundaries under test is the
# 1 MiB body cap and a megabyte does not belong on a command line.
# ---------------------------------------------------------------------------

REMOTE_API_BASE="/lockable-resources/remote/v1"

# api_request <method> <server_key> <token> <path> <body_file|-> <out_file> [curl args...]
# Prints the HTTP status code; the response body lands in out_file.
api_request() {
  local method="$1"
  local key="$2"
  local token="$3"
  local path="$4"
  local body="$5"
  local out="$6"
  shift 6

  local args=(-sS -o "$out" -w '%{http_code}'
    -u "admin:$token"
    -H 'Accept: application/json'
    -X "$method")
  if [[ "$body" != "-" ]]; then
    args+=(-H 'Content-Type: application/json' --data-binary "@$body")
  fi

  curl "${args[@]}" "$@" "$(controller_url "$key")${REMOTE_API_BASE}${path}"
}

# api_acquire <server_key> <token> <json_body> <out_file> - body as a string, for the common case.
api_acquire() {
  local body_file
  body_file="$(mktemp)"
  printf '%s' "$3" >"$body_file"
  api_request POST "$1" "$2" "/acquire/" "$body_file" "$4"
  rm -f "$body_file"
}

# api_acquire_file <server_key> <token> <body_file> <out_file> - for bodies too big to pass inline.
api_acquire_file() {
  api_request POST "$1" "$2" "/acquire/" "$3" "$4"
}

api_poll() {
  api_request GET "$1" "$2" "/acquire/$3/" - "$4"
}

api_heartbeat() {
  api_request POST "$1" "$2" "/lease/$3/heartbeat" - "$4"
}

api_release() {
  api_request POST "$1" "$2" "/lease/$3/release" - "$4"
}

api_resources() {
  api_request GET "$1" "$2" "/resources/" - "$3"
}

# api_field <response_file> <key> - a top-level field of a JSON response.
api_field() {
  json_extract "$(cat "$1")" "$2" 2>/dev/null || true
}

# remote_record_state <server_key> <lock_id> - the server's view of a record: a state name, or GONE
# once the record has been cleaned up. GONE and a state are different answers and scenarios turn on
# the difference, so it is spelled rather than left empty.
remote_record_state() {
  run_groovy_script "$(controller_url "$1")" "
import org.jenkins.plugins.lockableresources.remote.RemoteLockManager

def rec = RemoteLockManager.get().find('$2')
println('RECORD=' + (rec == null ? 'GONE' : rec.getState().name()))
" | tr -d '\r' | awk -F= '/^RECORD=/{print $2}' | tail -n1
}

# scenario_check_api <label> <expected_status> <actual_status> <expected_error_code> <response_file>
# A rejection is a status *and* an errorCode; checking only the status lets a 400 that means
# something else entirely pass for the one the scenario asked about.
scenario_check_api() {
  local label="$1"
  local want_status="$2"
  local got_status="$3"
  local want_code="$4"
  local response_file="$5"

  local got_code=""
  [[ -s "$response_file" ]] && got_code="$(api_field "$response_file" errorCode)"

  if [[ -z "$want_code" ]]; then
    scenario_check "$label" "HTTP status" "$want_status" "$got_status"
    return
  fi

  scenario_check "$label" "HTTP status + errorCode" \
    "$want_status/$want_code" "$got_status/${got_code:-<none>}"
}

# ---------------------------------------------------------------------------
# Relay batches
#
# The topology scenarios - mesh, chain, fan-in, diamond - all do the same thing: start one job per
# controller, wait for every one, then assert that each finished and each got into its lock body.
# Written out longhand that was four near-identical blocks, and each of them collapsed the whole
# batch into a single `[[ $ar == SUCCESS && $br == SUCCESS && $cr == SUCCESS ]] || exit 1`, which
# tells you a topology failed but not which leg of it.
#
#   relay_reset
#   relay_trigger a d01-a A_ACQUIRED
#   relay_trigger b d01-b B_ACQUIRED
#   relay_await_all 900
# ---------------------------------------------------------------------------

_RELAY_KEYS=()
_RELAY_JOBS=()
_RELAY_MARKERS=()
_RELAY_URLS=()

relay_reset() {
  _RELAY_KEYS=()
  _RELAY_JOBS=()
  _RELAY_MARKERS=()
  _RELAY_URLS=()
}

# relay_trigger <controller_key> <job_name> [console_marker]
relay_trigger() {
  local key="$1"
  local job="$2"
  local marker="${3:-}"
  local url
  url="$(trigger_and_resolve_build_url "$(controller_url "$key")" "$job" 120)"
  _RELAY_KEYS+=("$key")
  _RELAY_JOBS+=("$job")
  _RELAY_MARKERS+=("$marker")
  _RELAY_URLS+=("$url")
}

# relay_await_all [timeout_seconds] - one checkpoint per leg, so a failed topology names its leg.
relay_await_all() {
  local timeout="${1:-900}"
  local i key job marker url console result

  for i in "${!_RELAY_URLS[@]}"; do
    key="${_RELAY_KEYS[$i]}"
    job="${_RELAY_JOBS[$i]}"
    marker="${_RELAY_MARKERS[$i]}"
    url="${_RELAY_URLS[$i]}"
    console="$SCENARIO_DIR/${job}-console.txt"

    result="$(wait_for_build_result "$url" "$timeout")" || result="TIMEOUT"
    save_console_log "$url" "$console" || true
    scenario_artifact "$job console (on $key)" "$console"

    scenario_check "$job on $key finished" "Build API" "SUCCESS" "$result"
    if [[ -n "$marker" ]]; then
      scenario_check_contains "$job on $key entered its lock body" "$console" "$marker"
    fi

    scenario_fact "${job}_url" "$url"
    scenario_fact "${job}_result" "$result"
  done
}

# ---------------------------------------------------------------------------
# Resource state
#
# "Is the resource free again afterwards?" is the check that catches a leaked lease, and almost every
# scenario ended up asking it with its own inline Groovy - each one looking at a slightly different
# subset (some checked isLocked, some getRemoteLockedBy, some both). A leaked lease that only shows
# up in the field nobody looked at is exactly the bug this check exists to find, so it asks once,
# here, and looks at all of them.
# ---------------------------------------------------------------------------

# resource_state <controller_key> <resource> - newline separated key=value facts.
resource_state() {
  local key="$1"
  local name="$2"
  run_groovy_script "$(controller_url "$key")" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager

def r = LockableResourcesManager.get().fromName('$name')
println('EXISTS=' + (r != null))
println('LOCKED=' + (r != null && r.isLocked()))
println('QUEUED=' + (r != null && r.isQueued()))
println('REMOTE_LOCK_ID=' + (r == null ? '' : (r.getRemoteLockedBy() ?: '')))
println('RESERVED_BY=' + (r == null ? '' : (r.getReservedBy() ?: '')))
" | tr -d '\r'
}

# resource_field <state> <key>
resource_field() {
  printf '%s\n' "$1" | awk -F= -v k="$2" '$1 == k { print substr($0, length(k) + 2); exit }'
}

# scenario_check_resource_free <label> <controller_key> <resource>
# Free means all of: not locked, no remote lease, not reserved. Checking one of the three is how a
# leak hides.
scenario_check_resource_free() {
  local label="$1"
  local key="$2"
  local name="$3"

  local state
  state="$(resource_state "$key" "$name")"
  local one_line
  one_line="$(printf '%s' "$state" | tr '\n' ' ')"

  if [[ "$(resource_field "$state" LOCKED)" == "false" &&
        -z "$(resource_field "$state" REMOTE_LOCK_ID)" &&
        -z "$(resource_field "$state" RESERVED_BY)" ]]; then
    scenario_record "$label" "Groovy resource state on $key" "free: not locked, no lease, not reserved" "free" "PASS"
  else
    scenario_record "$label" "Groovy resource state on $key" "free: not locked, no lease, not reserved" "$one_line" "FAIL"
  fi
}

# scenario_check_resource_locked <label> <controller_key> <resource> [remote|any]
scenario_check_resource_locked() {
  local label="$1"
  local key="$2"
  local name="$3"
  local kind="${4:-any}"

  local state
  state="$(resource_state "$key" "$name")"
  local one_line
  one_line="$(printf '%s' "$state" | tr '\n' ' ')"
  local locked lease
  locked="$(resource_field "$state" LOCKED)"
  lease="$(resource_field "$state" REMOTE_LOCK_ID)"

  if [[ "$kind" == "remote" ]]; then
    if [[ -n "$lease" ]]; then
      scenario_record "$label" "Groovy resource state on $key" "held by a remote lease" "lease=$lease" "PASS"
    else
      scenario_record "$label" "Groovy resource state on $key" "held by a remote lease" "$one_line" "FAIL"
    fi
  else
    if [[ "$locked" == "true" ]]; then
      scenario_record "$label" "Groovy resource state on $key" "locked" "locked" "PASS"
    else
      scenario_record "$label" "Groovy resource state on $key" "locked" "$one_line" "FAIL"
    fi
  fi
}

# remote_lease_id <controller_key> <resource> - empty when the resource carries no remote lease.
remote_lease_id() {
  resource_field "$(resource_state "$1" "$2")" REMOTE_LOCK_ID
}

# drop_resources <controller_key> <resource...> - remove resources a scenario created.
#
# Scenarios name their resources with a per-run stamp, which keeps two runs from colliding on a
# name but does nothing about the pile: every run leaves its resources behind, and on a long-lived
# container they accumulate. For a resource that is only ever addressed by name that is untidy;
# for one addressed by *label* it is a defect, because a label acquire matches across runs and can
# hand a scenario a resource an earlier run created. That is exactly how S08 was passing - its
# assertion was a prefix match, so binding to the previous run's board looked identical.
#
# Best-effort and free-only: a resource still held is a finding for the scenario to report, not
# something to delete out from under it.
drop_resources() {
  local key="$1"
  shift
  local names=""
  local name
  for name in "$@"; do
    names+="'${name}',"
  done
  [[ -z "$names" ]] && return 0

  run_groovy_script "$(controller_url "$key")" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager

def lrm = LockableResourcesManager.get()
[${names%,}].each { n ->
  def r = lrm.fromName(n)
  if (r != null && !r.isLocked() && r.getRemoteLockedBy() == null && r.getReservedBy() == null) {
    lrm.getResources().remove(r)
  }
}
lrm.save()
println('OK')
" >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# The scenario registry (lib/scenarios.tsv)
# ---------------------------------------------------------------------------

REGISTRY_FILE="$COMMON_SCRIPT_DIR/scenarios.tsv"

registry_rows() {
  grep -v '^#' "$REGISTRY_FILE" | grep -v '^[[:space:]]*$'
}

# registry_names [series] - in declaration order, which is also the run order.
registry_names() {
  local series="${1:-all}"
  if [[ "$series" == "all" ]]; then
    registry_rows | cut -f2
  else
    registry_rows | awk -F'\t' -v s="$series" '$3 == s {print $2}'
  fi
}

# registry_field <name> <column-number>
registry_field() {
  registry_rows | awk -F'\t' -v n="$1" -v c="$2" '$2 == n {print $c; exit}'
}

registry_id() { registry_field "$1" 1; }
registry_series() { registry_field "$1" 3; }
registry_controllers() { registry_field "$1" 4; }
registry_axis() { registry_field "$1" 5; }
registry_summary() { registry_field "$1" 6; }

registry_series_list() {
  registry_rows | cut -f3 | awk '!seen[$0]++'
}

registry_has() {
  registry_rows | cut -f2 | grep -Fxq "$1"
}

# The controllers a scenario needs, as separate keys: "abcd" -> a b c d
registry_controller_keys() {
  registry_controllers "$1" | grep -o . | tr '\n' ' '
}

configure_label_resource() {
  local base_url="$1"
  local resource_name="$2"
  local label_name="$3"
  local expose_label="${4:-remote-enabled}"

  run_groovy_script_checked "$base_url" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager

def lrm = LockableResourcesManager.get()
lrm.setRemoteApiEnabled(true)
lrm.setExposeLabel(\"$expose_label\")
if (lrm.fromName(\"$resource_name\") == null) {
  lrm.createResourceWithLabel(\"$resource_name\", \"$expose_label $label_name\".trim())
} else {
  def r = lrm.fromName(\"$resource_name\")
  def existingLabels = r.getLabels() ?: \"\"
  def newLabels = (existingLabels.tokenize() + [\"$expose_label\", \"$label_name\"]).unique().join(\" \").trim()
  r.setLabels(newLabels)
}
lrm.save()
println(\"OK: label resource $resource_name ($label_name) on $base_url\")
" "OK: label resource $resource_name" >/dev/null
}

# ---------------------------------------------------------------------------
# Sourced last: both need log/err, and scenario.sh installs an EXIT trap that must not be in place
# while common.sh is still defining things.
# ---------------------------------------------------------------------------
# shellcheck source=./timings.sh
source "$COMMON_SCRIPT_DIR/timings.sh"
# shellcheck source=./scenario.sh
source "$COMMON_SCRIPT_DIR/scenario.sh"
