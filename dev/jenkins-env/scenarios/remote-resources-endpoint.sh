#!/usr/bin/env bash
set -euo pipefail

# S19: GET /resources - the discovery endpoint the client page is built on.
#
# Three things have to hold at once, and only an end-to-end run can show them together:
#   * exposeLabel decides what a client may see, so an unexposed resource must not appear;
#   * the entry carries live state, which is why the client can render remote resources at all;
#   * and it must NOT carry the holder's identity. The server's admin published resources, not the
#     names of the builds using them, and this list is rendered on a controller whose viewers may
#     have no account here.
#
# The reserved resource carries a deliberately identifiable note and reserver name: if either
# appears anywhere in the response, the last of those three has been broken.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "S19" "remote-resources-endpoint" "${1:-}"

STAMP="$(scenario_stamp)"
EXPOSED="s19-exposed-$STAMP"
HIDDEN="s19-hidden-$STAMP"
BODY_FILE="$SCENARIO_DIR/resources.json"
PAUSED_FILE="$SCENARIO_DIR/resources-paused.json"

resume_acquires() {
  run_groovy_script "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
LockableResourcesManager.get().setAcceptNewAcquires(true)
println('OK')
"
}
scenario_cleanup_hook resume_acquires

scenario_step "Expose one resource on B, and add one that is deliberately not exposed"
configure_remote_server "$CONTROLLER_B_URL" "$EXPOSED" "remote-enabled" "authenticated"
verify_remote_server_config "$CONTROLLER_B_URL" "$EXPOSED" "authenticated"
configure_local_resource "$CONTROLLER_B_URL" "$HIDDEN"

scenario_step "Reserve the exposed resource, with a note and a reserver name that must not leak"
run_groovy_script_checked "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager

def lrm = LockableResourcesManager.get()
def r = lrm.fromName('${EXPOSED}')
r.setNote('S19_SECRET_NOTE')
lrm.reserve([r], 's19-operator')
println('RESERVED=' + (r.getReservedBy() != null))
" "RESERVED=true" >/dev/null

TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-s19-b-token")"

scenario_step "Fetch the catalogue"
http_code="$(api_resources "b" "$TOKEN_B" "$BODY_FILE")"
scenario_artifact "response" "$BODY_FILE"

scenario_require "Endpoint answers" "GET /resources" "200" "$http_code"
scenario_check_contains "The exposed resource is listed" "$BODY_FILE" "$EXPOSED"
scenario_check_absent "exposeLabel is the visibility boundary" "$BODY_FILE" "$HIDDEN"

scenario_check_contains "Entries carry live state" "$BODY_FILE" '"state"'
scenario_check_contains "A reserved resource reports RESERVED" "$BODY_FILE" '"RESERVED"'

scenario_check_absent "The note stays on the server" "$BODY_FILE" "S19_SECRET_NOTE"
scenario_check_absent "The reserver's name stays on the server" "$BODY_FILE" "s19-operator"
scenario_check_contains "The kind of holder is still reported" "$BODY_FILE" '"heldByKind"'

scenario_step "Pause acquires and check the same snapshot says so"
scenario_check_contains "Serving: acceptNewAcquires is true" "$BODY_FILE" '"acceptNewAcquires":true'

run_groovy_script_checked "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
LockableResourcesManager.get().setAcceptNewAcquires(false)
println('PAUSED=true')
" "PAUSED=true" >/dev/null

api_resources "b" "$TOKEN_B" "$PAUSED_FILE" >/dev/null
scenario_artifact "response while paused" "$PAUSED_FILE"

scenario_check_contains "Paused: acceptNewAcquires is false" "$PAUSED_FILE" '"acceptNewAcquires":false'
# State stays truthful while paused - saying "you cannot take this right now" is the page's job,
# not something the server expresses by lying about whether the resource is free.
scenario_check_contains "Resource state is unchanged by pausing" "$PAUSED_FILE" '"RESERVED"'

resume_acquires >/dev/null

scenario_fact "http_code" "$http_code"
scenario_fact "exposed_resource" "$EXPOSED"
scenario_fact "hidden_resource" "$HIDDEN"

scenario_finish
