#!/usr/bin/env bash
set -euo pipefail

# S22 (P1M2M3): the maintenance switch, from both sides.
#
# The point of the switch is that draining a server does not break the controllers locking against
# it: while it is off, a new lock() waits instead of failing, and a lease already held keeps its
# heartbeat and can be released. Turning it back on lets the waiting request through. Unit tests can
# show the 503; only a real run shows that the waiting build survives it.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

RESULTS_DIR="${1:-}"
if [[ -z "$RESULTS_DIR" ]]; then
  err "Results directory argument is required"
  exit 2
fi

SCENARIO="remote-maintenance-switch"
SCENARIO_ID="S22"
SCENARIO_DIR="$RESULTS_DIR/$SCENARIO"
mkdir -p "$SCENARIO_DIR"

TS="$(date +%s)"
HELD="s22-held-${TS}"
WANTED="s22-wanted-${TS}"
CREDENTIALS_ID="s22-a-for-b"
DETAIL_FILE="$SCENARIO_DIR/scenario-details.md"

set_accept_new_acquires() {
  local value="$1"
  run_groovy_script_checked "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
LockableResourcesManager.get().setAcceptNewAcquires($value)
println('ACCEPT=' + LockableResourcesManager.get().isAcceptNewAcquires())
" "ACCEPT=$value" >/dev/null
}

cleanup() {
  set_accept_new_acquires true >/dev/null 2>&1 || true
}
trap cleanup EXIT

# --- Setup: B serves two resources, A is a client ---
configure_remote_server "$CONTROLLER_B_URL" "$HELD" "remote-enabled" "authenticated"
verify_remote_server_config "$CONTROLLER_B_URL" "$HELD" "authenticated"
configure_label_resource "$CONTROLLER_B_URL" "$WANTED" "remote-enabled"

TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-s22-b-token")"
upsert_username_password_credential "$CONTROLLER_A_URL" "$CREDENTIALS_ID" "admin" "$TOKEN_B"
configure_remote_client_for_server "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "$CREDENTIALS_ID"

# --- A takes a lease first; it must survive the pause untouched ---
HOLDER_SCRIPT="$(cat <<EOF
node {
  lock(resource: '$HELD', serverId: 'b') {
    echo "S22_HOLDER_IN"
    sleep 90
  }
  echo "S22_HOLDER_RELEASED"
}
EOF
)"
upsert_pipeline_job "$CONTROLLER_A_URL" "s22-holder" "$HOLDER_SCRIPT"
holder_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s22-holder" 120)"
wait_for_console_contains "$holder_url" "S22_HOLDER_IN" 180

# --- Pause new acquires on B ---
set_accept_new_acquires false

# --- CP01: a new acquire is refused with 503 ACQUIRES_PAUSED ---
paused_body="$SCENARIO_DIR/acquire-paused.json"
code="$(curl -sS -o "$paused_body" -w '%{http_code}' -X POST \
  -u "admin:${TOKEN_B}" -H 'Content-Type: application/json' \
  -d "{\"lockRequest\":{\"resource\":\"${WANTED}\"}}" \
  "${CONTROLLER_B_URL}/lockable-resources/remote/v1/acquire/")"
[[ "$code" == "503" ]] \
  || { err "S22 CP01 FAIL: expected 503 while paused, got $code"; cat "$paused_body" >&2; exit 1; }
grep -Fq "ACQUIRES_PAUSED" "$paused_body" \
  || { err "S22 CP01 FAIL: the refusal does not carry ACQUIRES_PAUSED"; exit 1; }

# --- CP02: a client that meets the pause waits instead of failing ---
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
wait_for_console_contains "$waiter_url" "not accepting new acquire requests" 180
save_console_log "$waiter_url" "$SCENARIO_DIR/waiter-while-paused.txt"

if grep -Fq "S22_WAITER_IN" "$SCENARIO_DIR/waiter-while-paused.txt"; then
  err "S22 CP02 FAIL: the waiter acquired the lock while the server was paused"
  exit 1
fi

# --- CP03: the lease already held is untouched - heartbeats keep it alive, release works ---
still_held="$(run_groovy_script "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
def r = LockableResourcesManager.get().fromName('${HELD}')
println('HELD=' + (r != null && r.getRemoteLockedBy() != null))
" | tr -d '\r')"
printf '%s' "$still_held" | grep -Fq "HELD=true" \
  || { err "S22 CP03 FAIL: the lease held before the pause was lost (state: $still_held)"; exit 1; }

# --- CP04: resuming lets the waiting request through ---
set_accept_new_acquires true
waiter_result="$(wait_for_build_result "$waiter_url" 300)"
save_console_log "$waiter_url" "$SCENARIO_DIR/waiter-final.txt"
[[ "$waiter_result" == "SUCCESS" ]] \
  || { err "S22 CP04 FAIL: the waiting build did not succeed after resuming (result=$waiter_result)"; exit 1; }
grep -Fq "S22_WAITER_IN" "$SCENARIO_DIR/waiter-final.txt" \
  || { err "S22 CP04 FAIL: the waiter never entered the lock body"; exit 1; }

holder_result="$(wait_for_build_result "$holder_url" 300)"
save_console_log "$holder_url" "$SCENARIO_DIR/holder.txt"
[[ "$holder_result" == "SUCCESS" ]] \
  || { err "S22 CP03 FAIL: the holding build did not finish cleanly (result=$holder_result)"; exit 1; }

cat >"$SCENARIO_DIR/summary.txt" <<EOF
holder_url=$holder_url
holder_result=$holder_result
waiter_url=$waiter_url
waiter_result=$waiter_result
paused_acquire_http=$code
EOF

cat >"$DETAIL_FILE" <<EOF
### ${SCENARIO_ID}: ${SCENARIO}

#### Summary

- acquire while paused: HTTP $code (ACQUIRES_PAUSED)
- waiting build: $waiter_result (waited through the pause, then acquired)
- holding build: $holder_result (its lease was untouched by the pause)

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (POST /acquire answers 503 ACQUIRES_PAUSED while paused) |
| CP02 | PASS (the client waits instead of failing, and does not enter the body) |
| CP03 | PASS (a lease held before the pause stays held and releases normally) |
| CP04 | PASS (resuming lets the waiting request acquire) |

#### Artifacts

- refusal body: $SCENARIO_DIR/acquire-paused.json
- waiter console while paused: $SCENARIO_DIR/waiter-while-paused.txt
- waiter console final: $SCENARIO_DIR/waiter-final.txt
- holder console: $SCENARIO_DIR/holder.txt
EOF

log "remote-maintenance-switch: completed"
