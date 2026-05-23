#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

RESULTS_DIR="${1:-}"
if [[ -z "$RESULTS_DIR" ]]; then
  err "Results directory argument is required"
  exit 2
fi

SCENARIO="fan-in-contention"
SCENARIO_ID="S02"
SCENARIO_DIR="$RESULTS_DIR/$SCENARIO"
mkdir -p "$SCENARIO_DIR"

RESOURCE_NAME="s02-shared-$(date +%s)"
CREDENTIALS_ID="s02-for-b"
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
  printf -- "- SEQ%02d %s\n" "$SEQ_NO" "$text" >>"$SEQ_FILE"
}

scenario_checkpoint() {
  local step="$1"
  local action="$2"
  local expected="$3"
  local actual="$4"
  local result="$5"

  CP_NO=$((CP_NO + 1))
  printf '| CP%02d | %s | %s | %s | %s | %s |\n' \
    "$CP_NO" "$step" "$action" "$expected" "$actual" "$result" >>"$CP_FILE"
}

finalize_scenario_details() {
  {
    echo "### ${SCENARIO_ID}: ${SCENARIO}"
    echo ""
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
    echo "- holder-console: $SCENARIO_DIR/holder-console.txt"
    echo "- waiter-console: $SCENARIO_DIR/waiter-console.txt"
    echo "- summary: $SCENARIO_DIR/summary.txt"
  } >"$DETAIL_FILE"

  rm -f "$SEQ_FILE" "$CP_FILE"
}
trap finalize_scenario_details EXIT

scenario_sequence "Configure B remote server and A/C clients"
configure_remote_server "$CONTROLLER_B_URL" "$RESOURCE_NAME" "remote-enabled" "authenticated"
verify_remote_server_config "$CONTROLLER_B_URL" "$RESOURCE_NAME" "authenticated"
TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-s02-b-token")"
upsert_username_password_credential "$CONTROLLER_A_URL" "$CREDENTIALS_ID" "admin" "$TOKEN_B"
upsert_username_password_credential "$CONTROLLER_C_URL" "$CREDENTIALS_ID" "admin" "$TOKEN_B"
configure_remote_client_for_server "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "$CREDENTIALS_ID"
configure_remote_client_for_server "$CONTROLLER_C_URL" "jenkins-c" "b" "$CONTROLLER_B_INTERNAL_URL" "$CREDENTIALS_ID"
verify_remote_client_for_server "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "$CREDENTIALS_ID"
verify_remote_client_for_server "$CONTROLLER_C_URL" "jenkins-c" "b" "$CONTROLLER_B_INTERNAL_URL" "$CREDENTIALS_ID"
scenario_checkpoint "Remote setup" "Groovy settings" "B exposed and A/C linked" "configured and verified" "PASS"

HOLDER_SCRIPT="$(cat <<EOF
pipeline {
  agent any
  stages {
    stage("Hold") {
      steps {
        lock(resource: "${RESOURCE_NAME}", serverId: "b") {
          echo "HOLDER_ACQUIRED"
          sleep time: 25, unit: "SECONDS"
        }
      }
    }
  }
}
EOF
)"

WAITER_SCRIPT="$(cat <<EOF
pipeline {
  agent any
  stages {
    stage("Wait") {
      steps {
        lock(resource: "${RESOURCE_NAME}", serverId: "b") {
          echo "WAITER_ACQUIRED"
          sleep time: 5, unit: "SECONDS"
        }
      }
    }
  }
}
EOF
)"

upsert_pipeline_job "$CONTROLLER_A_URL" "s02-holder" "$HOLDER_SCRIPT"
upsert_pipeline_job "$CONTROLLER_C_URL" "s02-waiter" "$WAITER_SCRIPT"
scenario_checkpoint "Job upsert" "WorkflowJob upsert" "holder/waiter updated" "done" "PASS"

scenario_sequence "Trigger holder then waiter"
holder_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s02-holder" 120)"
if ! wait_for_console_contains "$holder_url" "HOLDER_ACQUIRED" 120; then
  scenario_checkpoint "Holder acquire" "ConsoleText" "HOLDER_ACQUIRED" "timeout" "FAIL"
  exit 1
fi
waiter_start="$(date +%s)"
waiter_url="$(trigger_and_resolve_build_url "$CONTROLLER_C_URL" "s02-waiter" 120)"
holder_result="$(wait_for_build_result "$holder_url" 900)"
waiter_result="$(wait_for_build_result "$waiter_url" 900)"
waiter_end="$(date +%s)"
waiter_duration="$((waiter_end - waiter_start))"

save_console_log "$holder_url" "$SCENARIO_DIR/holder-console.txt"
save_console_log "$waiter_url" "$SCENARIO_DIR/waiter-console.txt"

[[ "$holder_result" == "SUCCESS" ]] || { scenario_checkpoint "Holder result" "Build API" "SUCCESS" "$holder_result" "FAIL"; exit 1; }
[[ "$waiter_result" == "SUCCESS" ]] || { scenario_checkpoint "Waiter result" "Build API" "SUCCESS" "$waiter_result" "FAIL"; exit 1; }
scenario_checkpoint "Build results" "Build API" "holder/waiter SUCCESS" "holder=$holder_result waiter=$waiter_result" "PASS"

if [[ "$waiter_duration" -ge 15 ]]; then
  scenario_checkpoint "Wait evidence" "Elapsed time" ">= 15s" "${waiter_duration}s" "PASS"
else
  scenario_checkpoint "Wait evidence" "Elapsed time" ">= 15s" "${waiter_duration}s" "FAIL"
  exit 1
fi

if grep -Fq "WAITER_ACQUIRED" "$SCENARIO_DIR/waiter-console.txt"; then
  scenario_checkpoint "Waiter marker" "ConsoleText" "WAITER_ACQUIRED" "found" "PASS"
else
  scenario_checkpoint "Waiter marker" "ConsoleText" "WAITER_ACQUIRED" "missing" "FAIL"
  exit 1
fi

cat >"$SCENARIO_DIR/summary.txt" <<EOF
holder_build_url=$holder_url
holder_result=$holder_result
waiter_build_url=$waiter_url
waiter_result=$waiter_result
waiter_duration_seconds=$waiter_duration
EOF

log "fan-in-contention: completed"
