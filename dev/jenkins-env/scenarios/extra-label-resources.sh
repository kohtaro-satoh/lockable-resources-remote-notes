#!/usr/bin/env bash
set -euo pipefail

# S14: an extra entry selected by label joins the same lease as the main resource.
#
# Regression cover for a silent drop: an extra selected by label used to be accepted and then
# quietly ignored, so the build ran holding only its main resource while believing it held the
# labelled one too. Nothing in the console said otherwise - the only evidence is on the server, where
# the labelled resource either carries the same lease id or carries none.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "S14" "extra-label-resources" "${1:-}"

STAMP="$(scenario_stamp)"
RES1="s14-res1-$STAMP"
GPU="s14-gpu-$STAMP"
GPU_LABEL="s14gpu$STAMP"

scenario_cleanup_hook drop_resources "b" "$RES1" "$GPU"

scenario_step "Expose a main resource and a labelled one on B, and link A"
setup_remote_pair "s14" "a" "b" "$RES1"
# The labelled resource needs both labels: remote-enabled to be visible, its own to be selectable.
configure_label_resource "$CONTROLLER_B_URL" "$GPU" "$GPU_LABEL" "remote-enabled"

# Scripted, not declarative: declarative rejects this parameter combination before the step runs.
PIPELINE_SCRIPT="$(cat <<EOF
node {
  lock(resource: '$RES1', extra: [[label: '$GPU_LABEL', quantity: 1]], variable: 'S14RES', serverId: 'b') {
    echo "S14_BODY_START"
    echo "S14RES=\${env.S14RES}"
    echo "S14RES0=\${env.S14RES0}"
    echo "S14RES1=\${env.S14RES1}"
    sleep 8
    echo "S14_BODY_END"
  }
}
EOF
)"

scenario_step "Lock the main resource with a label-selected extra"
upsert_pipeline_job "$CONTROLLER_A_URL" "s14-extra-label" "$PIPELINE_SCRIPT"
build_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s14-extra-label" 120)"

wait_for_console_contains "$build_url" "S14_BODY_START" 120 ||
  scenario_require_ok "Body starts" "ConsoleText" "S14_BODY_START never appeared"

main_lease="$(remote_lease_id "b" "$RES1")"
gpu_lease="$(remote_lease_id "b" "$GPU")"
scenario_check_resource_locked "Main resource held remotely" "b" "$RES1" "remote"
# The heart of it: the labelled extra must be held at all, and under the same lease.
scenario_check_resource_locked "Label-selected extra was honoured, not dropped" "b" "$GPU" "remote"
scenario_check "Extra joined the same lease (atomic)" "Groovy getRemoteLockedBy on B" "$main_lease" "$gpu_lease"

result="$(wait_for_build_result "$build_url" 600)"
save_console_log "$build_url" "$SCENARIO_DIR/console.txt"
scenario_artifact "console" "$SCENARIO_DIR/console.txt"

combined="$(console_value "$SCENARIO_DIR/console.txt" S14RES)"

scenario_check "Build result" "Build API" "SUCCESS" "$result"
scenario_check_contains "Combined variable names the main resource" "$SCENARIO_DIR/console.txt" "$RES1"
scenario_check_contains "Combined variable names the label-resolved extra" "$SCENARIO_DIR/console.txt" "$GPU"
scenario_check "Combined variable is comma separated" "lockEnvVars S14RES" \
  "contains ," "$([[ "$combined" == *,* ]] && echo "contains ," || echo "$combined")"
scenario_check_matches "Indexed variable 0 is set" "$SCENARIO_DIR/console.txt" "^S14RES0=s14-"
scenario_check_matches "Indexed variable 1 is set" "$SCENARIO_DIR/console.txt" "^S14RES1=s14-"

scenario_step "Check both resources were released"
scenario_check_resource_free "Main resource released" "b" "$RES1"
scenario_check_resource_free "Label-selected extra released" "b" "$GPU"
scenario_check_contains "Went over the remote path" "$SCENARIO_DIR/console.txt" "Remote lock acquired on"

scenario_fact "build_url" "$build_url"
scenario_fact "result" "$result"
scenario_fact "S14RES" "$combined"
scenario_fact "lease_main" "$main_lease"
scenario_fact "lease_extra" "$gpu_lease"

scenario_finish
