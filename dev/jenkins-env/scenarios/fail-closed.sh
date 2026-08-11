#!/usr/bin/env bash
set -euo pipefail

# S07: everything that can go wrong between the client and the server must leave the body unrun.
#
# The one invariant: a lock the client could not prove it holds is not a lock. Five different faults
# - the server gone, the network black-holed, a bad token, a credentials id that resolves to nothing,
# and one that resolves to the wrong type of credential - must all end the same way, with the build
# FAILED and the body never entered. The cases run in one scenario because they share the setup and
# because "all five" is the actual claim.
#
# Each case restores what it broke before the next one starts, and the cleanup hook puts the world
# back even if the scenario dies in the middle - otherwise a failure here leaves B stopped and every
# scenario after it fails for the wrong reason.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "S07" "fail-closed" "${1:-}"

RESOURCE_NAME="s07-fail-board-$(scenario_stamp)"
VALID_CREDENTIALS_ID="s07-a-for-b"
INVALID_AUTH_CREDENTIALS_ID="s07-invalid-auth-creds"
MISSING_CREDENTIALS_ID="s07-missing-creds"
TYPE_MISMATCH_CREDENTIALS_ID="s07-type-mismatch-creds"

restore_environment() {
  docker_compose up -d jenkins-b
  wait_for_url "$CONTROLLER_B_URL/login" 240
  configure_remote_server "$CONTROLLER_B_URL" "$RESOURCE_NAME" "remote-enabled" "authenticated"
  configure_remote_client_for_server \
    "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "$VALID_CREDENTIALS_ID"
}
scenario_cleanup_hook restore_environment

scenario_step "Expose the resource on B and link A to it with a working credential"
setup_remote_pair "s07" "a" "b" "$RESOURCE_NAME"
scenario_check "Baseline setup" "Groovy /scriptText" "A->B configured and verified" "A->B configured and verified"

FAILURE_SCRIPT="$(cat <<EOF
pipeline {
  agent any
  stages {
    stage("FailClosed") {
      steps {
        lock(resource: "${RESOURCE_NAME}", serverId: "b") {
          echo "UNEXPECTED_BODY_EXECUTION"
        }
      }
    }
  }
}
EOF
)"

# run_failure_case <case> <job> <what the client should hit> <console evidence regex>
run_failure_case() {
  local case_name="$1"
  local job_name="$2"
  local api_behaviour="$3"
  local error_hint="$4"
  local case_dir="$SCENARIO_DIR/$case_name"

  mkdir -p "$case_dir"
  upsert_pipeline_job "$CONTROLLER_A_URL" "$job_name" "$FAILURE_SCRIPT"

  local build_url result
  build_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "$job_name" 120)"
  result="$(wait_for_build_result "$build_url" 600)"
  save_console_log "$build_url" "$case_dir/console.txt"
  scenario_artifact "$case_name console" "$case_dir/console.txt"

  scenario_check "$case_name: build failed closed" "$api_behaviour" "FAILURE" "$result"
  scenario_check_absent "$case_name: body never ran" "$case_dir/console.txt" "UNEXPECTED_BODY_EXECUTION"

  # The wording of a client-side error is not a contract, so a missing hint is a WARN: it means the
  # scenario can no longer prove the build failed for the reason it engineered, not that it passed.
  local matched="false"
  grep -Eqi "$error_hint" "$case_dir/console.txt" && matched="true"
  scenario_check_soft "$case_name: failed for the engineered reason" "console evidence" \
    "matches /$error_hint/" "$matched" "$matched"

  scenario_fact "${case_name}_result" "$result"
  scenario_fact "${case_name}_build_url" "$build_url"
}

scenario_step "Case remote-down: stop the server outright"
docker_compose stop jenkins-b
run_failure_case "remote-down" "s07-fail-remote-down" \
  "POST /acquire cannot connect" \
  "Remote API communication failure|Connection refused|ConnectException|No route to host"
docker_compose up -d jenkins-b
wait_for_url "$CONTROLLER_B_URL/login" 240 ||
  scenario_require_ok "Controller B recovers" "wait_for_url" "B did not come back after remote-down"
configure_remote_server "$CONTROLLER_B_URL" "$RESOURCE_NAME" "remote-enabled" "authenticated"

scenario_step "Case timeout: point the client at an unroutable address"
configure_remote_client_for_server \
  "$CONTROLLER_A_URL" "jenkins-a" "b" "http://10.255.255.1:18082/jenkins" "$VALID_CREDENTIALS_ID"
run_failure_case "timeout" "s07-fail-timeout" \
  "POST /acquire times out" \
  "timed out|HttpTimeoutException|timeout"
configure_remote_client_for_server \
  "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "$VALID_CREDENTIALS_ID"

scenario_step "Case auth-error: a credential holding a token the server will not accept"
upsert_username_password_credential "$CONTROLLER_A_URL" "$INVALID_AUTH_CREDENTIALS_ID" "admin" "not-a-valid-api-token"
configure_remote_client_for_server \
  "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "$INVALID_AUTH_CREDENTIALS_ID"
run_failure_case "auth-error" "s07-fail-auth" \
  "POST /acquire is rejected with 401/403" \
  "HTTP 401|HTTP 403|returned HTTP 401|returned HTTP 403|Sign in to access"

scenario_step "Case missing-credentials-id: a credentials id that resolves to nothing"
configure_remote_client_for_server \
  "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "$MISSING_CREDENTIALS_ID"
run_failure_case "missing-credentials-id" "s07-fail-missing-credentials" \
  "the client cannot resolve credentialsId, and must not fall back to anonymous" \
  "Remote credentials not found for serverId=b, credentialsId=${MISSING_CREDENTIALS_ID}"

scenario_step "Case credentials-type-mismatch: a secret-text credential where a username/password is required"
upsert_string_credential "$CONTROLLER_A_URL" "$TYPE_MISMATCH_CREDENTIALS_ID" "dummy-secret"
configure_remote_client_for_server \
  "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "$TYPE_MISMATCH_CREDENTIALS_ID"
run_failure_case "credentials-type-mismatch" "s07-fail-credentials-type-mismatch" \
  "the client rejects a credential of the wrong type rather than coercing it" \
  "Remote credentials not found for serverId=b, credentialsId=${TYPE_MISMATCH_CREDENTIALS_ID}"

scenario_step "Check no fault left the resource held on B"
configure_remote_client_for_server \
  "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "$VALID_CREDENTIALS_ID"
scenario_check_resource_free "Resource free after all five faults" "b" "$RESOURCE_NAME"

scenario_finish
