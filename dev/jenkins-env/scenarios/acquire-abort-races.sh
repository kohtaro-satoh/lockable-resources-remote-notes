#!/usr/bin/env bash
set -euo pipefail

# B05: aborting a build must not strand a resource on the server.
#
# Every other scenario ends its builds the same way: the body finishes and the step releases on its
# way out. Aborting does not take that path, and it is the most common way a lock's life actually
# ends - someone presses the red X, a job is cancelled, a queue is flushed. Two moments matter, and
# they fail differently:
#
#   * aborted while QUEUED - the request is still waiting. If the withdrawal does not reach the
#     server's queue, the resource is eventually promoted to a client that stopped listening: it
#     shows as locked, nothing is using it, and only an administrator can free it.
#
#   * aborted while ACQUIRED - the lease is live. If the release does not happen, the resource stays
#     held until it goes STALE (RLR_STALE_THRESHOLD_S) and then needs a human, so the whole point is
#     that it comes back promptly rather than eventually.
#
# The second check is therefore against a bound well inside the STALE threshold. Reaching STALE is
# not the safety net working, it is this test failing slowly.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "B05" "acquire-abort-races" "${1:-}"

STAMP="$(scenario_stamp)"
RES="b05-res-$STAMP"
RELEASE_BOUND=$((RLR_STALE_THRESHOLD_S / 2))

scenario_cleanup_hook drop_resources "b" "$RES"

scenario_step "Expose the resource on B and link A to it"
setup_remote_pair "b05" "a" "b" "$RES"

HOLDER_SCRIPT="$(cat <<EOF
node {
  lock(resource: '$RES', serverId: 'b') {
    echo "B05_HOLDER_IN"
    sleep 60
  }
}
EOF
)"
WAITER_SCRIPT="$(cat <<EOF
node {
  lock(resource: '$RES', serverId: 'b') {
    echo "B05_WAITER_IN"
    sleep 10
  }
}
EOF
)"

upsert_pipeline_job "$CONTROLLER_A_URL" "b05-holder" "$HOLDER_SCRIPT"
upsert_pipeline_job "$CONTROLLER_A_URL" "b05-waiter" "$WAITER_SCRIPT"

scenario_step "Case 1: abort a build that is still queued for the resource"
holder_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "b05-holder" 120)"
wait_for_console_contains "$holder_url" "B05_HOLDER_IN" 180 ||
  scenario_require_ok "Holder takes the resource" "ConsoleText" "B05_HOLDER_IN never appeared"

waiter_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "b05-waiter" 120)"
# Give the waiter time to reach the server and be queued, rather than aborting it before it asks.
sleep $((RLR_POLL_INTERVAL_S * 3))
waiter_queued="$(resource_field "$(resource_state "b" "$RES")" QUEUED)"

abort_build "$CONTROLLER_A_URL" "$waiter_url"
waiter_result="$(wait_for_build_result "$waiter_url" 180)" || waiter_result="TIMEOUT"
save_console_log "$waiter_url" "$SCENARIO_DIR/waiter-console.txt"
scenario_artifact "aborted waiter console" "$SCENARIO_DIR/waiter-console.txt"

scenario_check "The queued build ends as ABORTED" "Build API" "ABORTED" "$waiter_result"
scenario_check_absent "It never entered the lock body" "$SCENARIO_DIR/waiter-console.txt" "B05_WAITER_IN"

scenario_step "Let the holder finish and check the abandoned request did not take the resource"
holder_result="$(wait_for_build_result "$holder_url" 300)" || holder_result="TIMEOUT"
save_console_log "$holder_url" "$SCENARIO_DIR/holder-console.txt"
scenario_artifact "holder console" "$SCENARIO_DIR/holder-console.txt"
scenario_check "Holder finished normally" "Build API" "SUCCESS" "$holder_result"

# The moment of truth: with the holder gone, an un-withdrawn queue entry would be promoted now and
# the resource would be locked to a build that no longer exists.
freed="free"
wait_for_resource_free "b" "$RES" 30 || freed="still held"
scenario_check "The resource is free, not handed to the aborted build" \
  "Groovy resource state on B, after the holder released" "free" "$freed"

scenario_step "Case 2: abort a build that is holding the lease"
holder2_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "b05-holder" 120)"
wait_for_console_contains "$holder2_url" "B05_HOLDER_IN" 180 ||
  scenario_require_ok "Second holder takes the resource" "ConsoleText" "B05_HOLDER_IN never appeared"

scenario_check_resource_locked "The lease is live before the abort" "b" "$RES" "remote"

abort_start="$(date +%s)"
abort_build "$CONTROLLER_A_URL" "$holder2_url"
holder2_result="$(wait_for_build_result "$holder2_url" 180)" || holder2_result="TIMEOUT"
scenario_check "The holding build ends as ABORTED" "Build API" "ABORTED" "$holder2_result"

released="released"
wait_for_resource_free "b" "$RES" "$RELEASE_BOUND" || released="still held"
release_seconds="$(($(date +%s) - abort_start))"

scenario_check "Aborting released the lease" \
  "Groovy resource state on B, within ${RELEASE_BOUND}s of the abort" "released" "$released"
# Recorded either way: how long it took is the difference between "the step released it" and "it sat
# there until something else noticed".
scenario_observe "Time from abort to the resource being free" "polled resource state" "${release_seconds}s"
scenario_check_lt "Released well inside the STALE threshold" \
  "$release_seconds" "$RLR_STALE_THRESHOLD_S" "seconds (STALE would need an administrator)"

save_console_log "$holder2_url" "$SCENARIO_DIR/aborted-holder-console.txt"
scenario_artifact "aborted holder console" "$SCENARIO_DIR/aborted-holder-console.txt"

scenario_check_resource_free "Nothing is left held at the end" "b" "$RES"

scenario_fact "waiter_was_queued_before_abort" "$waiter_queued"
scenario_fact "waiter_result" "$waiter_result"
scenario_fact "aborted_holder_result" "$holder2_result"
scenario_fact "release_after_abort_seconds" "$release_seconds"
scenario_fact "stale_threshold_seconds" "$RLR_STALE_THRESHOLD_S"

scenario_finish
