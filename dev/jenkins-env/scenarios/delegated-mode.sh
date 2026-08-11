#!/usr/bin/env bash
set -euo pipefail

# S09: forcedServerId sends a lock() with no serverId to a remote, transparently.
#
# The point of delegated mode is that existing pipelines need no edit: the same `lock(resource: 'x')`
# goes remote when the controller is configured to delegate, and goes back to being an ordinary local
# lock when it is not. Both halves are asserted, and the second one matters most - a controller that
# stays in delegated mode after the setting is cleared would route every local lock off-box.
#
# forcedServerId is controller-wide state, so clearing it is a cleanup hook rather than a final line:
# left set by a scenario that died here, it would silently redirect every scenario that follows.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "S09" "delegated-mode" "${1:-}"

STAMP="$(scenario_stamp)"
B_RESOURCE="s09-res-b-$STAMP"
A_LOCAL_RESOURCE="s09-local-a-$STAMP"

scenario_cleanup_hook configure_forced_server_id_empty "$CONTROLLER_A_URL"

scenario_step "Expose a resource on B, add a local one on A, and link A to B"
setup_remote_pair "s09" "a" "b" "$B_RESOURCE"
configure_local_resource "$CONTROLLER_A_URL" "$A_LOCAL_RESOURCE"

scenario_step "Set forcedServerId=b on A and run a lock() that names no serverId"
configure_forced_server_id "$CONTROLLER_A_URL" "b"

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
delegated_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s09-delegated" 120)"
delegated_result="$(wait_for_build_result "$delegated_url" 600)"
save_console_log "$delegated_url" "$SCENARIO_DIR/delegated-console.txt"
scenario_artifact "delegated console" "$SCENARIO_DIR/delegated-console.txt"

scenario_check "Delegated build result" "Build API" "SUCCESS" "$delegated_result"
scenario_check_contains "Body ran" "$SCENARIO_DIR/delegated-console.txt" "DELEGATED_ACQUIRED"
scenario_check_contains "Went over the remote path" "$SCENARIO_DIR/delegated-console.txt" "Remote lock acquired on"
scenario_check_contains "Delegated to the configured server" "$SCENARIO_DIR/delegated-console.txt" "serverId=b"

scenario_step "Clear forcedServerId and run a lock() on a local resource"
configure_forced_server_id_empty "$CONTROLLER_A_URL"

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
fallback_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s09-local-fallback" 120)"
fallback_result="$(wait_for_build_result "$fallback_url" 600)"
save_console_log "$fallback_url" "$SCENARIO_DIR/fallback-console.txt"
scenario_artifact "fallback console" "$SCENARIO_DIR/fallback-console.txt"

scenario_check "Fallback build result" "Build API" "SUCCESS" "$fallback_result"
scenario_check_contains "Local body ran" "$SCENARIO_DIR/fallback-console.txt" "LOCAL_ACQUIRED"
scenario_check_absent "Delegation stopped with the setting" "$SCENARIO_DIR/fallback-console.txt" "Remote lock acquired on"

scenario_check_resource_free "Delegated resource released on B" "b" "$B_RESOURCE"
scenario_check_resource_free "Local resource released on A" "a" "$A_LOCAL_RESOURCE"

scenario_fact "delegated_build_url" "$delegated_url"
scenario_fact "delegated_result" "$delegated_result"
scenario_fact "fallback_build_url" "$fallback_url"
scenario_fact "fallback_result" "$fallback_result"

scenario_finish
