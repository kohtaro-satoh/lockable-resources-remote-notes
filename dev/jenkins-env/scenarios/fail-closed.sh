#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

RESULTS_DIR="${1:-}"
if [[ -z "$RESULTS_DIR" ]]; then
  err "Results directory argument is required"
  exit 2
fi

SCENARIO_DIR="$RESULTS_DIR/fail-closed"
mkdir -p "$SCENARIO_DIR"
RESOURCE_NAME="step8-fail-board-$(date +%s)"
VALID_CREDENTIALS_ID="step8-fail-valid-creds"
INVALID_AUTH_CREDENTIALS_ID="step8-fail-invalid-auth-creds"
MISSING_CREDENTIALS_ID="step8-fail-missing-creds"
TYPE_MISMATCH_CREDENTIALS_ID="step8-fail-type-mismatch-creds"
DETAIL_FILE="$SCENARIO_DIR/scenario-details.md"
SEQ_FILE="$SCENARIO_DIR/.sequence.tmp"
CP_FILE="$SCENARIO_DIR/.checkpoints.tmp"
SEQ_NO=0
CP_NO=0

: >"$SEQ_FILE"
: >"$CP_FILE"

scenario_sequence() {
  local text="$1"
  SEQ_NO=$((SEQ_NO + 1))
  printf -- "- S%02d %s\n" "$SEQ_NO" "$text" >>"$SEQ_FILE"
}

scenario_checkpoint() {
  local step="$1"
  local api_action="$2"
  local expected="$3"
  local actual="$4"
  local result="$5"

  CP_NO=$((CP_NO + 1))
  printf '| CP%02d | %s | %s | %s | %s | %s |\n' \
    "$CP_NO" "$step" "$api_action" "$expected" "$actual" "$result" >>"$CP_FILE"
}

finalize_scenario_details() {
  {
    echo "#### Sequence"
    echo ""
    cat "$SEQ_FILE"
    echo ""
    echo "#### Checkpoints"
    echo ""
    echo "| ID | Step | API / Action | Expected | Actual | Result |"
    echo "|---|---|---|---|---|---|"
    cat "$CP_FILE"
    echo ""
    echo "#### Artifacts"
    echo ""
    echo "- scenario dir: $SCENARIO_DIR"
    echo "- remote-down console: $SCENARIO_DIR/remote-down/console.txt"
    echo "- timeout console: $SCENARIO_DIR/timeout/console.txt"
    echo "- auth-error console: $SCENARIO_DIR/auth-error/console.txt"
    echo "- missing-credentials-id console: $SCENARIO_DIR/missing-credentials-id/console.txt"
    echo "- credentials-type-mismatch console: $SCENARIO_DIR/credentials-type-mismatch/console.txt"
  } >"$DETAIL_FILE"

  rm -f "$SEQ_FILE" "$CP_FILE"
}

setup_base() {
  scenario_sequence "Configure Controller B as authenticated remote server and create exposed resource ${RESOURCE_NAME}"
  configure_controller_b_remote_server "$RESOURCE_NAME" "authenticated"
  verify_controller_b_remote_server_config "$RESOURCE_NAME" "authenticated"
  scenario_checkpoint \
    "Controller B remote server configuration" \
    "Groovy /scriptText (set auth mode, remoteApiEnabled, exposeLabel, resource)" \
    "authenticatedMode=true, remoteApiEnabled=true and resourceExposed=true" \
    "verify_controller_b_remote_server_config(authenticated) passed" \
    "PASS"

  scenario_sequence "Issue API token for Controller B admin and create valid username/password credential on Controller A"
  local valid_remote_token
  valid_remote_token="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-fail-closed-valid-token")"
  upsert_username_password_credential "$CONTROLLER_A_URL" "$VALID_CREDENTIALS_ID" "admin" "$valid_remote_token"
  scenario_checkpoint \
    "Controller A credentials upsert" \
    "Groovy /scriptText (ApiTokenProperty issue + SystemCredentialsProvider upsert)" \
    "credential id=${VALID_CREDENTIALS_ID} exists on A and password field contains B-side API token" \
    "issue_user_api_token + upsert_username_password_credential completed" \
    "PASS"

  scenario_sequence "Configure Controller A as remote client with credentials (serverId=b)"
  configure_remote_client "$CONTROLLER_A_URL" "jenkins-a" "$CONTROLLER_B_INTERNAL_URL" "$VALID_CREDENTIALS_ID"
  verify_remote_client_config "$CONTROLLER_A_URL" "jenkins-a" "$CONTROLLER_B_INTERNAL_URL" "$VALID_CREDENTIALS_ID"
  scenario_checkpoint \
    "Controller A remote client configuration" \
    "Groovy /scriptText (set remotes=[b->8082], credentialsId)" \
    "Controller A remotes point to B with credentialsId=${VALID_CREDENTIALS_ID}" \
    "configure_remote_client + verify_remote_client_config completed" \
    "PASS"
}

