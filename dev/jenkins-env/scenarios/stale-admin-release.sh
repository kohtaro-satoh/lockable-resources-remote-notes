#!/usr/bin/env bash
set -euo pipefail

# S13: a lease whose client vanished goes STALE, stays held, and needs an administrator.
#
# The alternative design - release the lease automatically once heartbeats stop - is the one this
# scenario exists to rule out. A client that stopped answering may still be running the work; taking
# its resource away would hand the same hardware to a second build. So the lease goes STALE, the
# resource stays held, and a human decides. Every step of that is asserted, including the one that
# looks like a bug from the outside (the resource stays locked with nobody heartbeating it).
#
# The ghost client is a direct REST acquire that never heartbeats. That is the only way to produce a
# client that is gone but whose lease is intact - a real client that dies takes its build with it.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "S13" "stale-admin-release" "${1:-}"

RES="s13-res-$(scenario_stamp)"
RESPONSE="$SCENARIO_DIR/acquire-response.json"
# STALE is RLR_STALE_THRESHOLD_S after the last heartbeat; allow the sweep's own period on top.
STALE_WAIT_LIMIT=$((RLR_STALE_THRESHOLD_S + 30))

scenario_step "Expose the resource on B"
configure_remote_server "$CONTROLLER_B_URL" "$RES" "remote-enabled" "authenticated"
verify_remote_server_config "$CONTROLLER_B_URL" "$RES" "authenticated"
TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-s13-b-token")"

scenario_step "Acquire directly over REST as a client that will never heartbeat"
status="$(api_acquire "b" "$TOKEN_B" \
  "{\"lockRequest\": {\"resource\": \"$RES\"}, \"clientId\": \"e2e-s13-ghost\"}" "$RESPONSE")"
scenario_artifact "acquire response" "$RESPONSE"

lock_id="$(api_field "$RESPONSE" lockId)"
acquire_state="$(api_field "$RESPONSE" state)"
scenario_require "Ghost lease acquired" "POST /acquire" "202/ACQUIRED" "$status/$acquire_state"

scenario_step "Queue a local waiter behind the ghost lease"
WAITER_SCRIPT="$(cat <<EOF
node {
  lock(resource: '$RES') {
    echo "S13_WAITER_ACQUIRED"
  }
}
EOF
)"
upsert_pipeline_job "$CONTROLLER_B_URL" "s13-waiter" "$WAITER_SCRIPT"
waiter_url="$(trigger_and_resolve_build_url "$CONTROLLER_B_URL" "s13-waiter" 120)"
sleep 3

scenario_step "Wait for the lease to be marked STALE (threshold ${RLR_STALE_THRESHOLD_S}s)"
record_state=""
elapsed=0
while ((elapsed < STALE_WAIT_LIMIT)); do
  record_state="$(remote_record_state "b" "$lock_id")"
  [[ "$record_state" == "STALE" ]] && break
  # Disappearing instead of going STALE would be an auto-release, which is the design this scenario
  # rules out - stop immediately rather than time out on a wrong answer.
  [[ "$record_state" == "GONE" ]] && break
  sleep 5
  elapsed=$((elapsed + 5))
done

scenario_check "Lease reached STALE without heartbeats" \
  "RemoteLockManager.find after ${elapsed}s" "STALE" "$record_state"
scenario_check_lt "STALE arrived on time" "$elapsed" "$STALE_WAIT_LIMIT" "seconds waited"

scenario_step "Check the resource is still held while STALE (fail-closed, no auto-release)"
scenario_check_resource_locked "Resource still held while STALE" "b" "$RES" "remote"

scenario_step "Force-release as an administrator, the same call the UI button makes"
release_ok="ok"
jenkins_post "$CONTROLLER_B_URL" "/lockable-resources/releaseRemoteLock" \
  -X POST --data-urlencode "resource=$RES" >/dev/null || release_ok="failed"
scenario_check "Administrator force release" "POST /lockable-resources/releaseRemoteLock" "ok" "$release_ok"

scenario_step "Check the waiter woke up"
waiter_result="$(wait_for_build_result "$waiter_url" 120)" || waiter_result="TIMEOUT"
save_console_log "$waiter_url" "$SCENARIO_DIR/waiter-console.txt"
scenario_artifact "waiter console" "$SCENARIO_DIR/waiter-console.txt"

scenario_check "Waiter result" "Build API" "SUCCESS" "$waiter_result"
scenario_check_contains "Waiter entered its body" "$SCENARIO_DIR/waiter-console.txt" "S13_WAITER_ACQUIRED"
scenario_check_resource_free "Resource free at the end" "b" "$RES"

scenario_fact "lock_id" "$lock_id"
scenario_fact "stale_after_seconds" "$elapsed"
scenario_fact "stale_threshold_seconds" "$RLR_STALE_THRESHOLD_S"
scenario_fact "waiter_result" "$waiter_result"

scenario_finish
