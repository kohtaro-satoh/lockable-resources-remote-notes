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
  log "chain-4: jenkins-d is not available, skip"
  exit 10
fi

SCENARIO="chain-4"
SCENARIO_ID="D02"
SCENARIO_DIR="$RESULTS_DIR/$SCENARIO"
mkdir -p "$SCENARIO_DIR"

B_RES="d02-b-$(date +%s)"
C_RES="d02-c-$(date +%s)"
D_RES="d02-d-$(date +%s)"

configure_remote_server "$CONTROLLER_B_URL" "$B_RES" "remote-enabled" "authenticated"
configure_remote_server "$CONTROLLER_C_URL" "$C_RES" "remote-enabled" "authenticated"
configure_remote_server "$CONTROLLER_D_URL" "$D_RES" "remote-enabled" "authenticated"

TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-d02-b-token")"
TOKEN_C="$(issue_user_api_token "$CONTROLLER_C_URL" "admin" "e2e-d02-c-token")"
TOKEN_D="$(issue_user_api_token "$CONTROLLER_D_URL" "admin" "e2e-d02-d-token")"

upsert_username_password_credential "$CONTROLLER_A_URL" "d02-a-for-b" "admin" "$TOKEN_B"
upsert_username_password_credential "$CONTROLLER_B_URL" "d02-b-for-c" "admin" "$TOKEN_C"
upsert_username_password_credential "$CONTROLLER_C_URL" "d02-c-for-d" "admin" "$TOKEN_D"

configure_remote_client_for_server "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "d02-a-for-b"
configure_remote_client_for_server "$CONTROLLER_B_URL" "jenkins-b" "c" "$CONTROLLER_C_INTERNAL_URL" "d02-b-for-c"
configure_remote_client_for_server "$CONTROLLER_C_URL" "jenkins-c" "d" "$CONTROLLER_D_INTERNAL_URL" "d02-c-for-d"

A_SCRIPT="$(cat <<EOF
pipeline { agent any; stages { stage('AtoB') { steps { lock(resource: "${B_RES}", serverId: 'b') { echo 'A_ACQUIRED'; sleep time: 15, unit: 'SECONDS' } } } } }
EOF
)"
B_SCRIPT="$(cat <<EOF
pipeline { agent any; stages { stage('BtoC') { steps { lock(resource: "${C_RES}", serverId: 'c') { echo 'B_ACQUIRED'; sleep time: 15, unit: 'SECONDS' } } } } }
EOF
)"
C_SCRIPT="$(cat <<EOF
pipeline { agent any; stages { stage('CtoD') { steps { lock(resource: "${D_RES}", serverId: 'd') { echo 'C_ACQUIRED'; sleep time: 15, unit: 'SECONDS' } } } } }
EOF
)"

upsert_pipeline_job "$CONTROLLER_A_URL" "d02-a" "$A_SCRIPT"
upsert_pipeline_job "$CONTROLLER_B_URL" "d02-b" "$B_SCRIPT"
upsert_pipeline_job "$CONTROLLER_C_URL" "d02-c" "$C_SCRIPT"

start_epoch="$(date +%s)"
a_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "d02-a" 120)"
b_url="$(trigger_and_resolve_build_url "$CONTROLLER_B_URL" "d02-b" 120)"
c_url="$(trigger_and_resolve_build_url "$CONTROLLER_C_URL" "d02-c" 120)"

ar="$(wait_for_build_result "$a_url" 900)"
br="$(wait_for_build_result "$b_url" 900)"
cr="$(wait_for_build_result "$c_url" 900)"
end_epoch="$(date +%s)"

save_console_log "$a_url" "$SCENARIO_DIR/a-console.txt"
save_console_log "$b_url" "$SCENARIO_DIR/b-console.txt"
save_console_log "$c_url" "$SCENARIO_DIR/c-console.txt"

[[ "$ar" == "SUCCESS" && "$br" == "SUCCESS" && "$cr" == "SUCCESS" ]] || exit 1

cat >"$SCENARIO_DIR/summary.txt" <<EOF
a_result=$ar
b_result=$br
c_result=$cr
duration_seconds=$((end_epoch - start_epoch))
EOF

cat >"$SCENARIO_DIR/scenario-details.md" <<EOF
### ${SCENARIO_ID}: ${SCENARIO}

#### Summary

- a result: $ar
- b result: $br
- c result: $cr
- duration: $((end_epoch - start_epoch))s

#### Artifacts

- a console: $SCENARIO_DIR/a-console.txt
- b console: $SCENARIO_DIR/b-console.txt
- c console: $SCENARIO_DIR/c-console.txt
- summary: $SCENARIO_DIR/summary.txt
EOF

log "chain-4: completed"
