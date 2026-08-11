#!/usr/bin/env bash
set -euo pipefail

# D02: A->B, B->C, C->D as three independent relays running at once.
#
# A chain is the topology that would expose transitive holding: if B's own lock on C were somehow
# coupled to A's lock on B, the legs would serialise instead of overlapping. They are independent, so
# all three run in the time of one.
#
# Needs jenkins-d; declared as controllers=abcd in lib/scenarios.tsv.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "D02" "chain-4" "${1:-}"

STAMP="$(scenario_stamp)"
B_RES="d02-b-$STAMP"
C_RES="d02-c-$STAMP"
D_RES="d02-d-$STAMP"
HOLD_SECONDS=15

scenario_step "Wire the chain: A->B, B->C, C->D"
setup_remote_pair "d02" "a" "b" "$B_RES"
setup_remote_pair "d02" "b" "c" "$C_RES"
setup_remote_pair "d02" "c" "d" "$D_RES"

relay_script() {
  local resource="$1" server="$2" marker="$3"
  cat <<EOF
pipeline { agent any; stages { stage('Relay') { steps { lock(resource: "${resource}", serverId: '${server}') { echo '${marker}'; sleep time: ${HOLD_SECONDS}, unit: 'SECONDS' } } } } }
EOF
}

upsert_pipeline_job "$CONTROLLER_A_URL" "d02-a" "$(relay_script "$B_RES" b A_ACQUIRED)"
upsert_pipeline_job "$CONTROLLER_B_URL" "d02-b" "$(relay_script "$C_RES" c B_ACQUIRED)"
upsert_pipeline_job "$CONTROLLER_C_URL" "d02-c" "$(relay_script "$D_RES" d C_ACQUIRED)"

scenario_step "Run all three legs at once"
start_epoch="$(date +%s)"
relay_reset
relay_trigger a d02-a A_ACQUIRED
relay_trigger b d02-b B_ACQUIRED
relay_trigger c d02-c C_ACQUIRED
relay_await_all 900
duration="$(($(date +%s) - start_epoch))"

scenario_step "Check the chain left nothing held"
scenario_check_resource_free "B's resource released" "b" "$B_RES"
scenario_check_resource_free "C's resource released" "c" "$C_RES"
scenario_check_resource_free "D's resource released" "d" "$D_RES"

parallel_bound=$((HOLD_SECONDS * 3))
scenario_check_soft "Legs are independent" "elapsed time" "< ${parallel_bound}s (one hold, not three)" \
  "${duration}s" "$([[ "$duration" -lt "$parallel_bound" ]] && echo true || echo false)"

scenario_fact "duration_seconds" "$duration"

scenario_finish
