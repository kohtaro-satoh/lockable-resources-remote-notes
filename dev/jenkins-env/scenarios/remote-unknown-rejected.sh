#!/usr/bin/env bash
set -euo pipefail

# S17: asking for something the client may not have is refused at once, and leaves no trace.
#
# Two failure modes are being ruled out. The first is queueing: a request for a name the server does
# not expose has no possible future, so waiting on it burns the allocate timeout for nothing. The
# second is creation - the local lock() path can create a resource on demand, and if the remote path
# inherited that, any client could populate a server's resource list by asking for names.
#
# Unknown and unexposed are answered identically, on purpose: distinguishing them would tell a
# client which names exist on a server it has no other view into.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "S17" "remote-unknown-rejected" "${1:-}"

STAMP="$(scenario_stamp)"
EXPOSED="s17-exposed-$STAMP"
UNKNOWN="s17-unknown-$STAMP"
HIDDEN="s17-hidden-$STAMP"

scenario_step "Expose one resource on B, add one that is deliberately not exposed, and link A"
setup_remote_pair "s17" "a" "b" "$EXPOSED"
configure_local_resource "$CONTROLLER_B_URL" "$HIDDEN"

run_unknown_case() {
  local case_name="$1"
  local target="$2"
  local job="s17-$case_name"
  local console="$SCENARIO_DIR/$case_name-console.txt"

  upsert_pipeline_job "$CONTROLLER_A_URL" "$job" "$(cat <<EOF
node {
  lock(resource: '$target', serverId: 'b') {
    echo "S17_BODY_SHOULD_NOT_RUN"
  }
}
EOF
)"

  local build_url result start elapsed
  start="$(date +%s)"
  build_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "$job" 120)"
  result="$(wait_for_build_result "$build_url" 300)"
  elapsed="$(($(date +%s) - start))"
  save_console_log "$build_url" "$console"
  scenario_artifact "$case_name console" "$console"

  scenario_check "$case_name: build failed" "Build API" "FAILURE" "$result"
  scenario_check_matches "$case_name: refused as 404 / UNKNOWN_RESOURCE" "$console" "HTTP 404|UNKNOWN_RESOURCE"
  scenario_check_absent "$case_name: body never ran" "$console" "S17_BODY_SHOULD_NOT_RUN"
  # Refused, not queued: a request that waited would take the allocate timeout to fail.
  scenario_check_lt "$case_name: refused immediately, not queued" "$elapsed" 60 "elapsed seconds"

  scenario_fact "${case_name}_result" "$result"
  scenario_fact "${case_name}_seconds" "$elapsed"
}

scenario_step "Ask for a resource that does not exist on the server"
run_unknown_case "unknown" "$UNKNOWN"

# Same answer for a name that does exist but is not exposed - otherwise the response is an oracle
# for what the server has.
scenario_step "Ask for a resource that exists but is not exposed"
run_unknown_case "unexposed" "$HIDDEN"

scenario_step "Check the server created nothing for either name"
unknown_state="$(resource_state "b" "$UNKNOWN")"
scenario_check "No ephemeral resource created for the unknown name" \
  "Groovy fromName on B" "false" "$(resource_field "$unknown_state" EXISTS)"
scenario_check_resource_free "The unexposed resource was left alone" "b" "$HIDDEN"

scenario_fact "unknown_resource" "$UNKNOWN"
scenario_fact "unexposed_resource" "$HIDDEN"

scenario_finish
