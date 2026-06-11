#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

RESULTS_DIR="${1:-}"
if [[ -z "$RESULTS_DIR" ]]; then
  err "Results directory argument is required"
  exit 2
fi

SCENARIO="priority-ordering"
SCENARIO_ID="S12"
SCENARIO_DIR="$RESULTS_DIR/$SCENARIO"
mkdir -p "$SCENARIO_DIR"

TS="$(date +%s)"
RES="s12-res-${TS}"
CREDENTIALS_ID="s12-a-for-b"
DETAIL_FILE="$SCENARIO_DIR/scenario-details.md"

# --- Setup B: remote API + auth + exposed resource ---
configure_remote_server "$CONTROLLER_B_URL" "$RES" "remote-enabled" "authenticated"
verify_remote_server_config "$CONTROLLER_B_URL" "$RES" "authenticated"

# --- Setup A: credentials + remote client config ---
TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-s12-b-token")"
upsert_username_password_credential "$CONTROLLER_A_URL" "$CREDENTIALS_ID" "admin" "$TOKEN_B"
configure_remote_client_for_server "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "$CREDENTIALS_ID"

# --- Jobs ---
# holder (B, local): holds the resource while both waiters enqueue
HOLDER_SCRIPT="$(cat <<EOF
node {
  lock(resource: '$RES') {
    echo "S12_HOLDER_LOCKED"
    sleep 25
  }
}
EOF
)"
# local waiter (B, priority 0 = default): enqueued FIRST
LOCAL_WAITER_SCRIPT="$(cat <<EOF
node {
  lock(resource: '$RES') {
    echo "S12_LOCAL_ACQUIRED"
    sleep 2
  }
}
EOF
)"
# remote waiter (A -> B, priority 10): enqueued SECOND but must win on priority
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

# 1. holder acquires
holder_url="$(trigger_and_resolve_build_url "$CONTROLLER_B_URL" "s12-holder" 120)"
wait_for_console_contains "$holder_url" "S12_HOLDER_LOCKED" 120 \
  || { err "S12 FAIL: holder did not lock"; exit 1; }

# 2. local waiter enqueues first (priority 0)
local_url="$(trigger_and_resolve_build_url "$CONTROLLER_B_URL" "s12-local-waiter" 120)"
sleep 5

# 3. remote waiter enqueues second (priority 10)
remote_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s12-remote-high" 120)"
sleep 5

# 4. wait for holder to release
holder_result="$(wait_for_build_result "$holder_url" 600)"
[[ "$holder_result" == "SUCCESS" ]] || { err "S12 FAIL: holder result=$holder_result"; exit 1; }

# CP02: next acquirer must be the REMOTE entry (priority 10 beats FIFO-first local 0).
# Poll B during the remote hold window (10s): resource must be observed
# remote-locked. If priority ordering were broken, the local waiter (enqueued
# first) would lock it instead and we would observe a build lock, not a remote lock.
observed_remote=false
observed_local_first=false
for _ in $(seq 1 15); do
  state="$(run_groovy_script "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
def r = LockableResourcesManager.get().fromName('${RES}')
println('REMOTE=' + (r != null && r.getRemoteLockedBy() != null))
println('LOCALLOCK=' + (r != null && r.isLocked()))
" | tr -d '\r')"
  if printf '%s' "$state" | grep -Fq "REMOTE=true"; then
    observed_remote=true
    break
  fi
  if printf '%s' "$state" | grep -Fq "LOCALLOCK=true"; then
    observed_local_first=true
    break
  fi
  sleep 1
done

[[ "$observed_local_first" == false ]] \
  || { err "S12 CP02 FAIL: local waiter acquired before high-priority remote entry"; exit 1; }
[[ "$observed_remote" == true ]] \
  || { err "S12 CP02 FAIL: remote lock was never observed after holder release"; exit 1; }

# 5. both waiters complete
remote_result="$(wait_for_build_result "$remote_url" 600)"
local_result="$(wait_for_build_result "$local_url" 600)"

save_console_log "$holder_url" "$SCENARIO_DIR/holder-console.txt"
save_console_log "$local_url" "$SCENARIO_DIR/local-waiter-console.txt"
save_console_log "$remote_url" "$SCENARIO_DIR/remote-high-console.txt"

# CP01: all builds SUCCESS
[[ "$remote_result" == "SUCCESS" ]] || { err "S12 CP01 FAIL: remote result=$remote_result"; exit 1; }
[[ "$local_result" == "SUCCESS" ]] || { err "S12 CP01 FAIL: local result=$local_result"; exit 1; }

# CP03: both waiters actually entered their bodies
grep -Fq "S12_REMOTE_ACQUIRED" "$SCENARIO_DIR/remote-high-console.txt" \
  || { err "S12 CP03 FAIL: remote body marker missing"; exit 1; }
grep -Fq "S12_LOCAL_ACQUIRED" "$SCENARIO_DIR/local-waiter-console.txt" \
  || { err "S12 CP03 FAIL: local body marker missing"; exit 1; }

# CP04: resource free at the end
end_state="$(run_groovy_script "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
def r = LockableResourcesManager.get().fromName('${RES}')
println('FREE=' + (r != null && r.getRemoteLockedBy() == null && !r.isLocked()))
" | tr -d '\r')"
printf '%s' "$end_state" | grep -Fq "FREE=true" \
  || { err "S12 CP04 FAIL: $RES not free at end (state: $end_state)"; exit 1; }

cat >"$SCENARIO_DIR/summary.txt" <<EOF
holder_url=$holder_url
local_url=$local_url
remote_url=$remote_url
holder_result=$holder_result
local_result=$local_result
remote_result=$remote_result
observed_remote_first=$observed_remote
EOF

cat >"$DETAIL_FILE" <<EOF
### ${SCENARIO_ID}: ${SCENARIO}

#### Summary

- holder (B local): $holder_result
- local waiter (B, priority 0, enqueued first): $local_result
- remote waiter (A->B, priority 10, enqueued second): $remote_result
- after holder release the resource was observed remote-locked first: $observed_remote

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (all three builds SUCCESS) |
| CP02 | PASS (priority-10 remote entry acquired before priority-0 local waiter) |
| CP03 | PASS (both waiter bodies executed) |
| CP04 | PASS (resource free at end) |

#### Artifacts

- holder console: $SCENARIO_DIR/holder-console.txt
- local waiter console: $SCENARIO_DIR/local-waiter-console.txt
- remote high console: $SCENARIO_DIR/remote-high-console.txt
- summary: $SCENARIO_DIR/summary.txt
EOF

log "priority-ordering: completed"
