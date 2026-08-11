#!/usr/bin/env bash
set -euo pipefail

# S10: main + extra are acquired atomically, under one lease.
#
# "Atomically" is the whole claim, and it is not visible from the client: a client that took the two
# resources one after another would produce exactly the same console output while leaving a window
# where it held one and waited for the other. What distinguishes them is the lease id on the server,
# which is why the check happens mid-body against B rather than in the log afterwards.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "S10" "extra-resources" "${1:-}"

STAMP="$(scenario_stamp)"
RES1="s10-res1-$STAMP"
RES2="s10-res2-$STAMP"

scenario_step "Expose two resources on B and link A to them"
setup_remote_pair "s10" "a" "b" "$RES1"
expose_resource "b" "$RES2"

# Scripted, not declarative: declarative validates required parameters before the step runs and
# rejects the resource/extra combination this scenario is built on.
PIPELINE_SCRIPT="$(cat <<EOF
node {
  lock(resource: '$RES1', extra: [[resource: '$RES2']], variable: 'S10RES', serverId: 'b') {
    echo "S10_BODY_START"
    echo "S10RES=\${env.S10RES}"
    echo "S10RES0=\${env.S10RES0}"
    echo "S10RES1=\${env.S10RES1}"
    sleep 8
    echo "S10_BODY_END"
  }
}
EOF
)"

scenario_step "Lock main + extra and inspect the leases while the body runs"
upsert_pipeline_job "$CONTROLLER_A_URL" "s10-extra" "$PIPELINE_SCRIPT"
build_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s10-extra" 120)"

wait_for_console_contains "$build_url" "S10_BODY_START" 120 ||
  scenario_require_ok "Body starts" "ConsoleText" "S10_BODY_START never appeared"

lease1="$(remote_lease_id "b" "$RES1")"
lease2="$(remote_lease_id "b" "$RES2")"
scenario_check_resource_locked "Main resource held remotely during the body" "b" "$RES1" "remote"
scenario_check "Extra joined the same lease (atomic)" "Groovy getRemoteLockedBy on B" "$lease1" "$lease2"

result="$(wait_for_build_result "$build_url" 600)"
save_console_log "$build_url" "$SCENARIO_DIR/console.txt"
scenario_artifact "console" "$SCENARIO_DIR/console.txt"

combined="$(console_value "$SCENARIO_DIR/console.txt" S10RES)"
res0="$(console_value "$SCENARIO_DIR/console.txt" S10RES0)"
res1_var="$(console_value "$SCENARIO_DIR/console.txt" S10RES1)"

scenario_check "Build result" "Build API" "SUCCESS" "$result"
# Order is the allocator's business, so the combined variable is checked by content, not by string.
scenario_check_contains "Combined variable names the main resource" "$SCENARIO_DIR/console.txt" "$RES1"
scenario_check_contains "Combined variable names the extra resource" "$SCENARIO_DIR/console.txt" "$RES2"
scenario_check "Combined variable is comma separated, as local lock() does it" "lockEnvVars S10RES" \
  "contains ," "$([[ "$combined" == *,* ]] && echo "contains ," || echo "$combined")"
scenario_check_matches "Indexed variable 0 is set" "$SCENARIO_DIR/console.txt" "^S10RES0=s10-res"
scenario_check_matches "Indexed variable 1 is set" "$SCENARIO_DIR/console.txt" "^S10RES1=s10-res"

scenario_step "Check both resources were released"
scenario_check_resource_free "Main resource released" "b" "$RES1"
scenario_check_resource_free "Extra resource released" "b" "$RES2"
scenario_check_contains "Went over the remote path" "$SCENARIO_DIR/console.txt" "Remote lock acquired on"

scenario_fact "build_url" "$build_url"
scenario_fact "result" "$result"
scenario_fact "S10RES" "$combined"
scenario_fact "S10RES0" "$res0"
scenario_fact "S10RES1" "$res1_var"
scenario_fact "lease_main" "$lease1"
scenario_fact "lease_extra" "$lease2"

scenario_finish
