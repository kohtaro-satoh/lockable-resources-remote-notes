#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

RESULTS_DIR="${1:-}"
if [[ -z "$RESULTS_DIR" ]]; then
  err "Results directory argument is required"
  exit 2
fi

SCENARIO="stale-admin-release"
SCENARIO_ID="S13"
SCENARIO_DIR="$RESULTS_DIR/$SCENARIO"
mkdir -p "$SCENARIO_DIR"

TS="$(date +%s)"
RES="s13-res-${TS}"
DETAIL_FILE="$SCENARIO_DIR/scenario-details.md"

# --- Setup B: remote API + auth + exposed resource ---
configure_remote_server "$CONTROLLER_B_URL" "$RES" "remote-enabled" "authenticated"
verify_remote_server_config "$CONTROLLER_B_URL" "$RES" "authenticated"
TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-s13-b-token")"

# --- 1. Ghost client acquires directly via REST and never sends heartbeats ---
acquire_response="$(curl -fsS -u "admin:$TOKEN_B" \
  -H "Content-Type: application/json" -H "Accept: application/json" \
  -X POST \
  -d "{\"lockRequest\": {\"resource\": \"$RES\"}, \"clientId\": \"e2e-s13-ghost\"}" \
  "$CONTROLLER_B_URL/lockable-resources/remote/v1/acquire/")"

lock_id="$(json_extract "$acquire_response" 'lockId')"
acquire_state="$(json_extract "$acquire_response" 'state')"

# CP01: ghost acquire succeeded
[[ "$acquire_state" == "ACQUIRED" && -n "$lock_id" ]] \
  || { err "S13 CP01 FAIL: acquire state=$acquire_state lockId=$lock_id"; exit 1; }
log "Ghost lease acquired: lockId=$lock_id"

# --- 2. Local waiter on B queues behind the ghost lease ---
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

# --- 3. Wait for the record to go STALE (threshold 60s, scan every 1s) ---
log "Waiting for STALE transition (no heartbeats; threshold 60s)..."
stale_observed=false
elapsed=0
while [[ "$elapsed" -lt 90 ]]; do
  record_state="$(run_groovy_script "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.remote.RemoteLockManager
def rec = RemoteLockManager.get().find('${lock_id}')
println('RECORD=' + (rec == null ? 'GONE' : rec.getState().name()))
" | tr -d '\r' | awk -F= '/^RECORD=/{print $2}' | tail -n 1)"
  if [[ "$record_state" == "STALE" ]]; then
    stale_observed=true
    break
  fi
  if [[ "$record_state" == "GONE" ]]; then
    err "S13 CP02 FAIL: record disappeared before STALE (auto-release would violate fail-close)"
    exit 1
  fi
  sleep 5
  elapsed=$((elapsed + 5))
done

# CP02: record reached STALE
[[ "$stale_observed" == true ]] \
  || { err "S13 CP02 FAIL: record did not reach STALE within 90s (last=$record_state)"; exit 1; }
log "Record is STALE after ~${elapsed}s"

# CP03: while STALE the resource must STILL be held (fail-close: no auto-release)
stale_state="$(run_groovy_script "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
def r = LockableResourcesManager.get().fromName('${RES}')
println('HELD=' + (r != null && r.getRemoteLockedBy() != null))
" | tr -d '\r')"
printf '%s' "$stale_state" | grep -Fq "HELD=true" \
  || { err "S13 CP03 FAIL: resource not held while STALE (fail-close violated)"; exit 1; }

# --- 4. Admin force release (same endpoint as the UI button) ---
log "Force-releasing via /lockable-resources/releaseRemoteLock"
jenkins_post "$CONTROLLER_B_URL" "/lockable-resources/releaseRemoteLock" \
  -X POST --data-urlencode "resource=$RES" >/dev/null \
  || { err "S13 CP04 FAIL: releaseRemoteLock endpoint failed"; exit 1; }

# CP05: waiter wakes up and completes
waiter_result="$(wait_for_build_result "$waiter_url" 120)"
save_console_log "$waiter_url" "$SCENARIO_DIR/waiter-console.txt"
[[ "$waiter_result" == "SUCCESS" ]] \
  || { err "S13 CP05 FAIL: waiter result=$waiter_result"; exit 1; }
grep -Fq "S13_WAITER_ACQUIRED" "$SCENARIO_DIR/waiter-console.txt" \
  || { err "S13 CP05 FAIL: waiter body marker missing"; exit 1; }

# CP06: resource free at the end
end_state="$(run_groovy_script "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
def r = LockableResourcesManager.get().fromName('${RES}')
println('FREE=' + (r != null && r.getRemoteLockedBy() == null && !r.isLocked()))
" | tr -d '\r')"
printf '%s' "$end_state" | grep -Fq "FREE=true" \
  || { err "S13 CP06 FAIL: $RES not free at end (state: $end_state)"; exit 1; }

cat >"$SCENARIO_DIR/summary.txt" <<EOF
lock_id=$lock_id
acquire_state=$acquire_state
stale_after_seconds=$elapsed
waiter_url=$waiter_url
waiter_result=$waiter_result
end_state=$(printf '%s' "$end_state" | tr '\n' ';')
EOF

cat >"$DETAIL_FILE" <<EOF
### ${SCENARIO_ID}: ${SCENARIO}

#### Summary

- ghost lease: lockId=$lock_id (no heartbeats sent)
- STALE reached after: ~${elapsed}s
- waiter result: $waiter_result

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (ghost acquire ACQUIRED) |
| CP02 | PASS (record STALE after ~${elapsed}s without heartbeats) |
| CP03 | PASS (resource still held while STALE — fail-close) |
| CP04 | PASS (admin releaseRemoteLock succeeded) |
| CP05 | PASS (local waiter woke and completed) |
| CP06 | PASS (resource free at end) |

#### Artifacts

- waiter console: $SCENARIO_DIR/waiter-console.txt
- summary: $SCENARIO_DIR/summary.txt
EOF

log "stale-admin-release: completed"
