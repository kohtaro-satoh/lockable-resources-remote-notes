#!/usr/bin/env bash
set -euo pipefail

# S11: a heartbeat outage shorter than the STALE threshold must not disturb a running job.
#
# The heartbeat renews a lease; losing one is not losing the lock. The server holds the lease until
# STALE (RLR_STALE_THRESHOLD_S), so a client that aborted its build on the first failed heartbeat
# would be throwing away work it still owns. The outage is sized from the constants rather than
# hardcoded: long enough for several heartbeats to fail, short enough to stay inside STALE.
#
# The outage is engineered by disabling the remote API on B, which makes heartbeats fail while
# leaving the container up - closer to a server-side fault than stopping the process, and it lets the
# final release succeed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "S11" "heartbeat-resilience" "${1:-}"

RES="s11-res-$(scenario_stamp)"
CONTAINER_A="lrr-jenkins-a"

# Several heartbeats must fail, but the lease must not reach STALE: it has to stay comfortably under
# RLR_STALE_THRESHOLD_S, and long enough to span at least two heartbeat intervals.
OUTAGE_SECONDS="$(rlr_inside "$RLR_STALE_THRESHOLD_S")"
((OUTAGE_SECONDS > 25)) && OUTAGE_SECONDS=25
BODY_SECONDS=$((OUTAGE_SECONDS + RLR_HEARTBEAT_INTERVAL_S + 5))

restore_remote_api() {
  run_groovy_script "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
LockableResourcesManager.get().setRemoteApiEnabled(true)
println('OK')
"
}
scenario_cleanup_hook restore_remote_api

scenario_step "Expose the resource on B and link A to it"
setup_remote_pair "s11" "a" "b" "$RES"

PIPELINE_SCRIPT="$(cat <<EOF
node {
  lock(resource: '$RES', serverId: 'b') {
    echo "S11_BODY_START"
    sleep ${BODY_SECONDS}
    echo "S11_BODY_END"
  }
}
EOF
)"

scenario_step "Start a job holding the lock for ${BODY_SECONDS}s"
upsert_pipeline_job "$CONTROLLER_A_URL" "s11-heartbeat" "$PIPELINE_SCRIPT"
build_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s11-heartbeat" 120)"
wait_for_console_contains "$build_url" "S11_BODY_START" 120 ||
  scenario_require_ok "Body starts" "ConsoleText" "S11_BODY_START never appeared"

scenario_step "Break heartbeats for ${OUTAGE_SECONDS}s (inside the ${RLR_STALE_THRESHOLD_S}s STALE threshold)"
HB_BREAK_FROM="$(date -u '+%Y-%m-%dT%H:%M:%S')"
run_groovy_script_checked "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
LockableResourcesManager.get().setRemoteApiEnabled(false)
println('OK: remote API disabled')
" "OK: remote API disabled" >/dev/null

sleep "$OUTAGE_SECONDS"

run_groovy_script_checked "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
LockableResourcesManager.get().setRemoteApiEnabled(true)
println('OK: remote API enabled')
" "OK: remote API enabled" >/dev/null

result="$(wait_for_build_result "$build_url" 600)"
save_console_log "$build_url" "$SCENARIO_DIR/console.txt"
scenario_artifact "console" "$SCENARIO_DIR/console.txt"

scenario_check "Build result" "Build API" "SUCCESS" "$result"
scenario_check_contains "Body ran to completion" "$SCENARIO_DIR/console.txt" "S11_BODY_END"

# Without this the scenario would pass vacuously: if no heartbeat actually failed, nothing about
# heartbeat resilience was exercised.
docker logs --since "$HB_BREAK_FROM" "$CONTAINER_A" 2>&1 |
  grep -F "Remote heartbeat failed (continuing job; server retains lock)" \
  >"$SCENARIO_DIR/heartbeat-warnings.txt" || true
hb_warn_count="$(wc -l <"$SCENARIO_DIR/heartbeat-warnings.txt" | tr -d ' ')"
scenario_artifact "heartbeat warnings" "$SCENARIO_DIR/heartbeat-warnings.txt"
scenario_check_ge "Heartbeats really did fail" "$hb_warn_count" 1 "docker logs on $CONTAINER_A"

scenario_check_resource_free "Resource released after the job" "b" "$RES"

scenario_fact "build_url" "$build_url"
scenario_fact "result" "$result"
scenario_fact "outage_seconds" "$OUTAGE_SECONDS"
scenario_fact "stale_threshold_seconds" "$RLR_STALE_THRESHOLD_S"
scenario_fact "heartbeat_warning_count" "$hb_warn_count"

scenario_finish
