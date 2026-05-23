#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

RESULTS_DIR="${1:-}"
if [[ -z "$RESULTS_DIR" ]]; then
  err "Results directory argument is required"
  exit 2
fi

if ! wait_for_url "$CONTROLLER_D_URL/login" 20; then
  log "fan-in-4: jenkins-d is not available, skip"
  exit 10
fi

SCENARIO="fan-in-4"
SCENARIO_ID="D01"
SCENARIO_DIR="$RESULTS_DIR/$SCENARIO"
mkdir -p "$SCENARIO_DIR"

RESOURCE_NAME="d01-shared-d-$(date +%s)"
CREDENTIALS_ID="d01-for-d"

configure_remote_server "$CONTROLLER_D_URL" "$RESOURCE_NAME" "remote-enabled" "authenticated"
TOKEN_D="$(issue_user_api_token "$CONTROLLER_D_URL" "admin" "e2e-d01-d-token")"

upsert_username_password_credential "$CONTROLLER_A_URL" "$CREDENTIALS_ID" "admin" "$TOKEN_D"
upsert_username_password_credential "$CONTROLLER_B_URL" "$CREDENTIALS_ID" "admin" "$TOKEN_D"
upsert_username_password_credential "$CONTROLLER_C_URL" "$CREDENTIALS_ID" "admin" "$TOKEN_D"

configure_remote_client_for_server "$CONTROLLER_A_URL" "jenkins-a" "d" "$CONTROLLER_D_INTERNAL_URL" "$CREDENTIALS_ID"
configure_remote_client_for_server "$CONTROLLER_B_URL" "jenkins-b" "d" "$CONTROLLER_D_INTERNAL_URL" "$CREDENTIALS_ID"
configure_remote_client_for_server "$CONTROLLER_C_URL" "jenkins-c" "d" "$CONTROLLER_D_INTERNAL_URL" "$CREDENTIALS_ID"

A_SCRIPT="$(cat <<EOF
pipeline { agent any; stages { stage('A') { steps { lock(resource: "${RESOURCE_NAME}", serverId: 'd') { echo 'A_ACQUIRED'; sleep time: 20, unit: 'SECONDS' } } } } }
EOF
)"
B_SCRIPT="$(cat <<EOF
pipeline { agent any; stages { stage('B') { steps { lock(resource: "${RESOURCE_NAME}", serverId: 'd') { echo 'B_ACQUIRED'; sleep time: 5, unit: 'SECONDS' } } } } }
EOF
)"
C_SCRIPT="$(cat <<EOF
pipeline { agent any; stages { stage('C') { steps { lock(resource: "${RESOURCE_NAME}", serverId: 'd') { echo 'C_ACQUIRED'; sleep time: 5, unit: 'SECONDS' } } } } }
EOF
)"

upsert_pipeline_job "$CONTROLLER_A_URL" "d01-a" "$A_SCRIPT"
upsert_pipeline_job "$CONTROLLER_B_URL" "d01-b" "$B_SCRIPT"
upsert_pipeline_job "$CONTROLLER_C_URL" "d01-c" "$C_SCRIPT"

a_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "d01-a" 120)"
b_url="$(trigger_and_resolve_build_url "$CONTROLLER_B_URL" "d01-b" 120)"
c_url="$(trigger_and_resolve_build_url "$CONTROLLER_C_URL" "d01-c" 120)"

ar="$(wait_for_build_result "$a_url" 900)"
br="$(wait_for_build_result "$b_url" 900)"
cr="$(wait_for_build_result "$c_url" 900)"

save_console_log "$a_url" "$SCENARIO_DIR/a-console.txt"
save_console_log "$b_url" "$SCENARIO_DIR/b-console.txt"
save_console_log "$c_url" "$SCENARIO_DIR/c-console.txt"

[[ "$ar" == "SUCCESS" && "$br" == "SUCCESS" && "$cr" == "SUCCESS" ]] || exit 1

grep -Fq "A_ACQUIRED" "$SCENARIO_DIR/a-console.txt" || exit 1
grep -Fq "B_ACQUIRED" "$SCENARIO_DIR/b-console.txt" || exit 1
grep -Fq "C_ACQUIRED" "$SCENARIO_DIR/c-console.txt" || exit 1

cat >"$SCENARIO_DIR/summary.txt" <<EOF
a_result=$ar
b_result=$br
c_result=$cr
a_build_url=$a_url
b_build_url=$b_url
c_build_url=$c_url
EOF

cat >"$SCENARIO_DIR/scenario-details.md" <<EOF
### ${SCENARIO_ID}: ${SCENARIO}

#### Summary

- a result: $ar
- b result: $br
- c result: $cr

#### Artifacts

- a console: $SCENARIO_DIR/a-console.txt
- b console: $SCENARIO_DIR/b-console.txt
- c console: $SCENARIO_DIR/c-console.txt
- summary: $SCENARIO_DIR/summary.txt
EOF

log "fan-in-4: completed"
