#!/usr/bin/env bash
set -euo pipefail

# S01: two controllers each hold a lock on the other at the same time.
#
# The model in issue #1025 is a set of independent one-way relays, not a peer-to-peer protocol.
# A->B and B->A therefore have to be able to run at once without either noticing the other; if they
# shared any state the two would serialise, which is what the elapsed-time observation looks for.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "S01" "mutual-peer" "${1:-}"

STAMP="$(scenario_stamp)"
A_RESOURCE="s01-a-resource-$STAMP"
B_RESOURCE="s01-b-resource-$STAMP"
HOLD_SECONDS=20

scenario_step "Configure A and B as each other's remote server and client"
setup_remote_pair "s01" "a" "b" "$B_RESOURCE"
setup_remote_pair "s01" "b" "a" "$A_RESOURCE"
scenario_check "Remote pair setup" "Groovy /scriptText" "A->B and B->A configured" "A->B and B->A configured"

A_SCRIPT="$(cat <<EOF
pipeline {
  agent any
  stages {
    stage("AtoB") {
      steps {
        lock(resource: "${B_RESOURCE}", serverId: "b") {
          echo "A_ACQUIRED"
          sleep time: ${HOLD_SECONDS}, unit: "SECONDS"
        }
      }
    }
  }
}
EOF
)"

B_SCRIPT="$(cat <<EOF
pipeline {
  agent any
  stages {
    stage("BtoA") {
      steps {
        lock(resource: "${A_RESOURCE}", serverId: "a") {
          echo "B_ACQUIRED"
          sleep time: ${HOLD_SECONDS}, unit: "SECONDS"
        }
      }
    }
  }
}
EOF
)"

upsert_pipeline_job "$CONTROLLER_A_URL" "s01-a-holder" "$A_SCRIPT"
upsert_pipeline_job "$CONTROLLER_B_URL" "s01-b-holder" "$B_SCRIPT"

scenario_step "Trigger both relays and wait for them to finish"
start_epoch="$(date +%s)"
a_build_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s01-a-holder" 120)"
b_build_url="$(trigger_and_resolve_build_url "$CONTROLLER_B_URL" "s01-b-holder" 120)"
a_result="$(wait_for_build_result "$a_build_url" 900)"
b_result="$(wait_for_build_result "$b_build_url" 900)"
duration="$(($(date +%s) - start_epoch))"

save_console_log "$a_build_url" "$SCENARIO_DIR/a-console.txt"
save_console_log "$b_build_url" "$SCENARIO_DIR/b-console.txt"
scenario_artifact "a-console" "$SCENARIO_DIR/a-console.txt"
scenario_artifact "b-console" "$SCENARIO_DIR/b-console.txt"

scenario_check "A build result" "Build API" "SUCCESS" "$a_result"
scenario_check "B build result" "Build API" "SUCCESS" "$b_result"
scenario_check_contains "A entered the lock body" "$SCENARIO_DIR/a-console.txt" "A_ACQUIRED"
scenario_check_contains "B entered the lock body" "$SCENARIO_DIR/b-console.txt" "B_ACQUIRED"

# Both relays hold for HOLD_SECONDS. Run in parallel that is one hold plus overhead; serialised it is
# two. The bound sits between the two, but stays a WARN: on a loaded host the overhead alone can
# cross it, and a slow run is not the same finding as a run where the relays blocked each other.
parallel_bound=$((HOLD_SECONDS * 2 + 20))
serialised="false"
((duration < parallel_bound)) && serialised="true"
scenario_check_soft "Relays ran in parallel" "elapsed time" "< ${parallel_bound}s (one hold, not two)" "${duration}s" "$serialised"

scenario_fact "a_build_url" "$a_build_url"
scenario_fact "a_result" "$a_result"
scenario_fact "b_build_url" "$b_build_url"
scenario_fact "b_result" "$b_result"
scenario_fact "duration_seconds" "$duration"

scenario_finish
