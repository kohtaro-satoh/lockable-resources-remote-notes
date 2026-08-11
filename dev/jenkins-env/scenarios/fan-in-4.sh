#!/usr/bin/env bash
set -euo pipefail

# D01: three clients contend for one resource on a fourth controller.
#
# Same shape as S02 but with the queue two deep instead of one, which is where a queue that promotes
# the wrong waiter, or forgets one, starts to show.
#
# jenkins-d availability is declared in lib/scenarios.tsv (controllers=abcd); run-e2e.sh skips this
# scenario when d is down, so there is no probe here.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "D01" "fan-in-4" "${1:-}"

RESOURCE_NAME="d01-shared-d-$(scenario_stamp)"

scenario_step "Expose one resource on D and point A, B and C at it"
setup_remote_pair "d01" "a" "d" "$RESOURCE_NAME"
setup_remote_pair "d01" "b" "d" "$RESOURCE_NAME"
setup_remote_pair "d01" "c" "d" "$RESOURCE_NAME"

contender_script() {
  local marker="$1" hold="$2"
  cat <<EOF
pipeline { agent any; stages { stage('Contend') { steps { lock(resource: "${RESOURCE_NAME}", serverId: 'd') { echo '${marker}'; sleep time: ${hold}, unit: 'SECONDS' } } } } }
EOF
}

upsert_pipeline_job "$CONTROLLER_A_URL" "d01-a" "$(contender_script A_ACQUIRED 20)"
upsert_pipeline_job "$CONTROLLER_B_URL" "d01-b" "$(contender_script B_ACQUIRED 5)"
upsert_pipeline_job "$CONTROLLER_C_URL" "d01-c" "$(contender_script C_ACQUIRED 5)"

scenario_step "Start all three contenders"
start_epoch="$(date +%s)"
relay_reset
relay_trigger a d01-a A_ACQUIRED
relay_trigger b d01-b B_ACQUIRED
relay_trigger c d01-c C_ACQUIRED
relay_await_all 900
duration="$(($(date +%s) - start_epoch))"

# Exclusion, from the outside: the three holds are 20 + 5 + 5 seconds and only one contender can be
# in at a time, so a run that finished faster than their sum handed the resource out twice.
scenario_check_ge "Contenders were serialised by the lock" "$duration" 30 "elapsed seconds (sum of holds)"

scenario_step "Check the resource was released"
scenario_check_resource_free "Shared resource released on D" "d" "$RESOURCE_NAME"

scenario_fact "duration_seconds" "$duration"
scenario_fact "resource" "$RESOURCE_NAME"

scenario_finish
