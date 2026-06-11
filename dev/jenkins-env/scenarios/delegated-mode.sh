#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

RESULTS_DIR="${1:-}"
if [[ -z "$RESULTS_DIR" ]]; then
  err "Results directory argument is required"
  exit 2
fi

SCENARIO="delegated-mode"
SCENARIO_ID="S09"
SCENARIO_DIR="$RESULTS_DIR/$SCENARIO"
mkdir -p "$SCENARIO_DIR"

TS="$(date +%s)"
B_RESOURCE="s09-res-b-${TS}"
A_LOCAL_RESOURCE="s09-local-a-${TS}"
CREDENTIALS_ID="s09-a-for-b"
DETAIL_FILE="$SCENARIO_DIR/scenario-details.md"

# --- Setup B: remote API + auth + exposed resource ---
configure_remote_server "$CONTROLLER_B_URL" "$B_RESOURCE" "remote-enabled" "authenticated"
verify_remote_server_config "$CONTROLLER_B_URL" "$B_RESOURCE" "authenticated"

# --- Setup A: local resource + credentials + remote client ---
configure_local_resource "$CONTROLLER_A_URL" "$A_LOCAL_RESOURCE"
TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-s09-b-token")"
upsert_username_password_credential "$CONTROLLER_A_URL" "$CREDENTIALS_ID" "admin" "$TOKEN_B"
configure_remote_client_for_server "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "$CREDENTIALS_ID"

# --- Setup A: forcedServerId = 'b' ---
configure_forced_server_id "$CONTROLLER_A_URL" "b"

# --- Pipeline s09-delegated (no serverId in DSL) ---
DELEGATED_PIPELINE="$(cat <<EOF
pipeline {
  agent any
  stages {
    stage("S09-Delegated") {
      steps {
        lock(resource: '${B_RESOURCE}') {
          echo "DELEGATED_ACQUIRED"
        }
      }
    }
  }
}
EOF
)"

upsert_pipeline_job "$CONTROLLER_A_URL" "s09-delegated" "$DELEGATED_PIPELINE"
delegated_build_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s09-delegated" 120)"
delegated_result="$(wait_for_build_result "$delegated_build_url" 600)"
save_console_log "$delegated_build_url" "$SCENARIO_DIR/delegated-console.txt"

# CP01: build result SUCCESS
[[ "$delegated_result" == "SUCCESS" ]] \
  || { err "S09 CP01 FAIL: s09-delegated build result=$delegated_result"; exit 1; }

# CP02: DELEGATED_ACQUIRED in console
grep -Fq "DELEGATED_ACQUIRED" "$SCENARIO_DIR/delegated-console.txt" \
  || { err "S09 CP02 FAIL: DELEGATED_ACQUIRED not found in console"; exit 1; }

# CP03: Remote lock acquired on in console
grep -Fq "Remote lock acquired on" "$SCENARIO_DIR/delegated-console.txt" \
  || { err "S09 CP03 FAIL: 'Remote lock acquired on' not found in console"; exit 1; }

# CP04: serverId=b in console (proof of forcedServerId delegation)
grep -Fq "serverId=b" "$SCENARIO_DIR/delegated-console.txt" \
  || { err "S09 CP04 FAIL: 'serverId=b' not found in console"; exit 1; }

# --- Clear forcedServerId on A ---
configure_forced_server_id_empty "$CONTROLLER_A_URL"

# --- Pipeline s09-local-fallback (forcedServerId cleared) ---
FALLBACK_PIPELINE="$(cat <<EOF
pipeline {
  agent any
  stages {
    stage("S09-LocalFallback") {
      steps {
        lock(resource: '${A_LOCAL_RESOURCE}') {
          echo "LOCAL_ACQUIRED"
        }
      }
    }
  }
}
EOF
)"

upsert_pipeline_job "$CONTROLLER_A_URL" "s09-local-fallback" "$FALLBACK_PIPELINE"
fallback_build_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s09-local-fallback" 120)"
fallback_result="$(wait_for_build_result "$fallback_build_url" 600)"
save_console_log "$fallback_build_url" "$SCENARIO_DIR/fallback-console.txt"

# CP05: fallback build result SUCCESS
[[ "$fallback_result" == "SUCCESS" ]] \
  || { err "S09 CP05 FAIL: s09-local-fallback build result=$fallback_result"; exit 1; }

# CP06: LOCAL_ACQUIRED in fallback console
grep -Fq "LOCAL_ACQUIRED" "$SCENARIO_DIR/fallback-console.txt" \
  || { err "S09 CP06 FAIL: LOCAL_ACQUIRED not found in fallback console"; exit 1; }

# CP07: Remote lock acquired on NOT in fallback console (local mode restored)
if grep -Fq "Remote lock acquired on" "$SCENARIO_DIR/fallback-console.txt"; then
  err "S09 CP07 FAIL: 'Remote lock acquired on' should not appear in fallback console"
  exit 1
fi

# CP08: B resource released after jobs complete
b_state="$(run_groovy_script "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
def r = LockableResourcesManager.get().fromName('${B_RESOURCE}')
println('EXISTS=' + (r != null))
println('LOCKED=' + (r != null && r.isLocked()))
" | tr -d '\r')"

if ! printf '%s' "$b_state" | grep -Fq "LOCKED=false"; then
  err "S09 CP08 FAIL: B resource ${B_RESOURCE} not released (state: $b_state)"
  exit 1
fi

cat >"$SCENARIO_DIR/summary.txt" <<EOF
delegated_build_url=$delegated_build_url
delegated_result=$delegated_result
fallback_build_url=$fallback_build_url
fallback_result=$fallback_result
b_resource_state=$(printf '%s' "$b_state" | tr '\n' ';')
EOF

cat >"$DETAIL_FILE" <<EOF
### ${SCENARIO_ID}: ${SCENARIO}

#### Summary

- s09-delegated result: $delegated_result
- s09-local-fallback result: $fallback_result
- B resource state: $(printf '%s' "$b_state" | tr '\n' ';')

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (s09-delegated SUCCESS) |
| CP02 | PASS (DELEGATED_ACQUIRED found) |
| CP03 | PASS (Remote lock acquired on found) |
| CP04 | PASS (serverId=b found) |
| CP05 | PASS (s09-local-fallback SUCCESS) |
| CP06 | PASS (LOCAL_ACQUIRED found) |
| CP07 | PASS (Remote lock acquired on absent in fallback) |
| CP08 | PASS (B resource released) |

#### Artifacts

- delegated console: $SCENARIO_DIR/delegated-console.txt
- fallback console: $SCENARIO_DIR/fallback-console.txt
- summary: $SCENARIO_DIR/summary.txt
EOF

log "delegated-mode: completed"
