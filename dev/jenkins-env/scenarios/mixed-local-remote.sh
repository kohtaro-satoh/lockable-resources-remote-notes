#!/usr/bin/env bash
set -euo pipefail

# S04: one pipeline holds a local lock and a remote lock at the same time, nested.
#
# The two locks are managed by different machinery on different controllers, and the risk is that
# unwinding one disturbs the other - so what matters as much as the body running is that both
# resources are free afterwards, on both controllers.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "S04" "mixed-local-remote" "${1:-}"

STAMP="$(scenario_stamp)"
LOCAL_RESOURCE="s04-local-a-$STAMP"
REMOTE_RESOURCE="s04-remote-b-$STAMP"

scenario_step "Create a local resource on A and an exposed one on B"
configure_local_resource "$CONTROLLER_A_URL" "$LOCAL_RESOURCE"
setup_remote_pair "s04" "a" "b" "$REMOTE_RESOURCE"

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

scenario_step "Run the nested local + remote lock"
upsert_pipeline_job "$CONTROLLER_A_URL" "s04-mixed-lock" "$PIPELINE_SCRIPT"
build_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s04-mixed-lock" 120)"
result="$(wait_for_build_result "$build_url" 600)"
save_console_log "$build_url" "$SCENARIO_DIR/console.txt"
scenario_artifact "console" "$SCENARIO_DIR/console.txt"

scenario_check "Build result" "Build API" "SUCCESS" "$result"
scenario_check_contains "Innermost body ran with both locks held" "$SCENARIO_DIR/console.txt" "BOTH_ACQUIRED"

scenario_step "Check both resources were released"
scenario_check_resource_free "Local resource released on A" "a" "$LOCAL_RESOURCE"
scenario_check_resource_free "Remote resource released on B" "b" "$REMOTE_RESOURCE"

scenario_fact "build_url" "$build_url"
scenario_fact "result" "$result"
scenario_fact "local_resource" "$LOCAL_RESOURCE"
scenario_fact "remote_resource" "$REMOTE_RESOURCE"

scenario_finish
