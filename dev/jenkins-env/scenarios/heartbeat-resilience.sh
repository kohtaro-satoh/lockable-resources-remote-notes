#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

RESULTS_DIR="${1:-}"
if [[ -z "$RESULTS_DIR" ]]; then
  err "Results directory argument is required"
  exit 2
fi

SCENARIO="heartbeat-resilience"
SCENARIO_ID="S11"
SCENARIO_DIR="$RESULTS_DIR/$SCENARIO"
mkdir -p "$SCENARIO_DIR"

TS="$(date +%s)"
RES="s11-res-${TS}"
CREDENTIALS_ID="s11-a-for-b"
DETAIL_FILE="$SCENARIO_DIR/scenario-details.md"
CONTAINER_A="lrr-jenkins-a"

# --- Setup B: remote API + auth + exposed resource ---
configure_remote_server "$CONTROLLER_B_URL" "$RES" "remote-enabled" "authenticated"
verify_remote_server_config "$CONTROLLER_B_URL" "$RES" "authenticated"

# --- Setup A: credentials + remote client config ---
TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-s11-b-token")"
upsert_username_password_credential "$CONTROLLER_A_URL" "$CREDENTIALS_ID" "admin" "$TOKEN_B"
configure_remote_client_for_server "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "$CREDENTIALS_ID"

# --- Pipeline: body long enough to span several failed heartbeats (10s interval) ---
PIPELINE_SCRIPT="$(cat <<EOF
node {
  lock(resource: '$RES', serverId: 'b') {
    echo "S11_BODY_START"
    sleep 40
    echo "S11_BODY_END"
  }
}
EOF
)"

upsert_pipeline_job "$CONTROLLER_A_URL" "s11-heartbeat" "$PIPELINE_SCRIPT"
build_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s11-heartbeat" 120)"

wait_for_console_contains "$build_url" "S11_BODY_START" 120 \
  || { err "S11 FAIL: body did not start"; exit 1; }

# Record timestamp for docker-log filtering, then break heartbeats by disabling
# the remote API on B mid-body. Re-enable before the body ends so the final
# release succeeds.
HB_BREAK_FROM="$(date -u '+%Y-%m-%dT%H:%M:%S')"
log "Disabling remote API on B to break heartbeats (~25s)"
run_groovy_script_checked "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
LockableResourcesManager.get().setRemoteApiEnabled(false)
println('OK: remote API disabled')
" "OK: remote API disabled" >/dev/null

sleep 25

log "Re-enabling remote API on B"
run_groovy_script_checked "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
LockableResourcesManager.get().setRemoteApiEnabled(true)
println('OK: remote API enabled')
" "OK: remote API enabled" >/dev/null

result="$(wait_for_build_result "$build_url" 600)"
save_console_log "$build_url" "$SCENARIO_DIR/console.txt"

# CP01: build SUCCESS (job continued despite heartbeat failures)
[[ "$result" == "SUCCESS" ]] || { err "S11 CP01 FAIL: build result=$result"; exit 1; }

# CP02: body ran to completion (was not interrupted)
grep -Fq "S11_BODY_END" "$SCENARIO_DIR/console.txt" \
  || { err "S11 CP02 FAIL: S11_BODY_END not found in console"; exit 1; }

# CP03: heartbeat failures actually happened (A-side warning log) — without this
# the scenario would pass vacuously
docker logs --since "$HB_BREAK_FROM" "$CONTAINER_A" 2>&1 \
  | grep -F "Remote heartbeat failed (continuing job; server retains lock)" \
  >"$SCENARIO_DIR/heartbeat-warnings.txt" \
  || { err "S11 CP03 FAIL: no heartbeat-failure warning in $CONTAINER_A logs"; exit 1; }
hb_warn_count="$(wc -l < "$SCENARIO_DIR/heartbeat-warnings.txt")"

# CP04: B resource released after completion
b_state="$(run_groovy_script "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
def r = LockableResourcesManager.get().fromName('${RES}')
println('FREE=' + (r != null && r.getRemoteLockedBy() == null && !r.isLocked()))
" | tr -d '\r')"
printf '%s' "$b_state" | grep -Fq "FREE=true" \
  || { err "S11 CP04 FAIL: $RES not released (state: $b_state)"; exit 1; }

cat >"$SCENARIO_DIR/summary.txt" <<EOF
build_url=$build_url
result=$result
heartbeat_warning_count=$hb_warn_count
b_resource_state=$(printf '%s' "$b_state" | tr '\n' ';')
EOF

cat >"$DETAIL_FILE" <<EOF
### ${SCENARIO_ID}: ${SCENARIO}

#### Summary

- build result: $result
- heartbeat warnings observed on A: $hb_warn_count
- B resource state: $(printf '%s' "$b_state" | tr '\n' ';')

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (build SUCCESS despite heartbeat failures) |
| CP02 | PASS (body ran to completion) |
| CP03 | PASS ($hb_warn_count heartbeat-failure warnings on A) |
| CP04 | PASS (B resource released after completion) |

#### Artifacts

- console: $SCENARIO_DIR/console.txt
- heartbeat warnings: $SCENARIO_DIR/heartbeat-warnings.txt
- summary: $SCENARIO_DIR/summary.txt
EOF

log "heartbeat-resilience: completed"
