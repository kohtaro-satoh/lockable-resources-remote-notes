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

wait_for_url() {
  local url="$1"
  local timeout_seconds="$2"
  local elapsed=0

  while [[ "$elapsed" -lt "$timeout_seconds" ]]; do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  return 1
}

wait_for_controllers() {
  local timeout_seconds="${1:-180}"
  local ok=true

  for url in "$CONTROLLER_A_URL" "$CONTROLLER_B_URL" "$CONTROLLER_C_URL"; do
    if wait_for_url "$url/login" "$timeout_seconds"; then
      log "Controller ready: $url"
    else
      err "Controller not ready within ${timeout_seconds}s: $url"
      ok=false
    fi
  done

  [[ "$ok" == true ]]
}

wait_for_controllers_with_d() {
  local timeout_seconds="${1:-180}"
  local ok=true

  for url in "$CONTROLLER_A_URL" "$CONTROLLER_B_URL" "$CONTROLLER_C_URL" "$CONTROLLER_D_URL"; do
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

wait_for_queue_executable() {
  local queue_url="$1"
  local timeout_seconds="$2"
  local elapsed=0

  while [[ "$elapsed" -lt "$timeout_seconds" ]]; do
    local json
    json="$(curl -fsS -u "$JENKINS_USER:$JENKINS_PASSWORD" "$queue_url/api/json")"
    local executable_url
    executable_url="$(json_extract "$json" 'executable.url')"
    local cancelled
    cancelled="$(json_extract "$json" 'cancelled')"

    if [[ -n "$executable_url" ]]; then
      printf '%s\n' "$executable_url"
      return 0
    fi
    if [[ "$cancelled" == "True" || "$cancelled" == "true" ]]; then
      err "Queue item was cancelled: $queue_url"
      return 1
    fi

    sleep 2
    elapsed=$((elapsed + 2))
  done

  err "Timeout waiting queue executable: $queue_url"
  return 1
}

wait_for_build_result() {
  local build_url="$1"
  local timeout_seconds="$2"
  local elapsed=0

  while [[ "$elapsed" -lt "$timeout_seconds" ]]; do
    local json
    json="$(curl -fsS -u "$JENKINS_USER:$JENKINS_PASSWORD" "$build_url/api/json")"
    local building
    building="$(json_extract "$json" 'building')"

    if [[ "$building" == "False" || "$building" == "false" ]]; then
      printf '%s\n' "$(json_extract "$json" 'result')"
      return 0
    fi

    sleep 2
    elapsed=$((elapsed + 2))
  done

  err "Timeout waiting build completion: $build_url"
  return 1
}

wait_for_console_contains() {
  local build_url="$1"
  local needle="$2"
  local timeout_seconds="$3"
  local elapsed=0

  while [[ "$elapsed" -lt "$timeout_seconds" ]]; do
    local console
    console="$(curl -fsS -u "$JENKINS_USER:$JENKINS_PASSWORD" "$build_url/consoleText")"
    if printf '%s' "$console" | grep -Fq "$needle"; then
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  return 1
}

save_console_log() {
  local build_url="$1"
  local output_file="$2"
  curl -fsS -u "$JENKINS_USER:$JENKINS_PASSWORD" "$build_url/consoleText" >"$output_file"
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
  def newLabels = (existingLabels.split(/\s+/) + [\"$expose_label\", \"$label_name\"]).unique().join(\" \").trim()
  r.setLabels(newLabels)
}
lrm.save()
println(\"OK: label resource $resource_name ($label_name) on $base_url\")
" "OK: label resource $resource_name" >/dev/null
}
