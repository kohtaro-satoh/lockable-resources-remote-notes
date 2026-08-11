#!/usr/bin/env bash
set -euo pipefail

# S08: a label-selected remote lock exposes the same environment a local one would.
#
# lock(variable: 'V') on a local resource sets V and V0 (and V1, V2... for more than one). The remote
# path builds those names on the server and ships them back, so the risk is a subtly different shape
# - V set but not V0, or the two disagreeing. With one resource matched, V and V0 must be equal.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "S08" "label-env-vars" "${1:-}"

STAMP="$(scenario_stamp)"
HW_RESOURCE="s08-hw-board-$STAMP"
# The label is stamped too, not just the resource. A label acquire matches every resource carrying
# it, including ones an earlier run of this scenario left behind, and with a fixed label this
# scenario would silently lock the previous run's board.
HW_LABEL="s08hw$STAMP"

scenario_cleanup_hook drop_resources "b" "$HW_RESOURCE"

scenario_step "Expose a labelled resource on B and link A to it"
setup_remote_pair "s08" "a" "b" "$HW_RESOURCE"
configure_label_resource "$CONTROLLER_B_URL" "$HW_RESOURCE" "$HW_LABEL"

PIPELINE_SCRIPT="$(cat <<EOF
pipeline {
  agent any
  stages {
    stage("S08-LabelEnvVars") {
      steps {
        lock(label: '${HW_LABEL}', resource: null, quantity: 1, variable: 'HW_LOCK', serverId: 'b') {
          echo "HW_LOCK=\${env.HW_LOCK}"
          echo "HW_LOCK0=\${env.HW_LOCK0}"
        }
      }
    }
  }
}
EOF
)"

scenario_step "Acquire by label with variable: 'HW_LOCK'"
upsert_pipeline_job "$CONTROLLER_A_URL" "s08-label-env" "$PIPELINE_SCRIPT"
build_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s08-label-env" 120)"
result="$(wait_for_build_result "$build_url" 600)"
save_console_log "$build_url" "$SCENARIO_DIR/console.txt"
scenario_artifact "console" "$SCENARIO_DIR/console.txt"

hw_lock="$(console_value "$SCENARIO_DIR/console.txt" HW_LOCK)"
hw_lock0="$(console_value "$SCENARIO_DIR/console.txt" HW_LOCK0)"

scenario_check "Build result" "Build API" "SUCCESS" "$result"
scenario_check "Combined variable names the matched resource" "lockEnvVars HW_LOCK" "$HW_RESOURCE" "$hw_lock"
scenario_check "Indexed variable is set" "lockEnvVars HW_LOCK0" "$HW_RESOURCE" "$hw_lock0"
scenario_check "One match means V equals V0" "local lock() equivalence" "$hw_lock" "$hw_lock0"
scenario_check_contains "Went over the remote path" "$SCENARIO_DIR/console.txt" "Remote lock acquired on"
scenario_check_resource_free "Resource released on B" "b" "$HW_RESOURCE"

scenario_fact "build_url" "$build_url"
scenario_fact "result" "$result"
scenario_fact "HW_LOCK" "$hw_lock"
scenario_fact "HW_LOCK0" "$hw_lock0"

scenario_finish
