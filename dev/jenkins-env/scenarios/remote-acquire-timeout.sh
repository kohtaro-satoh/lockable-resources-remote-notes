#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

RESULTS_DIR="${1:-}"
if [[ -z "$RESULTS_DIR" ]]; then
  err "Results directory argument is required"
  exit 2
fi

SCENARIO="remote-acquire-timeout"
SCENARIO_ID="S18"
SCENARIO_DIR="$RESULTS_DIR/$SCENARIO"
mkdir -p "$SCENARIO_DIR"

RESOURCE_NAME="s18-shared-$(date +%s)"
CREDENTIALS_ID="s18-a-for-b"
DETAIL_FILE="$SCENARIO_DIR/scenario-details.md"

# Allocate-timeout MUST exceed the server-side terminal-record TTL (120s) to exercise the
# queued-expiry-poll-404 regression: a record that times out after a wait longer than the TTL
# becomes terminal only at the deadline. With the fix the FAILED record is retained from its
# terminal instant and the waiter observes a clean LOCK_WAIT_TIMEOUT; with the bug the record is
# evicted immediately and the poll 404s -> "communication failure / server may have restarted".
WAITER_TIMEOUT_SECONDS=130
HOLDER_HOLD_SECONDS=150

configure_remote_server "$CONTROLLER_B_URL" "$RESOURCE_NAME" "remote-enabled" "authenticated"
verify_remote_server_config "$CONTROLLER_B_URL" "$RESOURCE_NAME" "authenticated"
TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-s18-b-token")"
upsert_username_password_credential "$CONTROLLER_A_URL" "$CREDENTIALS_ID" "admin" "$TOKEN_B"
configure_remote_client_for_server "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "$CREDENTIALS_ID"
verify_remote_client_for_server "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "$CREDENTIALS_ID"

LOCAL_SCRIPT="$(cat <<EOF
pipeline {
  agent any
  stages {
    stage("LocalHold") {
      steps {
        lock(resource: "${RESOURCE_NAME}") {
          echo "LOCAL_HOLDER_ACQUIRED"
          sleep time: ${HOLDER_HOLD_SECONDS}, unit: "SECONDS"
        }
      }
    }
  }
}
EOF
)"

# Waiter: remote acquire with an allocate timeout > TERMINAL_TTL. The body must NOT run; the build
# must FAIL with errorCode=LOCK_WAIT_TIMEOUT (not a 404 / communication failure).
REMOTE_SCRIPT="$(cat <<EOF
pipeline {
  agent any
  stages {
    stage("RemoteWait") {
      steps {
        lock(resource: "${RESOURCE_NAME}", serverId: "b", timeoutForAllocateResource: ${WAITER_TIMEOUT_SECONDS}, timeoutUnit: "SECONDS") {
          echo "SHOULD_NOT_RUN"
        }
      }
    }
  }
}
EOF
)"

upsert_pipeline_job "$CONTROLLER_B_URL" "s18-local-holder" "$LOCAL_SCRIPT"
upsert_pipeline_job "$CONTROLLER_A_URL" "s18-remote-waiter" "$REMOTE_SCRIPT"

local_url="$(trigger_and_resolve_build_url "$CONTROLLER_B_URL" "s18-local-holder" 120)"
if ! wait_for_console_contains "$local_url" "LOCAL_HOLDER_ACQUIRED" 120; then
  err "remote-acquire-timeout: local holder did not acquire lock in time"
  exit 1
fi

waiter_start="$(date +%s)"
remote_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s18-remote-waiter" 120)"
remote_result="$(wait_for_build_result "$remote_url" 900)"
waiter_end="$(date +%s)"
waiter_duration="$((waiter_end - waiter_start))"
local_result="$(wait_for_build_result "$local_url" 900)"

save_console_log "$local_url" "$SCENARIO_DIR/local-holder-console.txt"
save_console_log "$remote_url" "$SCENARIO_DIR/remote-waiter-console.txt"

WAITER_CONSOLE="$SCENARIO_DIR/remote-waiter-console.txt"
RESULT="PASS"

# CP01: holder succeeded (held the resource throughout the waiter's allocate window)
[[ "$local_result" == "SUCCESS" ]] || { err "S18 CP01: local holder result=$local_result (expected SUCCESS)"; RESULT="FAIL"; }

# CP02: waiter build FAILED (allocate timeout, fail-closed)
[[ "$remote_result" == "FAILURE" ]] || { err "S18 CP02: waiter result=$remote_result (expected FAILURE)"; RESULT="FAIL"; }

# CP03 (core regression): the failure is reported as a clean LOCK_WAIT_TIMEOUT, NOT a 404/comm failure
if ! grep -Fq "LOCK_WAIT_TIMEOUT" "$WAITER_CONSOLE"; then
  err "S18 CP03: waiter console lacks LOCK_WAIT_TIMEOUT (regression: queued-expiry-poll-404)"
  RESULT="FAIL"
fi
if grep -Eq "server may have restarted|Remote API communication failure|returned HTTP 404" "$WAITER_CONSOLE"; then
  err "S18 CP03: waiter console shows a 404/communication-failure instead of a clean timeout"
  RESULT="FAIL"
fi

# CP04: fail-closed - the lock body must not have executed
if grep -Fq "SHOULD_NOT_RUN" "$WAITER_CONSOLE"; then
  err "S18 CP04: lock body executed despite acquire timeout (fail-open!)"
  RESULT="FAIL"
fi

# CP05: the waiter actually waited the allocate window (it timed out, not failed instantly)
if [[ "$waiter_duration" -lt 120 ]]; then
  err "S18 CP05: waiter failed too fast (${waiter_duration}s < 120s); not a genuine allocate timeout"
  RESULT="FAIL"
fi

cat >"$SCENARIO_DIR/summary.txt" <<EOF
local_build_url=$local_url
local_result=$local_result
remote_build_url=$remote_url
remote_result=$remote_result
waiter_allocate_timeout_seconds=$WAITER_TIMEOUT_SECONDS
waiter_wait_seconds=$waiter_duration
overall=$RESULT
EOF

{
  echo "### ${SCENARIO_ID}: ${SCENARIO}"
  echo ""
  echo "#### Summary"
  echo ""
  echo "- local holder result: $local_result"
  echo "- remote waiter result: $remote_result (expected FAILURE)"
  echo "- waiter allocate timeout: ${WAITER_TIMEOUT_SECONDS}s (> 120s terminal TTL)"
  echo "- waiter wait seconds: $waiter_duration"
  echo ""
  echo "#### Checkpoints"
  echo ""
  echo "| ID | Check | Expected |"
  echo "|---|---|---|"
  echo "| CP01 | local holder result | SUCCESS |"
  echo "| CP02 | remote waiter result | FAILURE (fail-closed) |"
  echo "| CP03 | waiter console errorCode | LOCK_WAIT_TIMEOUT (not 404 / communication failure) |"
  echo "| CP04 | lock body (SHOULD_NOT_RUN) | not executed |"
  echo "| CP05 | waiter wait | >= 120s (genuine allocate timeout) |"
  echo ""
  echo "Overall: $RESULT"
  echo ""
  echo "#### Artifacts"
  echo ""
  echo "- local holder console: $SCENARIO_DIR/local-holder-console.txt"
  echo "- remote waiter console: $SCENARIO_DIR/remote-waiter-console.txt"
  echo "- summary: $SCENARIO_DIR/summary.txt"
} >"$DETAIL_FILE"

if [[ "$RESULT" != "PASS" ]]; then
  err "remote-acquire-timeout: FAILED"
  exit 1
fi

log "remote-acquire-timeout: completed"
