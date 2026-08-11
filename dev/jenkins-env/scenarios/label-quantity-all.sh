#!/usr/bin/env bash
set -euo pipefail

# S15: a label with no quantity means every match, exactly as a local lock() does.
#
# This is the boundary that reads backwards. Everywhere else an absent count means one; for a
# label it means all, because that is what local lock() has always done ("0 means all"). Defaulting
# the remote path to 1 would be the natural mistake and would silently under-lock a pool: the build
# gets one machine, believes it has the pool, and a second build takes the rest.
#
# Three resources share a label, and all three must end up under one lease.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "S15" "label-quantity-all" "${1:-}"

STAMP="$(scenario_stamp)"
POOL_LABEL="s15pool$STAMP"
POOL=("s15-pool1-$STAMP" "s15-pool2-$STAMP" "s15-pool3-$STAMP")

scenario_cleanup_hook drop_resources "b" "${POOL[@]}"

scenario_step "Expose a pool of ${#POOL[@]} resources sharing one label on B, and link A"
setup_remote_pair "s15" "a" "b" "${POOL[0]}"
for resource in "${POOL[@]}"; do
  configure_label_resource "$CONTROLLER_B_URL" "$resource" "$POOL_LABEL" "remote-enabled"
done

# Scripted, and deliberately without quantity: that absence is the thing under test.
PIPELINE_SCRIPT="$(cat <<EOF
node {
  lock(label: '$POOL_LABEL', variable: 'S15RES', serverId: 'b') {
    echo "S15_BODY_START"
    echo "S15RES=\${env.S15RES}"
    sleep 8
    echo "S15_BODY_END"
  }
}
EOF
)"

scenario_step "Lock by label with no quantity"
upsert_pipeline_job "$CONTROLLER_A_URL" "s15-label-all" "$PIPELINE_SCRIPT"
build_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s15-label-all" 120)"

wait_for_console_contains "$build_url" "S15_BODY_START" 120 ||
  scenario_require_ok "Body starts" "ConsoleText" "S15_BODY_START never appeared"

scenario_step "Check every resource in the pool is held under one lease"
first_lease="$(remote_lease_id "b" "${POOL[0]}")"
for resource in "${POOL[@]}"; do
  scenario_check "Pool member $resource is under the same lease" \
    "Groovy getRemoteLockedBy on B" "$first_lease" "$(remote_lease_id "b" "$resource")"
done
scenario_check_resource_locked "The pool is actually held" "b" "${POOL[0]}" "remote"

result="$(wait_for_build_result "$build_url" 600)"
save_console_log "$build_url" "$SCENARIO_DIR/console.txt"
scenario_artifact "console" "$SCENARIO_DIR/console.txt"

combined="$(console_value "$SCENARIO_DIR/console.txt" S15RES)"

scenario_check "Build result" "Build API" "SUCCESS" "$result"
for resource in "${POOL[@]}"; do
  scenario_check_contains "Combined variable names $resource" "$SCENARIO_DIR/console.txt" "$resource"
done
scenario_check "Combined variable is comma separated" "lockEnvVars S15RES" \
  "contains ," "$([[ "$combined" == *,* ]] && echo "contains ," || echo "$combined")"

scenario_step "Check the whole pool was released"
for resource in "${POOL[@]}"; do
  scenario_check_resource_free "$resource released" "b" "$resource"
done
scenario_check_contains "Went over the remote path" "$SCENARIO_DIR/console.txt" "Remote lock acquired on"

scenario_fact "build_url" "$build_url"
scenario_fact "result" "$result"
scenario_fact "pool_size" "${#POOL[@]}"
scenario_fact "S15RES" "$combined"
scenario_fact "lease" "$first_lease"

scenario_finish