cleanup() {
  docker_compose up -d jenkins-b >/dev/null 2>&1 || true
  wait_for_url "$CONTROLLER_B_URL/login" 240 >/dev/null 2>&1 || true
  configure_controller_b_remote_server "$RESOURCE_NAME" "authenticated" >/dev/null 2>&1 || true
  configure_remote_client "$CONTROLLER_A_URL" "jenkins-a" "$CONTROLLER_B_INTERNAL_URL" "$VALID_CREDENTIALS_ID" >/dev/null 2>&1 || true
}
trap 'cleanup; finalize_scenario_details' EXIT

setup_base

failure_script="$(cat <<EOF
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

run_failure_case() {
  local case_name="$1"
  local job_name="$2"
  local timeout_seconds="$3"
  local expected_api_behavior="$4"
  local expected_error_hint="$5"
  local case_dir="$SCENARIO_DIR/$case_name"

  mkdir -p "$case_dir"
  upsert_pipeline_job "$CONTROLLER_A_URL" "$job_name" "$failure_script"
  scenario_checkpoint \
    "$case_name: pipeline job upsert" \
    "Groovy /scriptText (WorkflowJob upsert)" \
    "$job_name is updated" \
    "upsert_pipeline_job completed" \
    "PASS"

  log "fail-closed: trigger case=$case_name"
  scenario_sequence "Run case=$case_name and verify it fails closed without executing lock body"
  local build_url
  build_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "$job_name" 120)"
  local result
  result="$(wait_for_build_result "$build_url" "$timeout_seconds")"

  save_console_log "$build_url" "$case_dir/console.txt"
  cat >"$case_dir/summary.txt" <<EOF
build_url=$build_url
result=$result
EOF

  if [[ "$result" != "FAILURE" ]]; then
    scenario_checkpoint \
      "$case_name: build result" \
      "$expected_api_behavior" \
      "FAILURE (fail-closed)" \
      "$result" \
      "FAIL"
    return 1
  fi
  scenario_checkpoint \
    "$case_name: build result" \
    "$expected_api_behavior" \
    "FAILURE (fail-closed)" \
    "$result" \
    "PASS"

  if grep -Eqi "$expected_error_hint" "$case_dir/console.txt"; then
    scenario_checkpoint \
      "$case_name: expected error evidence" \
      "$expected_api_behavior" \
      "Console contains expected error hint" \
      "Matched /$expected_error_hint/" \
      "PASS"
  else
    scenario_checkpoint \
      "$case_name: expected error evidence" \
      "$expected_api_behavior" \
      "Console contains expected error hint" \
      "No match for /$expected_error_hint/" \
      "WARN"
  fi

  if grep -Fq "UNEXPECTED_BODY_EXECUTION" "$case_dir/console.txt"; then
    err "fail-closed: case=$case_name unexpectedly executed lock body"
    scenario_checkpoint \
      "$case_name: lock body guard" \
      "Pipeline lock body" \
      "UNEXPECTED_BODY_EXECUTION is absent" \
      "UNEXPECTED_BODY_EXECUTION found" \
      "FAIL"
    return 1
  fi
  scenario_checkpoint \
    "$case_name: lock body guard" \
    "Pipeline lock body" \
    "UNEXPECTED_BODY_EXECUTION is absent" \
    "Marker not found" \
    "PASS"
}

