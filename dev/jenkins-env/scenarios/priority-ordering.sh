#!/usr/bin/env bash
set -euo pipefail

# S12: priority orders local and remote waiters in one queue.
#
# The queue on a server is shared: a remote request is not a second queue that happens to be served
# alongside the local one, it is an entry in the same one. That is what this scenario proves, by
# making priority contradict arrival order - a local waiter enqueues first at priority 0, a remote
# one second at priority 10, and the remote must win. Two separate queues would give the local
# waiter the resource, because within its own queue it was first.
#
# The moment of promotion is what has to be caught, so the resource is sampled in a tight loop right
# after the holder releases: whichever kind of hold appears first is the answer.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "S12" "priority-ordering" "${1:-}"

RES="s12-res-$(scenario_stamp)"

scenario_step "Expose the resource on B and link A to it"
setup_remote_pair "s12" "a" "b" "$RES"

HOLDER_SCRIPT="$(cat <<EOF
node {
  lock(resource: '$RES') {
    echo "S12_HOLDER_LOCKED"
    sleep 25
  }
}
EOF
)"
LOCAL_WAITER_SCRIPT="$(cat <<EOF
node {
  lock(resource: '$RES') {
    echo "S12_LOCAL_ACQUIRED"
    sleep 2
  }
}
EOF
)"
REMOTE_HIGH_SCRIPT="$(cat <<EOF
node {
  lock(resource: '$RES', priority: 10, serverId: 'b') {
    echo "S12_REMOTE_ACQUIRED"
    sleep 10
  }
}
EOF
)"

upsert_pipeline_job "$CONTROLLER_B_URL" "s12-holder" "$HOLDER_SCRIPT"
upsert_pipeline_job "$CONTROLLER_B_URL" "s12-local-waiter" "$LOCAL_WAITER_SCRIPT"
upsert_pipeline_job "$CONTROLLER_A_URL" "s12-remote-high" "$REMOTE_HIGH_SCRIPT"

scenario_step "Hold the resource locally on B"
holder_url="$(trigger_and_resolve_build_url "$CONTROLLER_B_URL" "s12-holder" 120)"
wait_for_console_contains "$holder_url" "S12_HOLDER_LOCKED" 120 ||
  scenario_require_ok "Holder acquires first" "ConsoleText" "S12_HOLDER_LOCKED never appeared"

scenario_step "Enqueue the local waiter (priority 0) first, then the remote one (priority 10)"
local_url="$(trigger_and_resolve_build_url "$CONTROLLER_B_URL" "s12-local-waiter" 120)"
sleep 5
remote_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s12-remote-high" 120)"
sleep 5

scenario_step "Release the holder and watch which waiter is promoted"
holder_result="$(wait_for_build_result "$holder_url" 600)"
scenario_check "Holder result" "Build API" "SUCCESS" "$holder_result"

promoted="none"
for _ in $(seq 1 15); do
  state="$(resource_state "b" "$RES")"
  if [[ -n "$(resource_field "$state" REMOTE_LOCK_ID)" ]]; then
    promoted="remote"
    break
  fi
  if [[ "$(resource_field "$state" LOCKED)" == "true" ]]; then
    promoted="local"
    break
  fi
  sleep 1
done

scenario_check "Higher priority won over arrival order" \
  "Groovy resource state on B, sampled after release" "remote" "$promoted"

remote_result="$(wait_for_build_result "$remote_url" 600)"
local_result="$(wait_for_build_result "$local_url" 600)"

save_console_log "$holder_url" "$SCENARIO_DIR/holder-console.txt"
save_console_log "$local_url" "$SCENARIO_DIR/local-waiter-console.txt"
save_console_log "$remote_url" "$SCENARIO_DIR/remote-high-console.txt"
scenario_artifact "holder console" "$SCENARIO_DIR/holder-console.txt"
scenario_artifact "local waiter console" "$SCENARIO_DIR/local-waiter-console.txt"
scenario_artifact "remote waiter console" "$SCENARIO_DIR/remote-high-console.txt"

scenario_check "Remote waiter result" "Build API" "SUCCESS" "$remote_result"
scenario_check "Local waiter result" "Build API" "SUCCESS" "$local_result"
# Losing the race must only mean waiting longer, never being dropped.
scenario_check_contains "Remote waiter entered its body" "$SCENARIO_DIR/remote-high-console.txt" "S12_REMOTE_ACQUIRED"
scenario_check_contains "Local waiter still got its turn" "$SCENARIO_DIR/local-waiter-console.txt" "S12_LOCAL_ACQUIRED"
scenario_check_resource_free "Resource free at the end" "b" "$RES"

scenario_fact "holder_result" "$holder_result"
scenario_fact "local_result" "$local_result"
scenario_fact "remote_result" "$remote_result"
scenario_fact "first_promoted" "$promoted"

scenario_finish
