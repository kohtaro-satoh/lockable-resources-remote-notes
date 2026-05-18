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

SCENARIO_DIR="$RESULTS_DIR/peer-basic"
mkdir -p "$SCENARIO_DIR"
RESOURCE_NAME="step8-board-$(date +%s)"
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
    echo "- holder build: ${holder_build_url:-N/A}"
    echo "- waiter build: ${waiter_build_url:-N/A}"
    echo "- holder console: $SCENARIO_DIR/holder-console.txt"
    echo "- waiter console: $SCENARIO_DIR/waiter-console.txt"
    echo "- summary: $SCENARIO_DIR/summary.txt"
  } >"$DETAIL_FILE"

  rm -f "$SEQ_FILE" "$CP_FILE"
}
trap finalize_scenario_details EXIT

log "peer-basic: configure controllers"
scenario_sequence "Configure Controller B as remote server and create exposed resource ${RESOURCE_NAME}"
configure_controller_b_remote_server "$RESOURCE_NAME"
verify_controller_b_remote_server_config "$RESOURCE_NAME"
scenario_checkpoint \
  "Controller B remote server configuration" \
  "Groovy /scriptText (set remoteApiEnabled, exposeLabel, resource)" \
  "remoteApiEnabled=true and resourceExposed=true" \
  "verify_controller_b_remote_server_config passed" \
  "PASS"

scenario_sequence "Configure Controllers A and C as remote clients (serverId=b)"
configure_remote_client "$CONTROLLER_A_URL" "jenkins-a" "$CONTROLLER_B_INTERNAL_URL"
configure_remote_client "$CONTROLLER_C_URL" "jenkins-c" "$CONTROLLER_B_INTERNAL_URL"
scenario_checkpoint \
  "Controller A/C remote client configuration" \
  "Groovy /scriptText (set remotes=[b->8082])" \
  "A/C can reference Controller B remote API" \
  "configure_remote_client completed for A and C" \
  "PASS"

holder_script="$(cat <<EOF
pipeline {
  agent any
  stages {
    stage("Hold") {
      steps {
        lock(resource: "${RESOURCE_NAME}", serverId: "b") {
          echo "HOLDER_ACQUIRED"
          sleep time: 25, unit: "SECONDS"
          echo "HOLDER_RELEASED"
        }
      }
    }
  }
}
EOF
)"

waiter_script="$(cat <<EOF
pipeline {
  agent any
  stages {
    stage("Wait") {
      steps {
        lock(resource: "${RESOURCE_NAME}", serverId: "b") {
          echo "WAITER_ACQUIRED"
          sleep time: 1, unit: "SECONDS"
        }
      }
    }
  }
}
EOF
)"

upsert_pipeline_job "$CONTROLLER_A_URL" "step8-peer-holder" "$holder_script"
upsert_pipeline_job "$CONTROLLER_C_URL" "step8-peer-waiter" "$waiter_script"
scenario_sequence "Create or update holder/waiter pipeline jobs"
scenario_checkpoint \
  "Pipeline job upsert" \
  "Groovy /scriptText (WorkflowJob upsert)" \
  "step8-peer-holder and step8-peer-waiter are updated" \
  "upsert_pipeline_job completed" \
  "PASS"

log "peer-basic: trigger holder build"
scenario_sequence "Trigger holder build and wait for lock acquisition signal"
holder_build_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "step8-peer-holder" 120)"

if ! wait_for_console_contains "$holder_build_url" "HOLDER_ACQUIRED" 120; then
  err "peer-basic: holder did not acquire lock in time"
  save_console_log "$holder_build_url" "$SCENARIO_DIR/holder-console.txt" || true
  scenario_checkpoint \
    "Holder lock acquisition" \
    "POST /lockable-resources/remote/v1/acquire/ -> 202, GET /acquire/{lockId}/ -> ACQUIRED" \
    "HOLDER_ACQUIRED appears within 120 seconds" \
    "Timed out waiting for HOLDER_ACQUIRED" \
    "FAIL"
  exit 1
