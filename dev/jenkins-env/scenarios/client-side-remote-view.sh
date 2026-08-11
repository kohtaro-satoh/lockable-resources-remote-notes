#!/usr/bin/env bash
set -euo pipefail

# S20: the client's lockable resources page shows what this controller holds remotely.
#
# The lockable resources page answers "what is this controller doing with locks right now?" - and
# before this, it answered it only for local resources, so a build holding a board on another
# controller was invisible here. The entry has to appear while the lock is held and disappear when
# it is released; an entry that outlives its lock is worse than none, because it reads as a lock
# nobody can find.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "S20" "client-side-remote-view" "${1:-}"

RESOURCE="s20-board-$(scenario_stamp)"
JOB="s20-hold"
HOLD_SECONDS=45

fetch_lr_page() {
  curl -sS -u "$JENKINS_USER:$JENKINS_PASSWORD" -o "$1" "${CONTROLLER_A_URL}/lockable-resources/"
}

scenario_step "Expose the resource on B and link A to it"
setup_remote_pair "s20" "a" "b" "$RESOURCE"

PIPELINE_SCRIPT="$(cat <<EOF
node {
  lock(resource: '$RESOURCE', serverId: 'b') {
    echo "S20_HOLDING"
    sleep ${HOLD_SECONDS}
  }
  echo "S20_RELEASED"
}
EOF
)"

scenario_step "Hold the remote lock and read the client page mid-hold"
upsert_pipeline_job "$CONTROLLER_A_URL" "$JOB" "$PIPELINE_SCRIPT"
build_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "$JOB" 120)"
wait_for_console_contains "$build_url" "S20_HOLDING" 180 ||
  scenario_require_ok "Lock is held" "ConsoleText" "S20_HOLDING never appeared"

fetch_lr_page "$SCENARIO_DIR/page-holding.html"
scenario_artifact "page while holding" "$SCENARIO_DIR/page-holding.html"

# The tab is hidden when the controller has no remote relation at all, so its presence is itself
# part of the behaviour.
scenario_check_contains "The page offers a Remote tab" "$SCENARIO_DIR/page-holding.html" 'data-lr-tab="remote"'
scenario_check_contains "The held lock is listed by resource name" "$SCENARIO_DIR/page-holding.html" "$RESOURCE"
scenario_check_contains "It is shown as ACQUIRED" "$SCENARIO_DIR/page-holding.html" "ACQUIRED"
# The client's view is an observation, not authority - the page has to say so, or an operator will
# act on it as if it were the server's own state.
scenario_check_contains "The page says the remote is the source of truth" "$SCENARIO_DIR/page-holding.html" "source of truth"

scenario_step "Let the lock go and read the page again"
result="$(wait_for_build_result "$build_url" 300)"
save_console_log "$build_url" "$SCENARIO_DIR/console.txt"
scenario_artifact "console" "$SCENARIO_DIR/console.txt"
scenario_check "Holding build result" "Build API" "SUCCESS" "$result"

fetch_lr_page "$SCENARIO_DIR/page-released.html"
scenario_artifact "page after release" "$SCENARIO_DIR/page-released.html"
scenario_check_absent "The entry is gone once released" "$SCENARIO_DIR/page-released.html" "$RESOURCE"

scenario_check_resource_free "Resource released on B" "b" "$RESOURCE"

scenario_fact "build_url" "$build_url"
scenario_fact "result" "$result"
scenario_fact "resource" "$RESOURCE"

scenario_finish
