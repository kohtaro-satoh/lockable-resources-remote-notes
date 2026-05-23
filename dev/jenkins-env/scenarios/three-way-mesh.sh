#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

RESULTS_DIR="${1:-}"
if [[ -z "$RESULTS_DIR" ]]; then
  err "Results directory argument is required"
  exit 2
fi

SCENARIO="three-way-mesh"
SCENARIO_ID="S06"
SCENARIO_DIR="$RESULTS_DIR/$SCENARIO"
mkdir -p "$SCENARIO_DIR"

A_RES="s06-a-$(date +%s)"
B_RES="s06-b-$(date +%s)"
C_RES="s06-c-$(date +%s)"

configure_remote_server "$CONTROLLER_A_URL" "$A_RES" "remote-enabled" "authenticated"
configure_remote_server "$CONTROLLER_B_URL" "$B_RES" "remote-enabled" "authenticated"
configure_remote_server "$CONTROLLER_C_URL" "$C_RES" "remote-enabled" "authenticated"

TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-s06-b-token")"
TOKEN_C="$(issue_user_api_token "$CONTROLLER_C_URL" "admin" "e2e-s06-c-token")"
TOKEN_A="$(issue_user_api_token "$CONTROLLER_A_URL" "admin" "e2e-s06-a-token")"

upsert_username_password_credential "$CONTROLLER_A_URL" "s06-a-for-b" "admin" "$TOKEN_B"
upsert_username_password_credential "$CONTROLLER_B_URL" "s06-b-for-c" "admin" "$TOKEN_C"
upsert_username_password_credential "$CONTROLLER_C_URL" "s06-c-for-a" "admin" "$TOKEN_A"

configure_remote_client_for_server "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "s06-a-for-b"
configure_remote_client_for_server "$CONTROLLER_B_URL" "jenkins-b" "c" "$CONTROLLER_C_INTERNAL_URL" "s06-b-for-c"
configure_remote_client_for_server "$CONTROLLER_C_URL" "jenkins-c" "a" "$CONTROLLER_A_INTERNAL_URL" "s06-c-for-a"

A_SCRIPT="$(cat <<EOF
pipeline {
  agent any
  stages {
    stage("AtoB") {
      steps {
        lock(resource: "${B_RES}", serverId: "b") {
          echo "A_ACQUIRED"
          sleep time: 15, unit: "SECONDS"
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
    stage("BtoC") {
      steps {
        lock(resource: "${C_RES}", serverId: "c") {
          echo "B_ACQUIRED"
          sleep time: 15, unit: "SECONDS"
        }
      }
    }
  }
}
EOF
)"

C_SCRIPT="$(cat <<EOF
pipeline {
  agent any
  stages {
    stage("CtoA") {
      steps {
        lock(resource: "${A_RES}", serverId: "a") {
          echo "C_ACQUIRED"
          sleep time: 15, unit: "SECONDS"
        }
      }
    }
  }
}
EOF
)"

upsert_pipeline_job "$CONTROLLER_A_URL" "s06-a-to-b" "$A_SCRIPT"
upsert_pipeline_job "$CONTROLLER_B_URL" "s06-b-to-c" "$B_SCRIPT"
upsert_pipeline_job "$CONTROLLER_C_URL" "s06-c-to-a" "$C_SCRIPT"

start_epoch="$(date +%s)"
a_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s06-a-to-b" 120)"
b_url="$(trigger_and_resolve_build_url "$CONTROLLER_B_URL" "s06-b-to-c" 120)"
c_url="$(trigger_and_resolve_build_url "$CONTROLLER_C_URL" "s06-c-to-a" 120)"

ar="$(wait_for_build_result "$a_url" 900)"
br="$(wait_for_build_result "$b_url" 900)"
cr="$(wait_for_build_result "$c_url" 900)"
end_epoch="$(date +%s)"

save_console_log "$a_url" "$SCENARIO_DIR/a-console.txt"
save_console_log "$b_url" "$SCENARIO_DIR/b-console.txt"
save_console_log "$c_url" "$SCENARIO_DIR/c-console.txt"

[[ "$ar" == "SUCCESS" && "$br" == "SUCCESS" && "$cr" == "SUCCESS" ]] || exit 1

grep -Fq "A_ACQUIRED" "$SCENARIO_DIR/a-console.txt" || exit 1
grep -Fq "B_ACQUIRED" "$SCENARIO_DIR/b-console.txt" || exit 1
grep -Fq "C_ACQUIRED" "$SCENARIO_DIR/c-console.txt" || exit 1

cat >"$SCENARIO_DIR/summary.txt" <<EOF
a_build_url=$a_url
a_result=$ar
b_build_url=$b_url
b_result=$br
c_build_url=$c_url
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

log "three-way-mesh: completed"
