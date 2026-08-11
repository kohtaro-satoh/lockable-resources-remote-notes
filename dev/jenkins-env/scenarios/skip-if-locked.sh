#!/usr/bin/env bash
set -euo pipefail

# S05: skipIfLocked over the remote path.
#
# skipIfLocked means "skip the body, carry on with the build" - not "fail", and not "wait". Over a
# remote the distinction is easy to lose, because a contended acquire and a refused one look the
# same from the client until the response is read. Both halves are asserted: the body did not run,
# and the build carried on past the lock step.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "S05" "skip-if-locked" "${1:-}"

RESOURCE_NAME="s05-shared-$(scenario_stamp)"
HOLD_SECONDS=30

scenario_step "Expose the resource on B and link A to it"
setup_remote_pair "s05" "a" "b" "$RESOURCE_NAME"

HOLDER_SCRIPT="$(cat <<EOF
pipeline {
  agent any
  stages {
    stage("LocalHold") {
      steps {
        lock(resource: "${RESOURCE_NAME}") {
          echo "LOCAL_HOLDER_ACQUIRED"
          sleep time: ${HOLD_SECONDS}, unit: "SECONDS"
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

scenario_step "Hold the resource locally on B, then ask from A with skipIfLocked"
holder_url="$(trigger_and_resolve_build_url "$CONTROLLER_B_URL" "s05-local-holder" 120)"
wait_for_console_contains "$holder_url" "LOCAL_HOLDER_ACQUIRED" 120 ||
  scenario_require_ok "Local holder acquires first" "ConsoleText" "LOCAL_HOLDER_ACQUIRED never appeared"

skip_start="$(date +%s)"
skip_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s05-skip-test" 120)"
skip_result="$(wait_for_build_result "$skip_url" 600)"
skip_duration="$(($(date +%s) - skip_start))"
holder_result="$(wait_for_build_result "$holder_url" 900)"

save_console_log "$holder_url" "$SCENARIO_DIR/local-holder-console.txt"
save_console_log "$skip_url" "$SCENARIO_DIR/skip-test-console.txt"
scenario_artifact "holder-console" "$SCENARIO_DIR/local-holder-console.txt"
scenario_artifact "skip-console" "$SCENARIO_DIR/skip-test-console.txt"

scenario_check "Holder result" "Build API" "SUCCESS" "$holder_result"
scenario_check "Skipping build result" "Build API" "SUCCESS" "$skip_result"
scenario_check_absent "Body was skipped, not executed" "$SCENARIO_DIR/skip-test-console.txt" "SKIP_BODY_EXECUTED"
scenario_check_contains "Build carried on past the lock step" "$SCENARIO_DIR/skip-test-console.txt" "SKIP_FLOW_DONE"

# skipIfLocked must return rather than queue. The holder keeps the resource for HOLD_SECONDS, so a
# skipping build that took anywhere near that long did not skip - it waited.
scenario_check_lt "Skip returned instead of queueing" "$skip_duration" "$HOLD_SECONDS" "elapsed seconds"

scenario_fact "holder_build_url" "$holder_url"
scenario_fact "holder_result" "$holder_result"
scenario_fact "skip_build_url" "$skip_url"
scenario_fact "skip_result" "$skip_result"
scenario_fact "skip_duration_seconds" "$skip_duration"

scenario_finish
