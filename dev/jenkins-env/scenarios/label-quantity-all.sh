#!/usr/bin/env bash
set -euo pipefail

# S15 (P1M1C follow-up): lock(label: X) with NO quantity must lock EVERY matching
# resource — local lock() treats an unspecified quantity as "0 = all". Since M1A the
# remote path locked only 1; this scenario proves the full-pool acquisition under a
# single lease (transparent equivalence for the label/quantity dimension of extra).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

RESULTS_DIR="${1:-}"
if [[ -z "$RESULTS_DIR" ]]; then
  err "Results directory argument is required"
  exit 2
fi

SCENARIO="label-quantity-all"
SCENARIO_ID="S15"
SCENARIO_DIR="$RESULTS_DIR/$SCENARIO"
mkdir -p "$SCENARIO_DIR"

TS="$(date +%s)"
POOL1="s15-pool1-${TS}"
POOL2="s15-pool2-${TS}"
POOL3="s15-pool3-${TS}"
POOL_LABEL="s15pool${TS}"
CREDENTIALS_ID="s15-a-for-b"
DETAIL_FILE="$SCENARIO_DIR/scenario-details.md"

# --- Setup B: remote API + auth + a pool of 3 exposed resources all carrying $POOL_LABEL ---
configure_remote_server "$CONTROLLER_B_URL" "$POOL1" "remote-enabled" "authenticated"
verify_remote_server_config "$CONTROLLER_B_URL" "$POOL1" "authenticated"
configure_label_resource "$CONTROLLER_B_URL" "$POOL1" "$POOL_LABEL" "remote-enabled"
configure_label_resource "$CONTROLLER_B_URL" "$POOL2" "$POOL_LABEL" "remote-enabled"
configure_label_resource "$CONTROLLER_B_URL" "$POOL3" "$POOL_LABEL" "remote-enabled"

# --- Setup A: credentials + remote client config ---
TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-s15-b-token")"
upsert_username_password_credential "$CONTROLLER_A_URL" "$CREDENTIALS_ID" "admin" "$TOKEN_B"
configure_remote_client_for_server "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "$CREDENTIALS_ID"

# --- Pipeline (scripted; NO quantity => lock ALL matching) ---
PIPELINE_SCRIPT="$(cat <<EOF
node {
  lock(label: '$POOL_LABEL', variable: 'S15RES', serverId: 'b') {
    echo "S15_BODY_START"
    echo "S15RES=\${env.S15RES}"
    sleep 8
    echo "S15_BODY_END"
  }
}
EOF
)"

upsert_pipeline_job "$CONTROLLER_A_URL" "s15-label-all" "$PIPELINE_SCRIPT"
build_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s15-label-all" 120)"

# CP02: during body, ALL THREE pool resources are locked on B by the SAME lease.
# This is the core "0 = all" proof (and atomicity across the whole pool).
wait_for_console_contains "$build_url" "S15_BODY_START" 120 \
  || { err "S15 CP02 FAIL: body did not start"; exit 1; }

during_state="$(run_groovy_script "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
def lrm = LockableResourcesManager.get()
['${POOL1}','${POOL2}','${POOL3}'].each { n ->
  def r = lrm.fromName(n)
  println(n + '_LOCKID=' + (r == null ? 'null' : r.getRemoteLockedBy()))
}
" | tr -d '\r')"

l1="$(printf '%s\n' "$during_state" | awk -F= '/_LOCKID=/{print $2}' | sed -n '1p')"
l2="$(printf '%s\n' "$during_state" | awk -F= '/_LOCKID=/{print $2}' | sed -n '2p')"
l3="$(printf '%s\n' "$during_state" | awk -F= '/_LOCKID=/{print $2}' | sed -n '3p')"

[[ -n "$l1" && "$l1" != "null" ]] \
  || { err "S15 CP02 FAIL: $POOL1 not locked during body (only-1 regression?). state: $during_state"; exit 1; }
[[ "$l1" == "$l2" && "$l2" == "$l3" ]] \
  || { err "S15 CP02 FAIL: not all pool resources locked under one lease (l1=$l1 l2=$l2 l3=$l3) — 'all' semantics broken"; exit 1; }

result="$(wait_for_build_result "$build_url" 600)"
save_console_log "$build_url" "$SCENARIO_DIR/console.txt"

# CP01: build result SUCCESS
[[ "$result" == "SUCCESS" ]] || { err "S15 CP01 FAIL: build result=$result"; exit 1; }

# CP03: combined variable contains all three pool resources, comma-separated
combined="$(grep -E "^S15RES=" "$SCENARIO_DIR/console.txt" | head -1 | cut -d= -f2- | tr -d '\r')"
for p in "$POOL1" "$POOL2" "$POOL3"; do
  printf '%s' "$combined" | grep -Fq "$p" \
    || { err "S15 CP03 FAIL: S15RES does not contain $p (S15RES=$combined)"; exit 1; }
done
printf '%s' "$combined" | grep -Fq "," \
  || { err "S15 CP03 FAIL: S15RES is not comma-separated (S15RES=$combined)"; exit 1; }

# CP05: all three released after completion
after_state="$(run_groovy_script "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
def lrm = LockableResourcesManager.get()
['${POOL1}','${POOL2}','${POOL3}'].each { n ->
  def r = lrm.fromName(n)
  println(n + '_FREE=' + (r != null && r.getRemoteLockedBy() == null && !r.isLocked()))
}
" | tr -d '\r')"

for p in "$POOL1" "$POOL2" "$POOL3"; do
  printf '%s' "$after_state" | grep -Fq "${p}_FREE=true" \
    || { err "S15 CP05 FAIL: $p not released (state: $after_state)"; exit 1; }
done

# CP06: remote lock acquisition message present
grep -Fq "Remote lock acquired on" "$SCENARIO_DIR/console.txt" \
  || { err "S15 CP06 FAIL: 'Remote lock acquired on' not found in console"; exit 1; }

cat >"$SCENARIO_DIR/summary.txt" <<EOF
build_url=$build_url
result=$result
combined=$combined
during_lease=$l1
after_state=$(printf '%s' "$after_state" | tr '\n' ';')
EOF

cat >"$DETAIL_FILE" <<EOF
### ${SCENARIO_ID}: ${SCENARIO}

#### Summary

- build result: $result
- S15RES (combined): $combined
- during-body lease (all three): $l1
- after state: $(printf '%s' "$after_state" | tr '\n' ';')

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (build SUCCESS) |
| CP02 | PASS (all 3 pool resources locked during body under one lease — "0 = all") |
| CP03 | PASS (S15RES=$combined, all three, comma-separated) |
| CP05 | PASS (all three released after completion) |
| CP06 | PASS (Remote lock acquired on found) |

#### Artifacts

- console: $SCENARIO_DIR/console.txt
- summary: $SCENARIO_DIR/summary.txt
EOF

log "label-quantity-all: completed"