log "fail-closed: case remote-down"
scenario_sequence "Case remote-down: stop Controller B to simulate remote API unavailability"
docker_compose stop jenkins-b
run_failure_case \
  "remote-down" \
  "step8-fail-remote-down" \
  600 \
  "POST /acquire/ or GET /acquire/{lockId}/ fails due to connection issue" \
  "Remote API communication failure|Connection refused|ConnectException|No route to host"
docker_compose up -d jenkins-b
if ! wait_for_url "$CONTROLLER_B_URL/login" 240; then
  err "fail-closed: controller B did not recover after remote-down case"
  exit 1
fi
configure_controller_b_remote_server "$RESOURCE_NAME" "authenticated"

log "fail-closed: case timeout"
scenario_sequence "Case timeout: point Controller A remote URL to unroutable IP to trigger timeout"
configure_remote_client "$CONTROLLER_A_URL" "jenkins-a" "http://10.255.255.1:18082/jenkins" "$VALID_CREDENTIALS_ID"
run_failure_case \
  "timeout" \
  "step8-fail-timeout" \
  600 \
  "POST /acquire/ times out" \
  "timed out|HttpTimeoutException|timeout"
configure_remote_client "$CONTROLLER_A_URL" "jenkins-a" "$CONTROLLER_B_INTERNAL_URL" "$VALID_CREDENTIALS_ID"

log "fail-closed: case auth-error"
scenario_sequence "Case auth-error: use invalid API token credential and expect 401/403"
upsert_username_password_credential "$CONTROLLER_A_URL" "$INVALID_AUTH_CREDENTIALS_ID" "admin" "not-a-valid-api-token"
configure_remote_client "$CONTROLLER_A_URL" "jenkins-a" "$CONTROLLER_B_INTERNAL_URL" "$INVALID_AUTH_CREDENTIALS_ID"
run_failure_case \
  "auth-error" \
  "step8-fail-auth" \
  600 \
  "POST /acquire/ returns HTTP 401/403 due to invalid Authorization" \
  "HTTP 401|HTTP 403|returned HTTP 401|returned HTTP 403|Sign in to access"

log "fail-closed: case missing-credentials-id"
scenario_sequence "Case missing-credentials-id: configure unknown credentialsId and expect fail-fast"
configure_remote_client "$CONTROLLER_A_URL" "jenkins-a" "$CONTROLLER_B_INTERNAL_URL" "$MISSING_CREDENTIALS_ID"
run_failure_case \
  "missing-credentials-id" \
  "step8-fail-missing-credentials" \
  600 \
  "LockStepExecution.resolveAuthorizationHeader() cannot resolve credentialsId" \
  "Remote credentials not found for serverId=b, credentialsId=${MISSING_CREDENTIALS_ID}"

log "fail-closed: case credentials-type-mismatch"
scenario_sequence "Case credentials-type-mismatch: configure secret-text credential id and expect fail-fast"
upsert_string_credential "$CONTROLLER_A_URL" "$TYPE_MISMATCH_CREDENTIALS_ID" "dummy-secret"
configure_remote_client "$CONTROLLER_A_URL" "jenkins-a" "$CONTROLLER_B_INTERNAL_URL" "$TYPE_MISMATCH_CREDENTIALS_ID"
run_failure_case \
  "credentials-type-mismatch" \
  "step8-fail-credentials-type-mismatch" \
  600 \
  "LockStepExecution.resolveAuthorizationHeader() rejects non-username/password credential" \
  "Remote credentials not found for serverId=b, credentialsId=${TYPE_MISMATCH_CREDENTIALS_ID}"

configure_remote_client "$CONTROLLER_A_URL" "jenkins-a" "$CONTROLLER_B_INTERNAL_URL" "$VALID_CREDENTIALS_ID"

log "fail-closed: completed"
