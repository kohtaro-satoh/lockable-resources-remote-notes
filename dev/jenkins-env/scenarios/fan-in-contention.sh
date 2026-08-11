#!/usr/bin/env bash
set -euo pipefail

# S02: two clients want the same resource on one server.
#
# The interesting part is not that both eventually succeed - it is that the second one waits. A
# waiter that returns immediately would mean the server handed out the resource twice, which no
# console marker on its own would reveal, so the elapsed time of the waiter is the real assertion.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "S02" "fan-in-contention" "${1:-}"

RESOURCE_NAME="s02-shared-$(scenario_stamp)"
HOLD_SECONDS=25
# The waiter cannot get in before the holder lets go. Allow the holder's acquire and the waiter's
# own trigger latency, and assert on the remainder.
MIN_WAIT_SECONDS=15

scenario_step "Expose the resource on B and link A and C to it"
setup_remote_pair "s02" "a" "b" "$RESOURCE_NAME"
setup_remote_pair "s02" "c" "b" "$RESOURCE_NAME"
scenario_check "Remote setup" "Groovy /scriptText" "B exposed, A and C linked" "B exposed, A and C linked"

HOLDER_SCRIPT="$(cat <<EOF
pipeline {
  agent any
  stages {
    stage("Hold") {
      steps {
        lock(resource: "${RESOURCE_NAME}", serverId: "b") {
          echo "HOLDER_ACQUIRED"
          sleep time: ${HOLD_SECONDS}, unit: "SECONDS"
        }
      }
    }
  }
}
EOF
)"

WAITER_SCRIPT="$(cat <<EOF
pipeline {
  agent any
  stages {
    stage("Wait") {
      steps {
        lock(resource: "${RESOURCE_NAME}", serverId: "b") {
          echo "WAITER_ACQUIRED"
          sleep time: 5, unit: "SECONDS"
        }
      }
    }
  }
}
EOF
)"

upsert_pipeline_job "$CONTROLLER_A_URL" "s02-holder" "$HOLDER_SCRIPT"
upsert_pipeline_job "$CONTROLLER_C_URL" "s02-waiter" "$WAITER_SCRIPT"

scenario_step "Start the holder, then the waiter while the holder still has it"
holder_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s02-holder" 120)"
wait_for_console_contains "$holder_url" "HOLDER_ACQUIRED" 120 ||
  scenario_require_ok "Holder acquires first" "ConsoleText" "HOLDER_ACQUIRED never appeared"

waiter_start="$(date +%s)"
waiter_url="$(trigger_and_resolve_build_url "$CONTROLLER_C_URL" "s02-waiter" 120)"
holder_result="$(wait_for_build_result "$holder_url" 900)"
waiter_result="$(wait_for_build_result "$waiter_url" 900)"
waiter_duration="$(($(date +%s) - waiter_start))"

save_console_log "$holder_url" "$SCENARIO_DIR/holder-console.txt"
save_console_log "$waiter_url" "$SCENARIO_DIR/waiter-console.txt"
scenario_artifact "holder-console" "$SCENARIO_DIR/holder-console.txt"
scenario_artifact "waiter-console" "$SCENARIO_DIR/waiter-console.txt"

scenario_check "Holder result" "Build API" "SUCCESS" "$holder_result"
scenario_check "Waiter result" "Build API" "SUCCESS" "$waiter_result"
scenario_check_ge "Waiter queued behind the holder" "$waiter_duration" "$MIN_WAIT_SECONDS" "elapsed seconds"
scenario_check_contains "Waiter entered the body after the wait" "$SCENARIO_DIR/waiter-console.txt" "WAITER_ACQUIRED"

scenario_fact "holder_build_url" "$holder_url"
scenario_fact "holder_result" "$holder_result"
scenario_fact "waiter_build_url" "$waiter_url"
scenario_fact "waiter_result" "$waiter_result"
scenario_fact "waiter_duration_seconds" "$waiter_duration"

scenario_finish
