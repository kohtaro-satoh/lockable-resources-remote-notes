#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

RESULTS_DIR="${1:-}"
if [[ -z "$RESULTS_DIR" ]]; then
  err "Results directory argument is required"
  exit 2
fi

SCENARIO="skip-if-locked"
SCENARIO_ID="S05"
SCENARIO_DIR="$RESULTS_DIR/$SCENARIO"
mkdir -p "$SCENARIO_DIR"

RESOURCE_NAME="s05-shared-$(date +%s)"
CREDENTIALS_ID="s05-a-for-b"
DETAIL_FILE="$SCENARIO_DIR/scenario-details.md"

configure_remote_server "$CONTROLLER_B_URL" "$RESOURCE_NAME" "remote-enabled" "authenticated"
verify_remote_server_config "$CONTROLLER_B_URL" "$RESOURCE_NAME" "authenticated"
TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-s05-b-token")"
upsert_username_password_credential "$CONTROLLER_A_URL" "$CREDENTIALS_ID" "admin" "$TOKEN_B"
configure_remote_client_for_server "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "$CREDENTIALS_ID"

HOLDER_SCRIPT="$(cat <<EOF
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

SKIP_SCRIPT="$(cat <<EOF
pipeline {
  agent any
  stages {
    stage("SkipLock") {
      steps {
        lock(resource: "${RESOURCE_NAME}", serverId: "b", skipIfLocked: true) {
          echo "SKIP_BODY_EXECUTED"
        }
        echo "SKIP_FLOW_DONE"
      }
    }
  }
}
EOF
)"

upsert_pipeline_job "$CONTROLLER_B_URL" "s05-local-holder" "$HOLDER_SCRIPT"
upsert_pipeline_job "$CONTROLLER_A_URL" "s05-skip-test" "$SKIP_SCRIPT"

holder_url="$(trigger_and_resolve_build_url "$CONTROLLER_B_URL" "s05-local-holder" 120)"
if ! wait_for_console_contains "$holder_url" "LOCAL_HOLDER_ACQUIRED" 120; then
  err "skip-if-locked: local holder did not acquire"
  exit 1
fi

skip_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s05-skip-test" 120)"
skip_result="$(wait_for_build_result "$skip_url" 600)"
holder_result="$(wait_for_build_result "$holder_url" 900)"

save_console_log "$holder_url" "$SCENARIO_DIR/local-holder-console.txt"
save_console_log "$skip_url" "$SCENARIO_DIR/skip-test-console.txt"

[[ "$holder_result" == "SUCCESS" ]] || exit 1
[[ "$skip_result" == "SUCCESS" ]] || exit 1

if grep -Fq "SKIP_BODY_EXECUTED" "$SCENARIO_DIR/skip-test-console.txt"; then
  err "skip-if-locked: lock body was executed unexpectedly"
  exit 1
fi

grep -Fq "SKIP_FLOW_DONE" "$SCENARIO_DIR/skip-test-console.txt" || exit 1

cat >"$SCENARIO_DIR/summary.txt" <<EOF
holder_build_url=$holder_url
holder_result=$holder_result
skip_build_url=$skip_url
skip_result=$skip_result
EOF

cat >"$DETAIL_FILE" <<EOF
### ${SCENARIO_ID}: ${SCENARIO}

#### Summary

- holder result: $holder_result
- skip test result: $skip_result
- skip body executed: no

#### Artifacts

- holder console: $SCENARIO_DIR/local-holder-console.txt
- skip console: $SCENARIO_DIR/skip-test-console.txt
- summary: $SCENARIO_DIR/summary.txt
EOF

log "skip-if-locked: completed"
