#!/usr/bin/env bash
set -euo pipefail

# S22: pausing new acquires must not disturb the leases already out.
#
# The switch exists so an administrator can drain a server before taking it down. That only works if
# the two halves are separable: new acquires are refused, while the leases in flight keep their
# heartbeats, keep their resources, and release normally. A pause that also broke live leases would
# turn a planned drain into an outage.
#
# 503 rather than an error is the other half of it - it tells a client to come back, and the client
# waits rather than failing the build.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "S22" "remote-maintenance-switch" "${1:-}"

STAMP="$(scenario_stamp)"
HELD="s22-held-$STAMP"
WANTED="s22-wanted-$STAMP"
HOLD_SECONDS=90

set_accept_new_acquires() {
  local value="$1"
  run_groovy_script_checked "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
LockableResourcesManager.get().setAcceptNewAcquires($value)
println('ACCEPT=' + LockableResourcesManager.get().isAcceptNewAcquires())
" "ACCEPT=$value" >/dev/null
}

scenario_cleanup_hook set_accept_new_acquires true

scenario_step "B serves two resources and A is its client"
setup_remote_pair "s22" "a" "b" "$HELD"
configure_label_resource "$CONTROLLER_B_URL" "$WANTED" "remote-enabled"
TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-s22-token")"

scenario_step "A takes a lease that must survive the pause"
HOLDER_SCRIPT="$(cat <<EOF
node {
  lock(resource: '$HELD', serverId: 'b') {
    echo "S22_HOLDER_IN"
    sleep ${HOLD_SECONDS}
  }
  echo "S22_HOLDER_RELEASED"
}
EOF
)"
upsert_pipeline_job "$CONTROLLER_A_URL" "s22-holder" "$HOLDER_SCRIPT"
holder_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s22-holder" 120)"
wait_for_console_contains "$holder_url" "S22_HOLDER_IN" 180 ||
  scenario_require_ok "Holder takes its lease first" "ConsoleText" "S22_HOLDER_IN never appeared"

scenario_step "Pause new acquires on B"
set_accept_new_acquires false

paused_body="$SCENARIO_DIR/acquire-paused.json"
code="$(api_acquire "b" "$TOKEN_B" "{\"lockRequest\":{\"resource\":\"${WANTED}\"}}" "$paused_body")"
scenario_artifact "refused acquire response" "$paused_body"
scenario_check_api "A new acquire is refused while paused" 503 "$code" ACQUIRES_PAUSED "$paused_body"

scenario_step "A client that meets the pause waits rather than failing"
WAITER_SCRIPT="$(cat <<EOF
node {
  lock(resource: '$WANTED', serverId: 'b') {
    echo "S22_WAITER_IN"
  }
}
EOF
)"
upsert_pipeline_job "$CONTROLLER_A_URL" "s22-waiter" "$WAITER_SCRIPT"
waiter_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s22-waiter" 120)"
wait_for_console_contains "$waiter_url" "not accepting new acquire requests" 180 ||
  scenario_require_ok "Waiter notices the pause" "ConsoleText" "the waiter never reported the pause"
save_console_log "$waiter_url" "$SCENARIO_DIR/waiter-while-paused.txt"
scenario_artifact "waiter console while paused" "$SCENARIO_DIR/waiter-while-paused.txt"

scenario_check_absent "The waiter did not get in while paused" "$SCENARIO_DIR/waiter-while-paused.txt" "S22_WAITER_IN"

scenario_step "Check the live lease is untouched"
scenario_check_resource_locked "The lease taken before the pause is still held" "b" "$HELD" "remote"

scenario_step "Resume, and let both builds finish"
set_accept_new_acquires true

waiter_result="$(wait_for_build_result "$waiter_url" 300)"
save_console_log "$waiter_url" "$SCENARIO_DIR/waiter-final.txt"
scenario_artifact "waiter console" "$SCENARIO_DIR/waiter-final.txt"
scenario_check "Waiter result after resuming" "Build API" "SUCCESS" "$waiter_result"
scenario_check_contains "Waiter finally entered the body" "$SCENARIO_DIR/waiter-final.txt" "S22_WAITER_IN"

holder_result="$(wait_for_build_result "$holder_url" 300)"
save_console_log "$holder_url" "$SCENARIO_DIR/holder.txt"
scenario_artifact "holder console" "$SCENARIO_DIR/holder.txt"
scenario_check "Holder finished cleanly through the pause" "Build API" "SUCCESS" "$holder_result"
scenario_check_contains "Holder released normally" "$SCENARIO_DIR/holder.txt" "S22_HOLDER_RELEASED"

scenario_check_resource_free "Held resource released" "b" "$HELD"
scenario_check_resource_free "Wanted resource released" "b" "$WANTED"

scenario_fact "holder_result" "$holder_result"
scenario_fact "waiter_result" "$waiter_result"
scenario_fact "paused_acquire_status" "$code"

scenario_finish
