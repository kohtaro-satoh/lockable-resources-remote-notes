#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

RESULTS_DIR="${1:-}"
if [[ -z "$RESULTS_DIR" ]]; then
  err "Results directory argument is required"
  exit 2
fi

SCENARIO="mixed-local-remote"
SCENARIO_ID="S04"
SCENARIO_DIR="$RESULTS_DIR/$SCENARIO"
mkdir -p "$SCENARIO_DIR"

LOCAL_RESOURCE="s04-local-a-$(date +%s)"
REMOTE_RESOURCE="s04-remote-b-$(date +%s)"
CREDENTIALS_ID="s04-a-for-b"
DETAIL_FILE="$SCENARIO_DIR/scenario-details.md"

configure_local_resource "$CONTROLLER_A_URL" "$LOCAL_RESOURCE"
configure_remote_server "$CONTROLLER_B_URL" "$REMOTE_RESOURCE" "remote-enabled" "authenticated"
verify_remote_server_config "$CONTROLLER_B_URL" "$REMOTE_RESOURCE" "authenticated"
TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-s04-b-token")"
upsert_username_password_credential "$CONTROLLER_A_URL" "$CREDENTIALS_ID" "admin" "$TOKEN_B"
configure_remote_client_for_server "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "$CREDENTIALS_ID"

PIPELINE_SCRIPT="$(cat <<EOF
pipeline {
  agent any
  stages {
    stage("Mixed") {
      steps {
        lock(resource: "${LOCAL_RESOURCE}") {
          lock(resource: "${REMOTE_RESOURCE}", serverId: "b") {
            echo "BOTH_ACQUIRED"
          }
        }
      }
    }
  }
}
EOF
)"

upsert_pipeline_job "$CONTROLLER_A_URL" "s04-mixed-lock" "$PIPELINE_SCRIPT"
build_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s04-mixed-lock" 120)"
result="$(wait_for_build_result "$build_url" 600)"
save_console_log "$build_url" "$SCENARIO_DIR/console.txt"

[[ "$result" == "SUCCESS" ]] || exit 1
grep -Fq "BOTH_ACQUIRED" "$SCENARIO_DIR/console.txt" || exit 1

local_state="$(run_groovy_script "$CONTROLLER_A_URL" "import org.jenkins.plugins.lockableresources.LockableResourcesManager; def r=LockableResourcesManager.get().fromName('${LOCAL_RESOURCE}'); println('EXISTS=' + (r!=null)); println('LOCKED=' + (r!=null && r.isLocked()))" | tr -d '\r')"
remote_state="$(run_groovy_script "$CONTROLLER_B_URL" "import org.jenkins.plugins.lockableresources.LockableResourcesManager; def r=LockableResourcesManager.get().fromName('${REMOTE_RESOURCE}'); println('EXISTS=' + (r!=null)); println('LOCKED=' + (r!=null && r.isLocked()))" | tr -d '\r')"

if ! printf '%s' "$local_state" | grep -Fq "LOCKED=false"; then
  err "mixed-local-remote: local resource lock state is not false"
  exit 1
fi
if ! printf '%s' "$remote_state" | grep -Fq "LOCKED=false"; then
  err "mixed-local-remote: remote resource lock state is not false"
  err "mixed-local-remote: resource unlock verification failed"
  exit 1
fi

cat >"$SCENARIO_DIR/summary.txt" <<EOF
build_url=$build_url
result=$result
local_state=$(printf '%s' "$local_state" | tr '\n' ';')
remote_state=$(printf '%s' "$remote_state" | tr '\n' ';')
EOF

cat >"$DETAIL_FILE" <<EOF
### ${SCENARIO_ID}: ${SCENARIO}

#### Summary

- build result: $result
- local unlock state: $(printf '%s' "$local_state" | tr '\n' ';')
- remote unlock state: $(printf '%s' "$remote_state" | tr '\n' ';')

#### Artifacts

- console: $SCENARIO_DIR/console.txt
- summary: $SCENARIO_DIR/summary.txt
EOF

log "mixed-local-remote: completed"
