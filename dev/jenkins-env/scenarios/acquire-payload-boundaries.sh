#!/usr/bin/env bash
set -euo pipefail

# B01: the edges of POST /acquire.
#
# Every other scenario reaches the API through lock(), which only ever sends well-formed requests.
# That leaves the entire rejection half of the contract untested: the client never sends a malformed
# body, never contradicts itself, and never posts a megabyte, so nothing checks that the server
# answers those with the right status and the right errorCode. A caller cannot act on "400" alone -
# retry, fix the pipeline, page someone - the errorCode is the actionable part, so both are asserted.
#
# The scenario also pins the cases the endpoint does NOT reject. Those are recorded as observations
# rather than failures: they are the current behaviour, not a stated contract, and pinning them here
# means a change to any of them shows up as a diff in the report instead of silently altering what a
# malformed pipeline does. See the boundary analysis for why the timeoutUnit one matters most.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "B01" "acquire-payload-boundaries" "${1:-}"

STAMP="$(scenario_stamp)"
RES="b01-res-$STAMP"
RESPONSE="$SCENARIO_DIR/response.json"
BODY_FILE="$SCENARIO_DIR/body.json"

scenario_cleanup_hook drop_resources "b" "$RES"

scenario_step "Expose one resource on B to aim the requests at"
configure_remote_server "$CONTROLLER_B_URL" "$RES" "remote-enabled" "authenticated"
verify_remote_server_config "$CONTROLLER_B_URL" "$RES" "authenticated"
TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-b01-token")"

# Sends a request and leaves the outcome in LAST_CODE / LAST_STATE / LAST_LOCK_ID.
# Globals rather than a printed value on purpose: a command substitution would run this in a
# subshell, and the lock id needed for cleanup would not survive it.
LAST_CODE=""
LAST_STATE=""
LAST_LOCK_ID=""

send() {
  LAST_CODE="$(api_acquire "b" "$TOKEN_B" "$1" "$RESPONSE")" || LAST_CODE="curl-error"
  LAST_LOCK_ID="$(api_field "$RESPONSE" lockId)" || LAST_LOCK_ID=""
  LAST_STATE="$(api_field "$RESPONSE" state)" || LAST_STATE=""
}

# A case that unexpectedly succeeds must not leave the resource held for the next one.
release_last() {
  if [[ -n "$LAST_LOCK_ID" ]]; then
    api_release "b" "$TOKEN_B" "$LAST_LOCK_ID" /dev/null >/dev/null || true
    LAST_LOCK_ID=""
  fi
}

# reject <label> <status> <errorCode> <body>
reject() {
  local label="$1" status="$2" code="$3" body="$4"
  send "$body"
  scenario_check_api "$label" "$status" "$LAST_CODE" "$code" "$RESPONSE"
  release_last
}

scenario_step "Malformed and structurally wrong bodies"
reject "Body that is not JSON"            400 INVALID_JSON          '{not json'
reject "Body missing lockRequest"         400 MISSING_LOCK_REQUEST  '{}'
reject "lockRequest that is not an object" 400 MISSING_LOCK_REQUEST '{"lockRequest":"x"}'

scenario_step "Requests that contradict lock() semantics"
# These are rejected by the same validator a local lock() uses, so the wording a pipeline author
# sees is the wording they would have seen locally.
reject "No target at all"                 400 INVALID_REQUEST "{\"lockRequest\":{}}"
reject "resource and label together"      400 INVALID_REQUEST "{\"lockRequest\":{\"resource\":\"$RES\",\"label\":\"anything\"}}"
reject "Unknown resourceSelectStrategy"   400 INVALID_REQUEST "{\"lockRequest\":{\"resource\":\"$RES\",\"resourceSelectStrategy\":\"NOPE\"}}"
reject "priority with inversePrecedence"  400 INVALID_REQUEST "{\"lockRequest\":{\"resource\":\"$RES\",\"priority\":5,\"inversePrecedence\":true}}"
reject "extra entry naming neither resource nor label" 400 INVALID_EXTRA "{\"lockRequest\":{\"resource\":\"$RES\",\"extra\":[{}]}}"

scenario_step "heartbeatIntervalSeconds, the one field with its own validation"
reject "heartbeatIntervalSeconds = 0"     400 INVALID_HEARTBEAT_INTERVAL "{\"lockRequest\":{\"resource\":\"$RES\"},\"heartbeatIntervalSeconds\":0}"
reject "heartbeatIntervalSeconds < 0"     400 INVALID_HEARTBEAT_INTERVAL "{\"lockRequest\":{\"resource\":\"$RES\"},\"heartbeatIntervalSeconds\":-1}"
reject "heartbeatIntervalSeconds not a number" 400 INVALID_HEARTBEAT_INTERVAL "{\"lockRequest\":{\"resource\":\"$RES\"},\"heartbeatIntervalSeconds\":\"abc\"}"

