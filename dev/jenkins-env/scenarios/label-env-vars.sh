#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

RESULTS_DIR="${1:-}"
if [[ -z "$RESULTS_DIR" ]]; then
  err "Results directory argument is required"
  exit 2
fi

SCENARIO="label-env-vars"
SCENARIO_ID="S08"
SCENARIO_DIR="$RESULTS_DIR/$SCENARIO"
mkdir -p "$SCENARIO_DIR"

TS="$(date +%s)"
HW_RESOURCE="s08-hw-board-${TS}"
CREDENTIALS_ID="s08-a-for-b"
DETAIL_FILE="$SCENARIO_DIR/scenario-details.md"

# --- Setup B: remote API + auth + resource with remote-enabled + hw labels ---
configure_remote_server "$CONTROLLER_B_URL" "$HW_RESOURCE" "remote-enabled" "authenticated"
verify_remote_server_config "$CONTROLLER_B_URL" "$HW_RESOURCE" "authenticated"
configure_label_resource "$CONTROLLER_B_URL" "$HW_RESOURCE" "hw"

# --- Setup A: credentials + remote client config ---
TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-s08-b-token")"
upsert_username_password_credential "$CONTROLLER_A_URL" "$CREDENTIALS_ID" "admin" "$TOKEN_B"
configure_remote_client_for_server "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "$CREDENTIALS_ID"

# --- Pipeline ---
PIPELINE_SCRIPT="$(cat <<EOF
pipeline {
  agent any
  stages {
    stage("S08-LabelEnvVars") {
      steps {
        lock(label: 'hw', resource: null, quantity: 1, variable: 'HW_LOCK', serverId: 'b') {
          echo "HW_LOCK=\${env.HW_LOCK}"
          echo "HW_LOCK0=\${env.HW_LOCK0}"
        }
      }
    }
  }
}
EOF
)"

upsert_pipeline_job "$CONTROLLER_A_URL" "s08-label-env" "$PIPELINE_SCRIPT"
build_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s08-label-env" 120)"
result="$(wait_for_build_result "$build_url" 600)"
save_console_log "$build_url" "$SCENARIO_DIR/console.txt"

# CP01: build result SUCCESS
[[ "$result" == "SUCCESS" ]] || { err "S08 CP01 FAIL: build result=$result"; exit 1; }

# CP02: HW_LOCK contains resource name
grep -Eq "^HW_LOCK=s08-hw-board-" "$SCENARIO_DIR/console.txt" \
  || { err "S08 CP02 FAIL: HW_LOCK line not found in console"; exit 1; }

# CP03: HW_LOCK0 contains resource name
grep -Eq "^HW_LOCK0=s08-hw-board-" "$SCENARIO_DIR/console.txt" \
  || { err "S08 CP03 FAIL: HW_LOCK0 line not found in console"; exit 1; }

# CP04: HW_LOCK and HW_LOCK0 have the same value (1 resource => variable equals variable0)
hw_lock_val="$(grep -E "^HW_LOCK=s08-hw-board-" "$SCENARIO_DIR/console.txt" | head -1 | cut -d= -f2- | tr -d '\r')"
hw_lock0_val="$(grep -E "^HW_LOCK0=s08-hw-board-" "$SCENARIO_DIR/console.txt" | head -1 | cut -d= -f2- | tr -d '\r')"
[[ "$hw_lock_val" == "$hw_lock0_val" ]] \
  || { err "S08 CP04 FAIL: HW_LOCK='$hw_lock_val' != HW_LOCK0='$hw_lock0_val'"; exit 1; }

# CP06: remote lock acquisition message present
grep -Fq "Remote lock acquired on" "$SCENARIO_DIR/console.txt" \
  || { err "S08 CP06 FAIL: 'Remote lock acquired on' not found in console"; exit 1; }

# CP05: B resource released after job completion
b_state="$(run_groovy_script "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
def r = LockableResourcesManager.get().fromName('${HW_RESOURCE}')
println('EXISTS=' + (r != null))
println('LOCKED=' + (r != null && r.isLocked()))
" | tr -d '\r')"

if ! printf '%s' "$b_state" | grep -Fq "LOCKED=false"; then
  err "S08 CP05 FAIL: B resource ${HW_RESOURCE} not released (state: $b_state)"
  exit 1
fi

cat >"$SCENARIO_DIR/summary.txt" <<EOF
build_url=$build_url
result=$result
hw_lock_val=$hw_lock_val
hw_lock0_val=$hw_lock0_val
b_resource_state=$(printf '%s' "$b_state" | tr '\n' ';')
EOF

cat >"$DETAIL_FILE" <<EOF
### ${SCENARIO_ID}: ${SCENARIO}

#### Summary

- build result: $result
- HW_LOCK: $hw_lock_val
- HW_LOCK0: $hw_lock0_val
- B resource state: $(printf '%s' "$b_state" | tr '\n' ';')

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (build SUCCESS) |
| CP02 | PASS (HW_LOCK=$hw_lock_val) |
| CP03 | PASS (HW_LOCK0=$hw_lock0_val) |
| CP04 | PASS (HW_LOCK == HW_LOCK0) |
| CP05 | PASS (B resource released) |
| CP06 | PASS (Remote lock acquired on found) |

#### Artifacts

- console: $SCENARIO_DIR/console.txt
- summary: $SCENARIO_DIR/summary.txt
EOF

log "label-env-vars: completed"
