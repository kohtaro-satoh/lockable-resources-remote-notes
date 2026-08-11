#!/usr/bin/env bash
set -euo pipefail

# S06: A->B, B->C, C->A all at once.
#
# A ring is the shape that would deadlock if remote locks were held transitively, and the shape that
# would show phantom locks if a controller confused its client role with its server role. Neither is
# true of the one-way relay model, so all three legs must simply succeed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "S06" "three-way-mesh" "${1:-}"

STAMP="$(scenario_stamp)"
A_RES="s06-a-$STAMP"
B_RES="s06-b-$STAMP"
C_RES="s06-c-$STAMP"
HOLD_SECONDS=15

scenario_step "Wire the ring: A->B, B->C, C->A"
setup_remote_pair "s06" "a" "b" "$B_RES"
setup_remote_pair "s06" "b" "c" "$C_RES"
setup_remote_pair "s06" "c" "a" "$A_RES"

relay_script() {
  local resource="$1" server="$2" marker="$3"
  cat <<EOF
pipeline {
  agent any
  stages {
    stage("Relay") {
      steps {
        lock(resource: "${resource}", serverId: "${server}") {
          echo "${marker}"
          sleep time: ${HOLD_SECONDS}, unit: "SECONDS"
        }
      }
    }
  }
}
EOF
}

upsert_pipeline_job "$CONTROLLER_A_URL" "s06-a-to-b" "$(relay_script "$B_RES" b A_ACQUIRED)"
upsert_pipeline_job "$CONTROLLER_B_URL" "s06-b-to-c" "$(relay_script "$C_RES" c B_ACQUIRED)"
upsert_pipeline_job "$CONTROLLER_C_URL" "s06-c-to-a" "$(relay_script "$A_RES" a C_ACQUIRED)"

scenario_step "Run all three legs at once"
start_epoch="$(date +%s)"
relay_reset
relay_trigger a s06-a-to-b A_ACQUIRED
relay_trigger b s06-b-to-c B_ACQUIRED
relay_trigger c s06-c-to-a C_ACQUIRED
relay_await_all 900
duration="$(($(date +%s) - start_epoch))"

scenario_step "Check the ring left nothing held"
scenario_check_resource_free "A's resource released" "a" "$A_RES"
scenario_check_resource_free "B's resource released" "b" "$B_RES"
scenario_check_resource_free "C's resource released" "c" "$C_RES"

# Serialised, the ring would take three holds; in parallel, one. Reported rather than asserted -
# see the note in mutual-peer.
parallel_bound=$((HOLD_SECONDS * 3))
scenario_check_soft "Legs ran in parallel" "elapsed time" "< ${parallel_bound}s (one hold, not three)" \
  "${duration}s" "$([[ "$duration" -lt "$parallel_bound" ]] && echo true || echo false)"

scenario_fact "duration_seconds" "$duration"

scenario_finish
