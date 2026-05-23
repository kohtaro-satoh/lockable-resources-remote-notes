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
  log "diamond: jenkins-d is not available, skip"
  exit 10
fi

SCENARIO="diamond"
SCENARIO_ID="D03"
SCENARIO_DIR="$RESULTS_DIR/$SCENARIO"
mkdir -p "$SCENARIO_DIR"

B_RES="d03-b-$(date +%s)"
C_RES="d03-c-$(date +%s)"
D_RES="d03-d-$(date +%s)"

configure_remote_server "$CONTROLLER_B_URL" "$B_RES" "remote-enabled" "authenticated"
configure_remote_server "$CONTROLLER_C_URL" "$C_RES" "remote-enabled" "authenticated"
configure_remote_server "$CONTROLLER_D_URL" "$D_RES" "remote-enabled" "authenticated"

TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-d03-b-token")"
TOKEN_C="$(issue_user_api_token "$CONTROLLER_C_URL" "admin" "e2e-d03-c-token")"
TOKEN_D="$(issue_user_api_token "$CONTROLLER_D_URL" "admin" "e2e-d03-d-token")"

upsert_username_password_credential "$CONTROLLER_A_URL" "d03-a-for-b" "admin" "$TOKEN_B"
upsert_username_password_credential "$CONTROLLER_A_URL" "d03-a-for-c" "admin" "$TOKEN_C"
upsert_username_password_credential "$CONTROLLER_B_URL" "d03-b-for-d" "admin" "$TOKEN_D"
upsert_username_password_credential "$CONTROLLER_C_URL" "d03-c-for-d" "admin" "$TOKEN_D"

configure_remote_client_for_server "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "d03-a-for-b"
configure_remote_client_for_server "$CONTROLLER_A_URL" "jenkins-a" "c" "$CONTROLLER_C_INTERNAL_URL" "d03-a-for-c"
configure_remote_client_for_server "$CONTROLLER_B_URL" "jenkins-b" "d" "$CONTROLLER_D_INTERNAL_URL" "d03-b-for-d"
configure_remote_client_for_server "$CONTROLLER_C_URL" "jenkins-c" "d" "$CONTROLLER_D_INTERNAL_URL" "d03-c-for-d"

A_SCRIPT="$(cat <<EOF
pipeline {
  agent any
  options { timeout(time: 180, unit: 'SECONDS') }
  stages {
    stage("Diamond-A") {
      steps {
        lock(resource: "${B_RES}", serverId: "b") {
          lock(resource: "${C_RES}", serverId: "c") {
            echo "DIAMOND_ACQUIRED"
          }
        }
      }
    }
  }
}
EOF
)"

B_SCRIPT="$(cat <<EOF
pipeline { agent any; stages { stage('BtoD') { steps { lock(resource: "${D_RES}", serverId: 'd') { echo 'B_TO_D'; sleep time: 10, unit: 'SECONDS' } } } } }
EOF
)"

C_SCRIPT="$(cat <<EOF
pipeline { agent any; stages { stage('CtoD') { steps { lock(resource: "${D_RES}", serverId: 'd') { echo 'C_TO_D'; sleep time: 10, unit: 'SECONDS' } } } } }
EOF
)"

upsert_pipeline_job "$CONTROLLER_A_URL" "d03-a" "$A_SCRIPT"
upsert_pipeline_job "$CONTROLLER_B_URL" "d03-b" "$B_SCRIPT"
upsert_pipeline_job "$CONTROLLER_C_URL" "d03-c" "$C_SCRIPT"

b_url="$(trigger_and_resolve_build_url "$CONTROLLER_B_URL" "d03-b" 120)"
c_url="$(trigger_and_resolve_build_url "$CONTROLLER_C_URL" "d03-c" 120)"
a_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "d03-a" 120)"

ar="$(wait_for_build_result "$a_url" 1200)"
br="$(wait_for_build_result "$b_url" 1200)"
cr="$(wait_for_build_result "$c_url" 1200)"

save_console_log "$a_url" "$SCENARIO_DIR/a-console.txt"
save_console_log "$b_url" "$SCENARIO_DIR/b-console.txt"
save_console_log "$c_url" "$SCENARIO_DIR/c-console.txt"

[[ "$ar" == "SUCCESS" && "$br" == "SUCCESS" && "$cr" == "SUCCESS" ]] || exit 1
grep -Fq "DIAMOND_ACQUIRED" "$SCENARIO_DIR/a-console.txt" || exit 1

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
- diamond marker: DIAMOND_ACQUIRED observed

#### Artifacts

- a console: $SCENARIO_DIR/a-console.txt
- b console: $SCENARIO_DIR/b-console.txt
- c console: $SCENARIO_DIR/c-console.txt
- summary: $SCENARIO_DIR/summary.txt
EOF

log "diamond: completed"
