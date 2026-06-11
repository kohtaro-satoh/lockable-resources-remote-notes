#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

RESULTS_DIR="${1:-}"
if [[ -z "$RESULTS_DIR" ]]; then
  err "Results directory argument is required"
  exit 2
fi

SCENARIO="extra-resources"
SCENARIO_ID="S10"
SCENARIO_DIR="$RESULTS_DIR/$SCENARIO"
mkdir -p "$SCENARIO_DIR"

TS="$(date +%s)"
RES1="s10-res1-${TS}"
RES2="s10-res2-${TS}"
CREDENTIALS_ID="s10-a-for-b"
DETAIL_FILE="$SCENARIO_DIR/scenario-details.md"

# --- Setup B: remote API + auth + two exposed resources ---
configure_remote_server "$CONTROLLER_B_URL" "$RES1" "remote-enabled" "authenticated"
verify_remote_server_config "$CONTROLLER_B_URL" "$RES1" "authenticated"
configure_remote_server "$CONTROLLER_B_URL" "$RES2" "remote-enabled" "authenticated"

# --- Setup A: credentials + remote client config ---
TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-s10-b-token")"
upsert_username_password_credential "$CONTROLLER_A_URL" "$CREDENTIALS_ID" "admin" "$TOKEN_B"
configure_remote_client_for_server "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "$CREDENTIALS_ID"

# --- Pipeline (scripted, to avoid Declarative required-parameter validation) ---
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

upsert_pipeline_job "$CONTROLLER_A_URL" "s10-extra" "$PIPELINE_SCRIPT"
build_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s10-extra" 120)"

# CP02: during body, both resources are locked on B by the SAME remote lease (atomic)
wait_for_console_contains "$build_url" "S10_BODY_START" 120 \
  || { err "S10 CP02 FAIL: body did not start"; exit 1; }

during_state="$(run_groovy_script "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
def lrm = LockableResourcesManager.get()
def r1 = lrm.fromName('${RES1}')
def r2 = lrm.fromName('${RES2}')
println('R1_LOCKID=' + (r1 == null ? 'null' : r1.getRemoteLockedBy()))
println('R2_LOCKID=' + (r2 == null ? 'null' : r2.getRemoteLockedBy()))
" | tr -d '\r')"

r1_lockid="$(printf '%s\n' "$during_state" | awk -F= '/^R1_LOCKID=/{print $2}' | tail -n 1)"
r2_lockid="$(printf '%s\n' "$during_state" | awk -F= '/^R2_LOCKID=/{print $2}' | tail -n 1)"

[[ -n "$r1_lockid" && "$r1_lockid" != "null" ]] \
  || { err "S10 CP02 FAIL: $RES1 not remote-locked during body"; exit 1; }
[[ "$r1_lockid" == "$r2_lockid" ]] \
  || { err "S10 CP02 FAIL: lease mismatch (r1=$r1_lockid r2=$r2_lockid) — not atomic"; exit 1; }

result="$(wait_for_build_result "$build_url" 600)"
save_console_log "$build_url" "$SCENARIO_DIR/console.txt"

# CP01: build result SUCCESS
[[ "$result" == "SUCCESS" ]] || { err "S10 CP01 FAIL: build result=$result"; exit 1; }

# CP03: combined variable contains both resources comma-separated (local lock() semantics)
combined="$(grep -E "^S10RES=" "$SCENARIO_DIR/console.txt" | head -1 | cut -d= -f2- | tr -d '\r')"
printf '%s' "$combined" | grep -Fq "$RES1" \
  || { err "S10 CP03 FAIL: S10RES does not contain $RES1 (S10RES=$combined)"; exit 1; }
printf '%s' "$combined" | grep -Fq "$RES2" \
  || { err "S10 CP03 FAIL: S10RES does not contain $RES2 (S10RES=$combined)"; exit 1; }
printf '%s' "$combined" | grep -Fq "," \
  || { err "S10 CP03 FAIL: S10RES is not comma-separated (S10RES=$combined)"; exit 1; }

# CP04: individual indexed variables present
grep -Eq "^S10RES0=s10-res" "$SCENARIO_DIR/console.txt" \
  || { err "S10 CP04 FAIL: S10RES0 not found in console"; exit 1; }
grep -Eq "^S10RES1=s10-res" "$SCENARIO_DIR/console.txt" \
  || { err "S10 CP04 FAIL: S10RES1 not found in console"; exit 1; }

# CP05: both resources released after completion
after_state="$(run_groovy_script "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
def lrm = LockableResourcesManager.get()
def r1 = lrm.fromName('${RES1}')
def r2 = lrm.fromName('${RES2}')
println('R1_FREE=' + (r1 != null && r1.getRemoteLockedBy() == null && !r1.isLocked()))
println('R2_FREE=' + (r2 != null && r2.getRemoteLockedBy() == null && !r2.isLocked()))
" | tr -d '\r')"

printf '%s' "$after_state" | grep -Fq "R1_FREE=true" \
  || { err "S10 CP05 FAIL: $RES1 not released (state: $after_state)"; exit 1; }
printf '%s' "$after_state" | grep -Fq "R2_FREE=true" \
  || { err "S10 CP05 FAIL: $RES2 not released (state: $after_state)"; exit 1; }

# CP06: remote lock acquisition message present
grep -Fq "Remote lock acquired on" "$SCENARIO_DIR/console.txt" \
  || { err "S10 CP06 FAIL: 'Remote lock acquired on' not found in console"; exit 1; }

cat >"$SCENARIO_DIR/summary.txt" <<EOF
build_url=$build_url
result=$result
combined=$combined
during_lease_r1=$r1_lockid
during_lease_r2=$r2_lockid
after_state=$(printf '%s' "$after_state" | tr '\n' ';')
EOF

cat >"$DETAIL_FILE" <<EOF
### ${SCENARIO_ID}: ${SCENARIO}

#### Summary

- build result: $result
- S10RES (combined): $combined
- during-body lease (r1/r2): $r1_lockid / $r2_lockid
- after state: $(printf '%s' "$after_state" | tr '\n' ';')

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (build SUCCESS) |
| CP02 | PASS (both locked during body by same lease — atomic) |
| CP03 | PASS (S10RES=$combined, comma-separated) |
| CP04 | PASS (S10RES0/S10RES1 present) |
| CP05 | PASS (both released after completion) |
| CP06 | PASS (Remote lock acquired on found) |

#### Artifacts

- console: $SCENARIO_DIR/console.txt
- summary: $SCENARIO_DIR/summary.txt
EOF

log "extra-resources: completed"
