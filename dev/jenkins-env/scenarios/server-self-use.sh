#!/usr/bin/env bash
set -euo pipefail

# S03: the server uses its own resource locally while a remote client wants it.
#
# Local and remote are two different code paths onto the same resource, and this is the scenario
# that proves they share one exclusion. The remote waiter must not get in until the local build lets
# go - which, again, only the elapsed time can show.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "S03" "server-self-use" "${1:-}"

RESOURCE_NAME="s03-shared-$(scenario_stamp)"
LOCAL_HOLD_SECONDS=30
MIN_WAIT_SECONDS=20

scenario_step "Expose the resource on B and link A to it"
setup_remote_pair "s03" "a" "b" "$RESOURCE_NAME"

LOCAL_SCRIPT="$(cat <<EOF
pipeline {
  agent any
  stages {
    stage("LocalHold") {
      steps {
        lock(resource: "${RESOURCE_NAME}") {
          echo "LOCAL_HOLDER_ACQUIRED"
          sleep time: ${LOCAL_HOLD_SECONDS}, unit: "SECONDS"
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

scenario_step "Take the resource locally on B, then ask for it remotely from A"
local_url="$(trigger_and_resolve_build_url "$CONTROLLER_B_URL" "s03-local-holder" 120)"
wait_for_console_contains "$local_url" "LOCAL_HOLDER_ACQUIRED" 120 ||
  scenario_require_ok "Local holder acquires first" "ConsoleText" "LOCAL_HOLDER_ACQUIRED never appeared"

remote_start="$(date +%s)"
remote_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s03-remote-waiter" 120)"
local_result="$(wait_for_build_result "$local_url" 900)"
remote_result="$(wait_for_build_result "$remote_url" 900)"
remote_duration="$(($(date +%s) - remote_start))"

save_console_log "$local_url" "$SCENARIO_DIR/local-holder-console.txt"
save_console_log "$remote_url" "$SCENARIO_DIR/remote-waiter-console.txt"
scenario_artifact "local-holder-console" "$SCENARIO_DIR/local-holder-console.txt"
scenario_artifact "remote-waiter-console" "$SCENARIO_DIR/remote-waiter-console.txt"

scenario_check "Local holder result" "Build API" "SUCCESS" "$local_result"
scenario_check "Remote waiter result" "Build API" "SUCCESS" "$remote_result"
scenario_check_ge "Remote waiter excluded by the local hold" "$remote_duration" "$MIN_WAIT_SECONDS" "elapsed seconds"
scenario_check_contains "Remote waiter entered the body" "$SCENARIO_DIR/remote-waiter-console.txt" "REMOTE_WAITER_ACQUIRED"

scenario_fact "local_build_url" "$local_url"
scenario_fact "local_result" "$local_result"
scenario_fact "remote_build_url" "$remote_url"
scenario_fact "remote_result" "$remote_result"
scenario_fact "remote_wait_seconds" "$remote_duration"

scenario_finish
