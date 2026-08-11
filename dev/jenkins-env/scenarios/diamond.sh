#!/usr/bin/env bash
set -euo pipefail

# D03: A holds B and C nested, while B and C both want D.
#
# The diamond is the shape that deadlocks under a naive implementation: A waits on B and C, both of
# which are themselves waiting on the same resource on D. It does not deadlock here because a remote
# lock is not held transitively - A's lock on B says nothing about what B is waiting for - and this
# scenario is the assertion that this stays true.
#
# Needs jenkins-d; declared as controllers=abcd in lib/scenarios.tsv.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "D03" "diamond" "${1:-}"

STAMP="$(scenario_stamp)"
B_RES="d03-b-$STAMP"
C_RES="d03-c-$STAMP"
D_RES="d03-d-$STAMP"

scenario_step "Wire the diamond: A->B, A->C, B->D, C->D"
setup_remote_pair "d03" "a" "b" "$B_RES"
setup_remote_pair "d03" "a" "c" "$C_RES"
setup_remote_pair "d03" "b" "d" "$D_RES"
setup_remote_pair "d03" "c" "d" "$D_RES"

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

leg_script() {
  local marker="$1"
  cat <<EOF
pipeline { agent any; stages { stage('ToD') { steps { lock(resource: "${D_RES}", serverId: 'd') { echo '${marker}'; sleep time: 10, unit: 'SECONDS' } } } } }
EOF
}

upsert_pipeline_job "$CONTROLLER_A_URL" "d03-a" "$A_SCRIPT"
upsert_pipeline_job "$CONTROLLER_B_URL" "d03-b" "$(leg_script B_TO_D)"
upsert_pipeline_job "$CONTROLLER_C_URL" "d03-c" "$(leg_script C_TO_D)"

# B and C first, so they are already contending for D when A tries to take them both.
scenario_step "Start B and C contending for D, then A taking B and C"
relay_reset
relay_trigger b d03-b B_TO_D
relay_trigger c d03-c C_TO_D
relay_trigger a d03-a DIAMOND_ACQUIRED
relay_await_all 1200

scenario_step "Check nothing was left held"
scenario_check_resource_free "B's resource released" "b" "$B_RES"
scenario_check_resource_free "C's resource released" "c" "$C_RES"
scenario_check_resource_free "D's resource released" "d" "$D_RES"

scenario_finish
