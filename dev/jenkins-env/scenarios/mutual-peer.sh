#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

RESULTS_DIR="${1:-}"
if [[ -z "$RESULTS_DIR" ]]; then
  err "Results directory argument is required"
  exit 2
fi

SCENARIO="mutual-peer"
SCENARIO_ID="S01"
SCENARIO_DIR="$RESULTS_DIR/$SCENARIO"
mkdir -p "$SCENARIO_DIR"

A_RESOURCE="s01-a-resource-$(date +%s)"
B_RESOURCE="s01-b-resource-$(date +%s)"
A_CRED="s01-a-for-b"
B_CRED="s01-b-for-a"
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
    echo "- a-console: $SCENARIO_DIR/a-console.txt"
    echo "- b-console: $SCENARIO_DIR/b-console.txt"
    echo "- summary: $SCENARIO_DIR/summary.txt"
  } >"$DETAIL_FILE"

  rm -f "$SEQ_FILE" "$CP_FILE"
}
trap finalize_scenario_details EXIT

scenario_sequence "Configure A/B as remote servers"
configure_remote_server "$CONTROLLER_A_URL" "$A_RESOURCE" "remote-enabled" "authenticated"
configure_remote_server "$CONTROLLER_B_URL" "$B_RESOURCE" "remote-enabled" "authenticated"
verify_remote_server_config "$CONTROLLER_A_URL" "$A_RESOURCE" "authenticated"
verify_remote_server_config "$CONTROLLER_B_URL" "$B_RESOURCE" "authenticated"
scenario_checkpoint "Remote server setup" "Groovy /scriptText" "A/B remote server ready" "configured and verified" "PASS"

scenario_sequence "Issue API token and configure credentials"
TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-s01-b-token")"
TOKEN_A="$(issue_user_api_token "$CONTROLLER_A_URL" "admin" "e2e-s01-a-token")"
upsert_username_password_credential "$CONTROLLER_A_URL" "$A_CRED" "admin" "$TOKEN_B"
upsert_username_password_credential "$CONTROLLER_B_URL" "$B_CRED" "admin" "$TOKEN_A"
scenario_checkpoint "Credentials setup" "ApiToken + Credentials upsert" "s01 creds exist" "created on A/B" "PASS"

scenario_sequence "Configure remote clients A->B and B->A"
configure_remote_client_for_server "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "$A_CRED"
configure_remote_client_for_server "$CONTROLLER_B_URL" "jenkins-b" "a" "$CONTROLLER_A_INTERNAL_URL" "$B_CRED"
verify_remote_client_for_server "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "$A_CRED"
verify_remote_client_for_server "$CONTROLLER_B_URL" "jenkins-b" "a" "$CONTROLLER_A_INTERNAL_URL" "$B_CRED"
scenario_checkpoint "Remote client setup" "Groovy remotes map" "A->B and B->A" "configured and verified" "PASS"

A_SCRIPT="$(cat <<EOF
pipeline {
  agent any
  stages {
    stage("AtoB") {
      steps {
        lock(resource: "${B_RESOURCE}", serverId: "b") {
          echo "A_ACQUIRED"
          sleep time: 20, unit: "SECONDS"
        }
      }
    }
  }
}
EOF
)"

B_SCRIPT="$(cat <<EOF
pipeline {
  agent any
  stages {
    stage("BtoA") {
      steps {
        lock(resource: "${A_RESOURCE}", serverId: "a") {
          echo "B_ACQUIRED"
          sleep time: 20, unit: "SECONDS"
        }
      }
    }
  }
}
EOF
)"

upsert_pipeline_job "$CONTROLLER_A_URL" "s01-a-holder" "$A_SCRIPT"
upsert_pipeline_job "$CONTROLLER_B_URL" "s01-b-holder" "$B_SCRIPT"

scenario_sequence "Trigger A/B jobs"
start_epoch="$(date +%s)"
a_build_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s01-a-holder" 120)"
b_build_url="$(trigger_and_resolve_build_url "$CONTROLLER_B_URL" "s01-b-holder" 120)"
a_result="$(wait_for_build_result "$a_build_url" 900)"
b_result="$(wait_for_build_result "$b_build_url" 900)"
end_epoch="$(date +%s)"
duration="$((end_epoch - start_epoch))"

save_console_log "$a_build_url" "$SCENARIO_DIR/a-console.txt"
save_console_log "$b_build_url" "$SCENARIO_DIR/b-console.txt"

[[ "$a_result" == "SUCCESS" ]] || { scenario_checkpoint "A build" "Build API" "SUCCESS" "$a_result" "FAIL"; exit 1; }
[[ "$b_result" == "SUCCESS" ]] || { scenario_checkpoint "B build" "Build API" "SUCCESS" "$b_result" "FAIL"; exit 1; }
scenario_checkpoint "Build results" "Build API" "A/B SUCCESS" "A=$a_result B=$b_result" "PASS"

if grep -Fq "A_ACQUIRED" "$SCENARIO_DIR/a-console.txt" && grep -Fq "B_ACQUIRED" "$SCENARIO_DIR/b-console.txt"; then
  scenario_checkpoint "Acquire markers" "ConsoleText" "A_ACQUIRED and B_ACQUIRED" "both found" "PASS"
else
  scenario_checkpoint "Acquire markers" "ConsoleText" "A_ACQUIRED and B_ACQUIRED" "marker missing" "FAIL"
  exit 1
fi

if [[ "$duration" -lt 60 ]]; then
  scenario_checkpoint "Parallel execution" "Elapsed time" "< 60s" "${duration}s" "PASS"
else
  scenario_checkpoint "Parallel execution" "Elapsed time" "< 60s" "${duration}s" "WARN"
fi

cat >"$SCENARIO_DIR/summary.txt" <<EOF
a_build_url=$a_build_url
a_result=$a_result
b_build_url=$b_build_url
b_result=$b_result
duration_seconds=$duration
EOF

log "mutual-peer: completed"
