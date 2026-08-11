#!/usr/bin/env bash
set -euo pipefail

# B02: what heartbeat, release and poll do to a lease that is not in the state they expect.
#
# A well-behaved client walks acquire -> heartbeat -> release once, in order, and every other
# scenario only exercises that walk. Real clients do not: a build is aborted between the acquire and
# the release, a retry sends the release twice, a resumed session heartbeats a lease that ended
# while it was away. Each of those is a call against a lease in the wrong state, and the answer has
# to be one the client can act on.
#
# The temporal half is the terminal-record TTL. A released or failed record stays readable for
# RLR_TERMINAL_TTL_S so a client polling just after the end learns what happened; past that it is
# gone and the answer becomes a 404. Both sides of that boundary are checked, because a TTL that
# only ever gets tested from one side is not a TTL - it is a constant nobody depends on.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "B02" "lease-lifecycle-edges" "${1:-}"

STAMP="$(scenario_stamp)"
RES="b02-res-$STAMP"
BUSY="b02-busy-$STAMP"
RESPONSE="$SCENARIO_DIR/response.json"
UNKNOWN_ID="b02-no-such-lock-id"

scenario_cleanup_hook drop_resources "b" "$RES" "$BUSY"

scenario_step "Expose two resources on B"
configure_remote_server "$CONTROLLER_B_URL" "$RES" "remote-enabled" "authenticated"
verify_remote_server_config "$CONTROLLER_B_URL" "$RES" "authenticated"
expose_resource "b" "$BUSY"
TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-b02-token")"

scenario_step "Calls against a lease id that never existed"
code="$(api_heartbeat "b" "$TOKEN_B" "$UNKNOWN_ID" "$RESPONSE")"
scenario_check_api "Heartbeat on an unknown lease" 410 "$code" LOCK_NOT_FOUND "$RESPONSE"

code="$(api_poll "b" "$TOKEN_B" "$UNKNOWN_ID" "$RESPONSE")"
scenario_check_api "Poll of an unknown lease" 404 "$code" LOCK_NOT_FOUND "$RESPONSE"

# Release is deliberately the odd one out: it is idempotent, so "release something that is not
# there" is a success, not an error. A client retrying a release it is no longer sure it sent must
# not be told it failed.
code="$(api_release "b" "$TOKEN_B" "$UNKNOWN_ID" "$RESPONSE")"
scenario_check "Release of an unknown lease is a no-op" "POST /lease/{id}/release" "204" "$code"

scenario_step "Acquire a lease, then act on it after it has ended"
code="$(api_acquire "b" "$TOKEN_B" "{\"lockRequest\":{\"resource\":\"$RES\"}}" "$RESPONSE")"
lock_id="$(api_field "$RESPONSE" lockId)"
scenario_require "Lease acquired" "POST /acquire" "202/ACQUIRED" "$code/$(api_field "$RESPONSE" state)"

code="$(api_heartbeat "b" "$TOKEN_B" "$lock_id" "$RESPONSE")"
scenario_check "Heartbeat on a live lease" "POST /lease/{id}/heartbeat" "204" "$code"

code="$(api_release "b" "$TOKEN_B" "$lock_id" "$RESPONSE")"
scenario_check "Release of a live lease" "POST /lease/{id}/release" "204" "$code"
scenario_check_resource_free "The resource is free again" "b" "$RES"

code="$(api_release "b" "$TOKEN_B" "$lock_id" "$RESPONSE")"
scenario_check "Releasing twice is still a no-op" "POST /lease/{id}/release (repeat)" "204" "$code"

code="$(api_heartbeat "b" "$TOKEN_B" "$lock_id" "$RESPONSE")"
scenario_check_api "Heartbeat after release is refused" 410 "$code" LOCK_NOT_FOUND "$RESPONSE"

scenario_step "A released record stays readable inside the ${RLR_TERMINAL_TTL_S}s terminal TTL"
code="$(api_poll "b" "$TOKEN_B" "$lock_id" "$RESPONSE")"
state="$(api_field "$RESPONSE" state)"
error_code="$(api_field "$RESPONSE" errorCode)"
scenario_check "A just-released lease still answers" "GET /acquire/{id}" "200" "$code"
# There is no RELEASED state - release marks the record terminal and puts RELEASED in errorCode.
# A client that reads only the state sees FAILED, so the pair is what has to be right.
scenario_check "It reports how it ended, not that it vanished" "GET /acquire/{id} state/errorCode" \
  "FAILED/RELEASED" "$state/$error_code"

scenario_step "Heartbeat on a lease that is queued rather than held"
# heartbeat renews a lease; a request still waiting for one has nothing to renew, and must be told
# so rather than being quietly accepted.
code="$(api_acquire "b" "$TOKEN_B" "{\"lockRequest\":{\"resource\":\"$BUSY\"}}" "$RESPONSE")"
holder_id="$(api_field "$RESPONSE" lockId)"
scenario_require "Holder lease taken" "POST /acquire" "202/ACQUIRED" "$code/$(api_field "$RESPONSE" state)"

code="$(api_acquire "b" "$TOKEN_B" "{\"lockRequest\":{\"resource\":\"$BUSY\"}}" "$RESPONSE")"
queued_id="$(api_field "$RESPONSE" lockId)"
scenario_check "A second request for a held resource queues" "POST /acquire" \
  "202/QUEUED" "$code/$(api_field "$RESPONSE" state)"

code="$(api_heartbeat "b" "$TOKEN_B" "$queued_id" "$RESPONSE")"
scenario_check_api "Heartbeat on a queued request is refused" 410 "$code" LOCK_NOT_FOUND "$RESPONSE"

# Releasing a queued request has to withdraw it from the queue, not just mark it - otherwise the
# resource is eventually handed to a client that stopped waiting for it.
code="$(api_release "b" "$TOKEN_B" "$queued_id" "$RESPONSE")"
scenario_check "A queued request can be withdrawn" "POST /lease/{id}/release" "204" "$code"
api_release "b" "$TOKEN_B" "$holder_id" "$RESPONSE" >/dev/null
sleep 5
scenario_check_resource_free "The withdrawn request did not take the resource" "b" "$BUSY"
scenario_check "The withdrawn request stays withdrawn" "RemoteLockManager.find state" \
  "FAILED" "$(remote_record_state "b" "$queued_id")"

scenario_step "Past the TTL the record is gone (waiting out ${RLR_TERMINAL_TTL_S}s)"
# The sweep runs every second, so shortly past the threshold is enough; the margin covers the sweep
# landing just before the deadline rather than just after.
remaining="$(rlr_past "$RLR_TERMINAL_TTL_S")"
sleep "$remaining"

code="$(api_poll "b" "$TOKEN_B" "$lock_id" "$RESPONSE")"
scenario_check_api "The expired record is no longer readable" 404 "$code" LOCK_NOT_FOUND "$RESPONSE"
scenario_check "The record is gone from the manager" "RemoteLockManager.find" \
  "GONE" "$(remote_record_state "b" "$lock_id")"

scenario_fact "terminal_ttl_seconds" "$RLR_TERMINAL_TTL_S"
scenario_fact "released_lock_id" "$lock_id"
scenario_fact "withdrawn_lock_id" "$queued_id"

scenario_finish
