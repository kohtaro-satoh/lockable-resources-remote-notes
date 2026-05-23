#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

RESULTS_DIR="${1:-}"
if [[ -z "$RESULTS_DIR" ]]; then
  err "Results directory argument is required"
  exit 2
fi

SCENARIO="server-self-use"
SCENARIO_ID="S03"
SCENARIO_DIR="$RESULTS_DIR/$SCENARIO"
mkdir -p "$SCENARIO_DIR"

RESOURCE_NAME="s03-shared-$(date +%s)"
CREDENTIALS_ID="s03-a-for-b"
DETAIL_FILE="$SCENARIO_DIR/scenario-details.md"

configure_remote_server "$CONTROLLER_B_URL" "$RESOURCE_NAME" "remote-enabled" "authenticated"
verify_remote_server_config "$CONTROLLER_B_URL" "$RESOURCE_NAME" "authenticated"
TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-s03-b-token")"
upsert_username_password_credential "$CONTROLLER_A_URL" "$CREDENTIALS_ID" "admin" "$TOKEN_B"
configure_remote_client_for_server "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "$CREDENTIALS_ID"
verify_remote_client_for_server "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "$CREDENTIALS_ID"

LOCAL_SCRIPT="$(cat <<EOF
pipeline {
  agent any
  stages {
    stage("LocalHold") {
      steps {
        lock(resource: "${RESOURCE_NAME}") {
          echo "LOCAL_HOLDER_ACQUIRED"
          sleep time: 30, unit: "SECONDS"
        }
      }
    }
  }
}
EOF
)"

REMOTE_SCRIPT="$(cat <<EOF
pipeline {
  agent any
  stages {
    stage("RemoteWait") {
      steps {
        lock(resource: "${RESOURCE_NAME}", serverId: "b") {
          echo "REMOTE_WAITER_ACQUIRED"
          sleep time: 2, unit: "SECONDS"
        }
      }
    }
  }
}
EOF
)"

upsert_pipeline_job "$CONTROLLER_B_URL" "s03-local-holder" "$LOCAL_SCRIPT"
upsert_pipeline_job "$CONTROLLER_A_URL" "s03-remote-waiter" "$REMOTE_SCRIPT"

local_url="$(trigger_and_resolve_build_url "$CONTROLLER_B_URL" "s03-local-holder" 120)"
if ! wait_for_console_contains "$local_url" "LOCAL_HOLDER_ACQUIRED" 120; then
  err "server-self-use: local holder did not acquire lock in time"
  exit 1
fi

remote_start="$(date +%s)"
remote_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s03-remote-waiter" 120)"
local_result="$(wait_for_build_result "$local_url" 900)"
remote_result="$(wait_for_build_result "$remote_url" 900)"
remote_end="$(date +%s)"
remote_duration="$((remote_end - remote_start))"

save_console_log "$local_url" "$SCENARIO_DIR/local-holder-console.txt"
save_console_log "$remote_url" "$SCENARIO_DIR/remote-waiter-console.txt"

[[ "$local_result" == "SUCCESS" ]] || exit 1
[[ "$remote_result" == "SUCCESS" ]] || exit 1

if [[ "$remote_duration" -lt 20 ]]; then
  err "server-self-use: remote waiter did not wait long enough (${remote_duration}s)"
  exit 1
fi

if ! grep -Fq "REMOTE_WAITER_ACQUIRED" "$SCENARIO_DIR/remote-waiter-console.txt"; then
  err "server-self-use: remote marker missing"
  exit 1
fi

cat >"$SCENARIO_DIR/summary.txt" <<EOF
local_build_url=$local_url
local_result=$local_result
remote_build_url=$remote_url
remote_result=$remote_result
remote_wait_seconds=$remote_duration
EOF

cat >"$DETAIL_FILE" <<EOF
### ${SCENARIO_ID}: ${SCENARIO}

#### Summary

- local holder result: $local_result
- remote waiter result: $remote_result
- remote wait seconds: $remote_duration

#### Artifacts

- local holder console: $SCENARIO_DIR/local-holder-console.txt
- remote waiter console: $SCENARIO_DIR/remote-waiter-console.txt
- summary: $SCENARIO_DIR/summary.txt
EOF

log "server-self-use: completed"