scenario_step "Targets this client may not have"
# Unknown and unexposed answer identically on purpose - see S17.
reject "Resource that does not exist"     404 UNKNOWN_RESOURCE '{"lockRequest":{"resource":"b01-no-such-resource"}}'
reject "Label that matches nothing"       404 UNKNOWN_LABEL     '{"lockRequest":{"label":"b01-no-such-label"}}'

scenario_step "The body size cap (${RLR_MAX_BODY_CHARS} characters)"
# Both sides of the boundary. Only the pair is meaningful: a server that rejected everything would
# pass the over-cap check on its own.
build_padded_body() {
  local total="$1"
  python3 - "$RES" "$total" "$BODY_FILE" <<'PY'
import json, sys
resource, total, path = sys.argv[1], int(sys.argv[2]), sys.argv[3]
# Pad through `reason`, a free-text field, until the whole body is exactly `total` characters.
skeleton = json.dumps({"lockRequest": {"resource": resource, "reason": ""}}, separators=(",", ":"))
pad = total - len(skeleton)
body = json.dumps(
    {"lockRequest": {"resource": resource, "reason": "x" * pad}}, separators=(",", ":")
)
assert len(body) == total, (len(body), total)
with open(path, "w") as fh:
    fh.write(body)
PY
}

build_padded_body "$RLR_MAX_BODY_CHARS"
body_code="$(api_acquire_file "b" "$TOKEN_B" "$BODY_FILE" "$RESPONSE")"
LAST_LOCK_ID="$(api_field "$RESPONSE" lockId)" || LAST_LOCK_ID=""
scenario_check "A body exactly at the cap is accepted" "POST /acquire with ${RLR_MAX_BODY_CHARS} chars" "202" "$body_code"
release_last

build_padded_body $((RLR_MAX_BODY_CHARS + 1))
body_code="$(api_acquire_file "b" "$TOKEN_B" "$BODY_FILE" "$RESPONSE")"
LAST_LOCK_ID="$(api_field "$RESPONSE" lockId)" || LAST_LOCK_ID=""
scenario_check_api "A body one character over is refused" 413 "$body_code" PAYLOAD_TOO_LARGE "$RESPONSE"
release_last
rm -f "$BODY_FILE"

scenario_step "Values that are accepted rather than rejected (pinned, not asserted)"
# quantity is read with a default of 0, and for a label 0 means "every match". So a quantity the
# server cannot parse does not fail the request - it widens it from "one machine" to "the pool".
send "{\"lockRequest\":{\"label\":\"remote-enabled\",\"quantity\":\"abc\"}}"
scenario_observe "quantity that is not a number" "POST /acquire label + quantity:\"abc\"" "$LAST_CODE/$LAST_STATE (not rejected; reads as 0 = all matching)"
release_last

send "{\"lockRequest\":{\"label\":\"remote-enabled\",\"quantity\":-1}}"
scenario_observe "Negative quantity" "POST /acquire label + quantity:-1" "$LAST_CODE/$LAST_STATE (not rejected)"
release_last

# The one worth reading twice. An unknown resourceSelectStrategy is a 400 above; an unknown
# timeoutUnit is accepted here, and RemoteQueueEntry turns the unparseable unit into deadline 0 -
# which means "no timeout". A plausible typo (MINUTE for MINUTES) therefore converts a bounded wait
# into an unbounded one, silently.
send "{\"lockRequest\":{\"resource\":\"$RES\",\"timeoutForAllocateResource\":5,\"timeoutUnit\":\"MINUTE\"}}"
scenario_observe "timeoutUnit that is not a TimeUnit" "POST /acquire timeoutUnit:\"MINUTE\"" \
  "$LAST_CODE/$LAST_STATE (not rejected; unparseable unit disables the timeout)"
release_last

send "{\"lockRequest\":{\"resource\":\"$RES\",\"timeoutForAllocateResource\":-5,\"timeoutUnit\":\"SECONDS\"}}"
scenario_observe "Negative allocate timeout" "POST /acquire timeoutForAllocateResource:-5" \
  "$LAST_CODE/$LAST_STATE (not rejected; <= 0 means wait forever, as local lock() does)"
release_last

scenario_step "Check no rejected request left anything behind"
scenario_check_resource_free "The target resource is free" "b" "$RES"
scenario_check "No resource was created for the unknown name" "Groovy fromName on B" \
  "false" "$(resource_field "$(resource_state "b" "b01-no-such-resource")" EXISTS)"

scenario_fact "max_body_chars" "$RLR_MAX_BODY_CHARS"
scenario_fact "resource" "$RES"

scenario_finish
