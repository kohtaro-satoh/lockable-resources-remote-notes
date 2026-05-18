#!/usr/bin/env bash
set -euo pipefail

COMMON_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_ROOT_DIR="$(cd "$COMMON_SCRIPT_DIR/.." && pwd)"

CONTROLLER_A_URL="http://127.0.0.1:8081/jenkins"
CONTROLLER_B_URL="http://127.0.0.1:8082/jenkins"
CONTROLLER_C_URL="http://127.0.0.1:8083/jenkins"
CONTROLLER_B_INTERNAL_URL="http://jenkins-8082:8080/jenkins"

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
    # Some Jenkins setups may not require crumbs.
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
  rm -f "$cookie_jar"
  rm -f "$response_file"
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

configure_controller_b_remote_server() {
  local resource_name="${1:-board-a1}"

  run_groovy_script_checked "$CONTROLLER_B_URL" "
import hudson.security.AuthorizationStrategy
import hudson.security.SecurityRealm
import jenkins.model.Jenkins
import org.jenkins.plugins.lockableresources.LockableResourcesManager

def j = Jenkins.get()
j.setSecurityRealm(SecurityRealm.NO_AUTHENTICATION)
j.setAuthorizationStrategy(AuthorizationStrategy.UNSECURED)

// Step8 E2E: remote client currently sends no auth/crumb.
// Disable CSRF in this local environment so POST /acquire can be exercised.
j.setCrumbIssuer(null)

def lrm = LockableResourcesManager.get()
lrm.setRemoteApiEnabled(true)
lrm.setExposeLabel(\"remote-enabled\")

if (lrm.fromName(\"$resource_name\") == null) {
  lrm.createResourceWithLabel(\"$resource_name\", \"remote-enabled\")
}
lrm.save()
j.save()
println(\"OK: configured remote server B\")
" "OK: configured remote server B" >/dev/null
}

verify_controller_b_remote_server_config() {
  local resource_name="${1:-board-a1}"

  local check_output
  check_output="$(run_groovy_script_checked "$CONTROLLER_B_URL" "
import jenkins.model.Jenkins
import hudson.security.SecurityRealm
import hudson.security.AuthorizationStrategy
import org.jenkins.plugins.lockableresources.LockableResourcesManager

def j = Jenkins.get()
def unsecured = (j.getSecurityRealm() == SecurityRealm.NO_AUTHENTICATION) && (j.getAuthorizationStrategy() == AuthorizationStrategy.UNSECURED)

def lrm = LockableResourcesManager.get()
def resource = lrm.fromName(\"$resource_name\")
def hasResource = (resource != null)
def exposed = hasResource && resource.getLabelsAsList().contains(lrm.getExposeLabel())

println(\"crumbDisabled=\" + (j.getCrumbIssuer() == null))
println(\"unsecuredMode=\" + unsecured)
println(\"remoteApiEnabled=\" + lrm.isRemoteApiEnabled())
println(\"exposeLabel=\" + lrm.getExposeLabel())
println(\"resourceExists=\" + hasResource)
println(\"resourceExposed=\" + exposed)

" "unsecuredMode=")"

  if ! printf '%s' "$check_output" | grep -Fq "crumbDisabled=true"; then
    err "Controller B verification failed: crumbDisabled is not true"
    return 1
  fi
  if ! printf '%s' "$check_output" | grep -Fq "unsecuredMode=true"; then
    err "Controller B verification failed: unsecuredMode is not true"
    return 1
  fi
  if ! printf '%s' "$check_output" | grep -Fq "remoteApiEnabled=true"; then
    err "Controller B verification failed: remoteApiEnabled is not true"
    return 1
  fi
  if ! printf '%s' "$check_output" | grep -Fq "resourceExists=true"; then
    err "Controller B verification failed: $resource_name does not exist"
    return 1
  fi
  if ! printf '%s' "$check_output" | grep -Fq "resourceExposed=true"; then
    err "Controller B verification failed: board-a1 is not exposed by exposeLabel"
    return 1
  fi
}

set_controller_b_anonymous_read() {
  local enabled="$1"

  if [[ "$enabled" == "on" ]]; then
    configure_controller_b_remote_server
    return 0
  fi

  # "off" means force authenticated mode so no-auth remote POST fails.
  run_groovy_script_checked "$CONTROLLER_B_URL" "
import hudson.security.FullControlOnceLoggedInAuthorizationStrategy
import hudson.security.HudsonPrivateSecurityRealm
import hudson.security.csrf.DefaultCrumbIssuer
import jenkins.model.Jenkins

def j = Jenkins.get()
if (!(j.getSecurityRealm() instanceof HudsonPrivateSecurityRealm)) {
  def realm = new HudsonPrivateSecurityRealm(false)
  realm.createAccount(\"admin\", \"admin\")
  j.setSecurityRealm(realm)
}
def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
j.setAuthorizationStrategy(strategy)
j.setCrumbIssuer(new DefaultCrumbIssuer(false))
j.save()
println(\"OK: anonymous read set to $enabled\")
" "OK: anonymous read set to $enabled" >/dev/null
}

configure_remote_client() {
  local base_url="$1"
  local client_id="$2"
  local remote_url="$3"

  run_groovy_script_checked "$base_url" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
import org.jenkins.plugins.lockableresources.RemoteConnection

def lrm = LockableResourcesManager.get()
lrm.setClientId(\"$client_id\")
lrm.setRemotes([new RemoteConnection(\"b\", \"$remote_url\", \"\")])
lrm.save()
println(\"OK: configured remote client $client_id -> $remote_url\")
" "OK: configured remote client $client_id -> $remote_url" >/dev/null
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
  rm -f "$cookie_jar"
  rm -f "$headers_file"

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
