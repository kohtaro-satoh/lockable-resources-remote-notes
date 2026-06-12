#!/usr/bin/env bash
set -euo pipefail

# S14 (P1M1C): a resource + a LABEL-based extra entry must be acquired atomically.
# Regression coverage for M1B review finding C-1: label-based extra entries were
# silently dropped server-side (the body ran while the labelled resource was NOT
# locked — a fail-open exclusivity violation). M1C resolves all selectors (main +
# every extra, each a named resource or label+quantity) through one resolver.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

RESULTS_DIR="${1:-}"
if [[ -z "$RESULTS_DIR" ]]; then
  err "Results directory argument is required"
  exit 2
fi

SCENARIO="extra-label-resources"
SCENARIO_ID="S14"
SCENARIO_DIR="$RESULTS_DIR/$SCENARIO"
mkdir -p "$SCENARIO_DIR"

TS="$(date +%s)"
RES1="s14-res1-${TS}"
GPU="s14-gpu-${TS}"
GPU_LABEL="s14gpu${TS}"
CREDENTIALS_ID="s14-a-for-b"
DETAIL_FILE="$SCENARIO_DIR/scenario-details.md"

# --- Setup B: remote API + auth + main exposed resource + a labelled exposed resource ---
configure_remote_server "$CONTROLLER_B_URL" "$RES1" "remote-enabled" "authenticated"
verify_remote_server_config "$CONTROLLER_B_URL" "$RES1" "authenticated"
# GPU carries [remote-enabled, $GPU_LABEL] so it is both exposed and label-matchable.
configure_label_resource "$CONTROLLER_B_URL" "$GPU" "$GPU_LABEL" "remote-enabled"

# --- Setup A: credentials + remote client config ---
TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-s14-b-token")"
upsert_username_password_credential "$CONTROLLER_A_URL" "$CREDENTIALS_ID" "admin" "$TOKEN_B"
configure_remote_client_for_server "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "$CREDENTIALS_ID"

# --- Pipeline (scripted, to avoid Declarative required-parameter validation) ---
PIPELINE_SCRIPT="$(cat <<EOF
node {
  lock(resource: '$RES1', extra: [[label: '$GPU_LABEL', quantity: 1]], variable: 'S14RES', serverId: 'b') {
    echo "S14_BODY_START"
    echo "S14RES=\${env.S14RES}"
    echo "S14RES0=\${env.S14RES0}"
    echo "S14RES1=\${env.S14RES1}"
    sleep 8
    echo "S14_BODY_END"
  }
}
EOF
)"

upsert_pipeline_job "$CONTROLLER_A_URL" "s14-extra-label" "$PIPELINE_SCRIPT"
build_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s14-extra-label" 120)"

# CP02: during body, RES1 AND the gpu resource are both locked on B by the SAME lease.
# This is the core C-1 proof: the label-based extra entry is actually honoured (not dropped)
# and is acquired atomically with the main resource.
wait_for_console_contains "$build_url" "S14_BODY_START" 120 \
  || { err "S14 CP02 FAIL: body did not start"; exit 1; }

during_state="$(run_groovy_script "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
def lrm = LockableResourcesManager.get()
def r1 = lrm.fromName('${RES1}')
def gpu = lrm.fromName('${GPU}')
println('R1_LOCKID=' + (r1 == null ? 'null' : r1.getRemoteLockedBy()))
println('GPU_LOCKID=' + (gpu == null ? 'null' : gpu.getRemoteLockedBy()))
" | tr -d '\r')"

r1_lockid="$(printf '%s\n' "$during_state" | awk -F= '/^R1_LOCKID=/{print $2}' | tail -n 1)"
gpu_lockid="$(printf '%s\n' "$during_state" | awk -F= '/^GPU_LOCKID=/{print $2}' | tail -n 1)"

[[ -n "$r1_lockid" && "$r1_lockid" != "null" ]] \
  || { err "S14 CP02 FAIL: $RES1 not remote-locked during body"; exit 1; }
