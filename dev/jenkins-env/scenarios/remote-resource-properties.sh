#!/usr/bin/env bash
set -euo pipefail

# S16 (P1M1D): resource-property env vars propagate over the bridge. local lock() injects
# VAR0_<PROP> from a resource's properties; M1D shares the env-var generator between local and
# remote, so a remote lock must expose the same VAR0_<PROP>. Proves the canonical-delegation win
# end-to-end (previously remote dropped property env vars).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

RESULTS_DIR="${1:-}"
if [[ -z "$RESULTS_DIR" ]]; then
  err "Results directory argument is required"
  exit 2
fi

SCENARIO="remote-resource-properties"
SCENARIO_ID="S16"
SCENARIO_DIR="$RESULTS_DIR/$SCENARIO"
mkdir -p "$SCENARIO_DIR"

TS="$(date +%s)"
RES="s16-board-${TS}"
PROP_VALUE="10.9.8.${TS: -2}"
CREDENTIALS_ID="s16-a-for-b"
DETAIL_FILE="$SCENARIO_DIR/scenario-details.md"

# --- Setup B: remote API + auth + exposed resource carrying a property S16_IP ---
configure_remote_server "$CONTROLLER_B_URL" "$RES" "remote-enabled" "authenticated"
verify_remote_server_config "$CONTROLLER_B_URL" "$RES" "authenticated"
run_groovy_script_checked "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
import org.jenkins.plugins.lockableresources.LockableResourceProperty
def lrm = LockableResourcesManager.get()
def r = lrm.fromName('${RES}')
def p = new LockableResourceProperty()
p.setName('S16_IP')
p.setValue('${PROP_VALUE}')
r.setProperties([p])
lrm.save()
println('PROP_SET=' + r.getProperties().size())
" "PROP_SET="

# --- Setup A: credentials + remote client config ---
TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-s16-b-token")"
upsert_username_password_credential "$CONTROLLER_A_URL" "$CREDENTIALS_ID" "admin" "$TOKEN_B"
configure_remote_client_for_server "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "$CREDENTIALS_ID"

# --- Pipeline (scripted) ---
PIPELINE_SCRIPT="$(cat <<EOF
node {
  lock(resource: '$RES', variable: 'S16RES', serverId: 'b') {
    echo "S16_BODY_START"
    echo "S16RES=\${env.S16RES}"
    echo "S16RES0=\${env.S16RES0}"
    echo "S16RES0_S16_IP=\${env.S16RES0_S16_IP}"
    echo "S16_BODY_END"
  }
}
EOF
)"

upsert_pipeline_job "$CONTROLLER_A_URL" "s16-props" "$PIPELINE_SCRIPT"
build_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s16-props" 120)"
result="$(wait_for_build_result "$build_url" 600)"
save_console_log "$build_url" "$SCENARIO_DIR/console.txt"

# CP01: build result SUCCESS
[[ "$result" == "SUCCESS" ]] || { err "S16 CP01 FAIL: build result=$result"; exit 1; }

# CP02: combined + indexed variable present
grep -Eq "^S16RES=${RES}$" "$SCENARIO_DIR/console.txt" \
  || { err "S16 CP02 FAIL: S16RES not equal to $RES"; exit 1; }
grep -Eq "^S16RES0=${RES}$" "$SCENARIO_DIR/console.txt" \
  || { err "S16 CP02 FAIL: S16RES0 not equal to $RES"; exit 1; }

# CP03: resource-property env var propagated (the M1D win) — S16RES0_S16_IP == property value
prop_line="$(grep -E "^S16RES0_S16_IP=" "$SCENARIO_DIR/console.txt" | head -1 | cut -d= -f2- | tr -d '\r')"
[[ "$prop_line" == "$PROP_VALUE" ]] \
  || { err "S16 CP03 FAIL: property env var S16RES0_S16_IP='$prop_line' != '$PROP_VALUE' (property env var not bridged)"; exit 1; }

# CP04: remote lock acquisition message present
grep -Fq "Remote lock acquired on" "$SCENARIO_DIR/console.txt" \
  || { err "S16 CP04 FAIL: 'Remote lock acquired on' not found in console"; exit 1; }

# CP05: resource released after completion
after_state="$(run_groovy_script "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
def r = LockableResourcesManager.get().fromName('${RES}')
println('FREE=' + (r != null && r.getRemoteLockedBy() == null && !r.isLocked()))
" | tr -d '\r')"
printf '%s' "$after_state" | grep -Fq "FREE=true" \
  || { err "S16 CP05 FAIL: $RES not released (state: $after_state)"; exit 1; }

cat >"$SCENARIO_DIR/summary.txt" <<EOF
build_url=$build_url
result=$result
property_value=$PROP_VALUE
S16RES0_S16_IP=$prop_line
after_state=$(printf '%s' "$after_state" | tr '\n' ';')
EOF

cat >"$DETAIL_FILE" <<EOF
### ${SCENARIO_ID}: ${SCENARIO}

#### Summary

- build result: $result
- property value: $PROP_VALUE
- S16RES0_S16_IP (bridged): $prop_line
- after state: $(printf '%s' "$after_state" | tr '\n' ';')

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (build SUCCESS) |
| CP02 | PASS (S16RES / S16RES0 == $RES) |
| CP03 | PASS (resource-property env var S16RES0_S16_IP=$prop_line bridged) |
| CP04 | PASS (Remote lock acquired on found) |
| CP05 | PASS (resource released after completion) |

#### Artifacts

- console: $SCENARIO_DIR/console.txt
- summary: $SCENARIO_DIR/summary.txt
EOF

log "remote-resource-properties: completed"