fi
scenario_checkpoint \
  "Holder lock acquisition" \
  "POST /lockable-resources/remote/v1/acquire/ -> 202, GET /acquire/{lockId}/ -> ACQUIRED" \
  "HOLDER_ACQUIRED appears within 120 seconds" \
  "HOLDER_ACQUIRED observed" \
  "PASS"

log "peer-basic: trigger waiter build"
scenario_sequence "Trigger waiter build and validate it waits until holder releases"
waiter_start_epoch="$(date +%s)"
waiter_build_url="$(trigger_and_resolve_build_url "$CONTROLLER_C_URL" "step8-peer-waiter" 120)"

holder_result="$(wait_for_build_result "$holder_build_url" 900)"
waiter_result="$(wait_for_build_result "$waiter_build_url" 900)"
waiter_end_epoch="$(date +%s)"
waiter_duration_seconds=$((waiter_end_epoch - waiter_start_epoch))

save_console_log "$holder_build_url" "$SCENARIO_DIR/holder-console.txt"
save_console_log "$waiter_build_url" "$SCENARIO_DIR/waiter-console.txt"

if [[ "$holder_result" != "SUCCESS" ]]; then
  scenario_checkpoint \
    "Holder build result" \
    "Jenkins Build API" \
    "SUCCESS" \
    "$holder_result" \
    "FAIL"
  exit 1
fi
scenario_checkpoint \
  "Holder build result" \
  "Jenkins Build API" \
  "SUCCESS" \
  "$holder_result" \
  "PASS"

if [[ "$waiter_result" != "SUCCESS" ]]; then
  scenario_checkpoint \
    "Waiter build result" \
    "Jenkins Build API" \
    "SUCCESS" \
    "$waiter_result" \
    "FAIL"
  exit 1
fi
scenario_checkpoint \
  "Waiter build result" \
  "Jenkins Build API" \
  "SUCCESS" \
  "$waiter_result" \
  "PASS"

if [[ "$waiter_duration_seconds" -lt 15 ]]; then
  scenario_checkpoint \
    "Waiter wait duration" \
    "Elapsed time between waiter trigger and completion" \
    ">= 15s (lock wait should happen)" \
    "${waiter_duration_seconds}s" \
    "FAIL"
  exit 1
fi
scenario_checkpoint \
  "Waiter wait duration" \
  "Elapsed time between waiter trigger and completion" \
  ">= 15s (lock wait should happen)" \
  "${waiter_duration_seconds}s" \
  "PASS"

if ! grep -Fq "WAITER_ACQUIRED" "$SCENARIO_DIR/waiter-console.txt"; then
  err "peer-basic: waiter console does not contain WAITER_ACQUIRED"
  scenario_checkpoint \
    "Waiter console marker" \
    "Waiter console log" \
    "WAITER_ACQUIRED is present" \
    "Marker not found" \
    "FAIL"
  exit 1
fi
scenario_checkpoint \
  "Waiter console marker" \
  "Waiter console log" \
  "WAITER_ACQUIRED is present" \
  "WAITER_ACQUIRED found" \
  "PASS"

if grep -Fq "Remote acquire enqueued" "$SCENARIO_DIR/holder-console.txt" \
  && grep -Fq "Remote lock acquired on" "$SCENARIO_DIR/holder-console.txt" \
  && grep -Fq "Remote lock released on" "$SCENARIO_DIR/holder-console.txt"; then
  scenario_checkpoint \
    "Remote API lifecycle evidence" \
    "POST /acquire/ -> GET /acquire/{lockId}/ -> POST /lease/{lockId}/release" \
    "enqueue/acquired/released markers exist in holder console" \
    "All lifecycle markers found in holder-console" \
    "PASS"
else
  scenario_checkpoint \
    "Remote API lifecycle evidence" \
    "POST /acquire/ -> GET /acquire/{lockId}/ -> POST /lease/{lockId}/release" \
    "enqueue/acquired/released markers exist in holder console" \
    "One or more lifecycle markers missing" \
    "WARN"
fi

cat >"$SCENARIO_DIR/summary.txt" <<EOF
holder_build_url=$holder_build_url
holder_result=$holder_result
waiter_build_url=$waiter_build_url
waiter_result=$waiter_result
waiter_duration_seconds=$waiter_duration_seconds
EOF

log "peer-basic: completed"
