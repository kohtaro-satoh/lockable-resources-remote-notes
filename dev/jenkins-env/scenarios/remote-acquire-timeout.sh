#!/usr/bin/env bash
set -euo pipefail

# S18: an allocate timeout longer than the terminal-record TTL still ends as a clean timeout.
#
# Regression cover for queued-expiry-poll-404. Terminal records are kept for RLR_TERMINAL_TTL_S, and
# when that retention was measured from enqueue rather than from the terminal instant, a request that
# waited longer than the TTL was evicted the moment it timed out - so the client's next poll got a
# 404 and reported "the server may have restarted" instead of "you waited and did not get it". Same
# outcome, useless diagnosis.
#
# The waiter's timeout is therefore set past RLR_TERMINAL_TTL_S deliberately: inside it, the bug is
# invisible.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "S18" "remote-acquire-timeout" "${1:-}"

RESOURCE_NAME="s18-shared-$(scenario_stamp)"
WAITER_TIMEOUT_SECONDS="$(rlr_past "$RLR_TERMINAL_TTL_S")"
# The holder must still hold when the waiter gives up, or the waiter would succeed instead - and it
# must hold well past that point, not just past it. With a small gap, "the timeout fired on time" and
# "the timeout was only noticed when the holder released" produce nearly the same elapsed time, and
# the scenario cannot tell them apart. That is exactly how it missed the defect described below.
HOLDER_HOLD_SECONDS=$((WAITER_TIMEOUT_SECONDS + 60))
# How late the failure may be before it is no longer "the timeout fired".
TIMEOUT_LATENESS_BUDGET_S=20

scenario_step "Expose the resource on B and link A to it"
setup_remote_pair "s18" "a" "b" "$RESOURCE_NAME"

LOCAL_SCRIPT="$(cat <<EOF
pipeline {
  agent any
  stages {
    stage("LocalHold") {
      steps {
        lock(resource: "${RESOURCE_NAME}") {
          echo "LOCAL_HOLDER_ACQUIRED"
          sleep time: ${HOLDER_HOLD_SECONDS}, unit: "SECONDS"
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
        lock(resource: "${RESOURCE_NAME}", serverId: "b", timeoutForAllocateResource: ${WAITER_TIMEOUT_SECONDS}, timeoutUnit: "SECONDS") {
          echo "SHOULD_NOT_RUN"
        }
      }
    }
  }
}
EOF
)"

upsert_pipeline_job "$CONTROLLER_B_URL" "s18-local-holder" "$LOCAL_SCRIPT"
upsert_pipeline_job "$CONTROLLER_A_URL" "s18-remote-waiter" "$REMOTE_SCRIPT"

scenario_step "Hold the resource locally on B for ${HOLDER_HOLD_SECONDS}s"
local_url="$(trigger_and_resolve_build_url "$CONTROLLER_B_URL" "s18-local-holder" 120)"
wait_for_console_contains "$local_url" "LOCAL_HOLDER_ACQUIRED" 120 ||
  scenario_require_ok "Local holder acquires first" "ConsoleText" "LOCAL_HOLDER_ACQUIRED never appeared"

scenario_step "Ask remotely with a ${WAITER_TIMEOUT_SECONDS}s allocate timeout (past the ${RLR_TERMINAL_TTL_S}s terminal TTL)"
waiter_start="$(date +%s)"
remote_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s18-remote-waiter" 120)"
remote_result="$(wait_for_build_result "$remote_url" 900)"
waiter_duration="$(($(date +%s) - waiter_start))"
local_result="$(wait_for_build_result "$local_url" 900)"

save_console_log "$local_url" "$SCENARIO_DIR/local-holder-console.txt"
save_console_log "$remote_url" "$SCENARIO_DIR/remote-waiter-console.txt"
scenario_artifact "local holder console" "$SCENARIO_DIR/local-holder-console.txt"
scenario_artifact "remote waiter console" "$SCENARIO_DIR/remote-waiter-console.txt"

WAITER_CONSOLE="$SCENARIO_DIR/remote-waiter-console.txt"

scenario_check "Holder kept the resource throughout" "Build API" "SUCCESS" "$local_result"
scenario_check "Waiter failed closed" "Build API" "FAILURE" "$remote_result"
scenario_check_contains "Failure is reported as a clean timeout" "$WAITER_CONSOLE" "LOCK_WAIT_TIMEOUT"
scenario_check_absent "Not misreported as a lost record" "$WAITER_CONSOLE" "server may have restarted"
scenario_check_absent "Not misreported as a communication failure" "$WAITER_CONSOLE" "Remote API communication failure"
scenario_check_absent "Body never ran" "$WAITER_CONSOLE" "SHOULD_NOT_RUN"
# A waiter that failed fast never reached the regression at all.
scenario_check_ge "Waiter genuinely waited out its allocate window" \
  "$waiter_duration" "$RLR_TERMINAL_TTL_S" "elapsed seconds"

# The timeout has to fire on its own deadline, not when something else happens to poke the queue.
#
# An allocate timeout is a promise about the longest a build will wait. A deadline that is only
# noticed during a maintenance pass triggered by something else is not that promise: it holds only
# while other traffic happens to keep the queue busy, and fails exactly when the resource is stuck -
# which is when a caller needs the bound most.
#
# The holder holds for HOLDER_HOLD_SECONDS, well past the waiter's deadline, so the two outcomes are
# far apart: firing on time is ~WAITER_TIMEOUT_SECONDS, firing on the holder's release is
# ~HOLDER_HOLD_SECONDS. That gap is the assertion. This scenario was previously blind to the
# difference - the holder released at about the deadline and the check was only ">= 120s".
lateness=$((waiter_duration - WAITER_TIMEOUT_SECONDS))
scenario_check_lt "Timeout fired on its own deadline, not on the holder's release" \
  "$lateness" $((TIMEOUT_LATENESS_BUDGET_S + 1)) \
  "seconds late against its ${WAITER_TIMEOUT_SECONDS}s deadline (holder held ${HOLDER_HOLD_SECONDS}s)"
scenario_fact "timeout_lateness_seconds" "$lateness"

scenario_check_resource_free "Resource free once the holder finished" "b" "$RESOURCE_NAME"

scenario_fact "local_result" "$local_result"
scenario_fact "remote_result" "$remote_result"
scenario_fact "waiter_allocate_timeout_seconds" "$WAITER_TIMEOUT_SECONDS"
scenario_fact "terminal_ttl_seconds" "$RLR_TERMINAL_TTL_S"
scenario_fact "waiter_wait_seconds" "$waiter_duration"

scenario_finish