[[ -n "$gpu_lockid" && "$gpu_lockid" != "null" ]] \
  || { err "S14 CP02 FAIL: label-based extra resource $GPU not locked (C-1 silent-drop regression)"; exit 1; }
[[ "$r1_lockid" == "$gpu_lockid" ]] \
  || { err "S14 CP02 FAIL: lease mismatch (r1=$r1_lockid gpu=$gpu_lockid) — not atomic"; exit 1; }

result="$(wait_for_build_result "$build_url" 600)"
save_console_log "$build_url" "$SCENARIO_DIR/console.txt"

# CP01: build result SUCCESS
[[ "$result" == "SUCCESS" ]] || { err "S14 CP01 FAIL: build result=$result"; exit 1; }

# CP03: combined variable contains both the main and the (label-resolved) extra resource, comma-separated
combined="$(grep -E "^S14RES=" "$SCENARIO_DIR/console.txt" | head -1 | cut -d= -f2- | tr -d '\r')"
printf '%s' "$combined" | grep -Fq "$RES1" \
  || { err "S14 CP03 FAIL: S14RES does not contain $RES1 (S14RES=$combined)"; exit 1; }
printf '%s' "$combined" | grep -Fq "$GPU" \
  || { err "S14 CP03 FAIL: S14RES does not contain $GPU (S14RES=$combined)"; exit 1; }
printf '%s' "$combined" | grep -Fq "," \
  || { err "S14 CP03 FAIL: S14RES is not comma-separated (S14RES=$combined)"; exit 1; }

# CP04: individual indexed variables present
grep -Eq "^S14RES0=s14-" "$SCENARIO_DIR/console.txt" \
  || { err "S14 CP04 FAIL: S14RES0 not found in console"; exit 1; }
grep -Eq "^S14RES1=s14-" "$SCENARIO_DIR/console.txt" \
  || { err "S14 CP04 FAIL: S14RES1 not found in console"; exit 1; }

# CP05: both resources released after completion
after_state="$(run_groovy_script "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
def lrm = LockableResourcesManager.get()
def r1 = lrm.fromName('${RES1}')
def gpu = lrm.fromName('${GPU}')
println('R1_FREE=' + (r1 != null && r1.getRemoteLockedBy() == null && !r1.isLocked()))
println('GPU_FREE=' + (gpu != null && gpu.getRemoteLockedBy() == null && !gpu.isLocked()))
" | tr -d '\r')"

printf '%s' "$after_state" | grep -Fq "R1_FREE=true" \
  || { err "S14 CP05 FAIL: $RES1 not released (state: $after_state)"; exit 1; }
printf '%s' "$after_state" | grep -Fq "GPU_FREE=true" \
  || { err "S14 CP05 FAIL: $GPU not released (state: $after_state)"; exit 1; }

# CP06: remote lock acquisition message present
grep -Fq "Remote lock acquired on" "$SCENARIO_DIR/console.txt" \
  || { err "S14 CP06 FAIL: 'Remote lock acquired on' not found in console"; exit 1; }

cat >"$SCENARIO_DIR/summary.txt" <<EOF
build_url=$build_url
result=$result
combined=$combined
during_lease_r1=$r1_lockid
during_lease_gpu=$gpu_lockid
after_state=$(printf '%s' "$after_state" | tr '\n' ';')
EOF

cat >"$DETAIL_FILE" <<EOF
### ${SCENARIO_ID}: ${SCENARIO}

#### Summary

- build result: $result
- S14RES (combined): $combined
- during-body lease (r1/gpu): $r1_lockid / $gpu_lockid
- after state: $(printf '%s' "$after_state" | tr '\n' ';')

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (build SUCCESS) |
| CP02 | PASS (main + label-based extra locked during body by same lease — atomic, C-1) |
| CP03 | PASS (S14RES=$combined, comma-separated) |
| CP04 | PASS (S14RES0/S14RES1 present) |
| CP05 | PASS (both released after completion) |
| CP06 | PASS (Remote lock acquired on found) |

#### Artifacts

- console: $SCENARIO_DIR/console.txt
- summary: $SCENARIO_DIR/summary.txt
EOF

log "extra-label-resources: completed"
