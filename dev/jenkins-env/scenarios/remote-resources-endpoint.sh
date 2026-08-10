#!/usr/bin/env bash
set -euo pipefail

# S19 (P1M2M3): GET /resources — the discovery endpoint the client page is built on.
#
# Three things have to hold at once, and only an end-to-end run can show them together:
#   * exposeLabel decides what a client may see, so an unexposed resource must not appear;
#   * the entry carries live state, which is why the client can render remote resources at all;
#   * and it must NOT carry the holder's identity. The server's admin published resources, not the
#     names of the builds using them, and this list is rendered on a controller whose viewers may
#     have no account here.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

RESULTS_DIR="${1:-}"
if [[ -z "$RESULTS_DIR" ]]; then
  err "Results directory argument is required"
  exit 2
fi

SCENARIO="remote-resources-endpoint"
SCENARIO_ID="S19"
SCENARIO_DIR="$RESULTS_DIR/$SCENARIO"
mkdir -p "$SCENARIO_DIR"

TS="$(date +%s)"
EXPOSED="s19-exposed-${TS}"
HIDDEN="s19-hidden-${TS}"
CREDENTIALS_ID="s19-a-for-b"
DETAIL_FILE="$SCENARIO_DIR/scenario-details.md"
BODY_FILE="$SCENARIO_DIR/resources.json"

# --- Setup B: remote API + one exposed resource, plus one that is deliberately not exposed ---
configure_remote_server "$CONTROLLER_B_URL" "$EXPOSED" "remote-enabled" "authenticated"
verify_remote_server_config "$CONTROLLER_B_URL" "$EXPOSED" "authenticated"
configure_local_resource "$CONTROLLER_B_URL" "$HIDDEN"   # no exposeLabel -> invisible to clients

# A secret-looking note and reason: if either leaks into the response, the check below fails.
run_groovy_script_checked "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
def lrm = LockableResourcesManager.get()
def r = lrm.fromName('${EXPOSED}')
r.setNote('S19_SECRET_NOTE')
lrm.reserve([r], 's19-operator')
println('RESERVED=' + (r.getReservedBy() != null))
" "RESERVED=true"

TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-s19-b-token")"

# --- CP01: the endpoint answers, and lists the exposed resource ---
http_code="$(curl -sS -o "$BODY_FILE" -w '%{http_code}' \
  -u "admin:${TOKEN_B}" \
  -H 'Accept: application/json' \
  "${CONTROLLER_B_URL}/lockable-resources/remote/v1/resources/")"

[[ "$http_code" == "200" ]] \
  || { err "S19 CP01 FAIL: expected HTTP 200 from GET /resources, got $http_code"; cat "$BODY_FILE" >&2; exit 1; }

grep -Fq "$EXPOSED" "$BODY_FILE" \
  || { err "S19 CP01 FAIL: the exposed resource is missing from the response"; exit 1; }

# --- CP02: exposeLabel is the visibility boundary — the unexposed resource must not appear ---
if grep -Fq "$HIDDEN" "$BODY_FILE"; then
  err "S19 CP02 FAIL: an unexposed resource leaked into GET /resources"
  exit 1
fi

# --- CP03: live state is present (this is what makes the client page worth rendering) ---
grep -Fq '"state"' "$BODY_FILE" \
  || { err "S19 CP03 FAIL: the response carries no state"; exit 1; }
grep -Fq '"RESERVED"' "$BODY_FILE" \
  || { err "S19 CP03 FAIL: the reserved resource is not reported as RESERVED"; exit 1; }

# --- CP04: the holder's identity stays on the server ---
for secret in "S19_SECRET_NOTE" "s19-operator"; do
  if grep -Fq "$secret" "$BODY_FILE"; then
    err "S19 CP04 FAIL: '$secret' leaked into GET /resources"
    exit 1
  fi
done
grep -Fq '"heldByKind"' "$BODY_FILE" \
  || { err "S19 CP04 FAIL: the response does not say what kind of holder has it"; exit 1; }

# --- CP05: the maintenance switch travels in the same snapshot ---
grep -Fq '"acceptNewAcquires":true' "$BODY_FILE" \
  || { err "S19 CP05 FAIL: acceptNewAcquires is missing or not true while the server is serving"; exit 1; }

run_groovy_script_checked "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
LockableResourcesManager.get().setAcceptNewAcquires(false)
println('PAUSED=true')
" "PAUSED=true"

curl -sS -o "$SCENARIO_DIR/resources-paused.json" \
  -u "admin:${TOKEN_B}" -H 'Accept: application/json' \
  "${CONTROLLER_B_URL}/lockable-resources/remote/v1/resources/" >/dev/null

grep -Fq '"acceptNewAcquires":false' "$SCENARIO_DIR/resources-paused.json" \
  || { err "S19 CP05 FAIL: pausing acquires is not reflected in GET /resources"; exit 1; }

# Resource state stays truthful while paused - "you cannot take it now" is the page's job to say.
grep -Fq '"RESERVED"' "$SCENARIO_DIR/resources-paused.json" \
  || { err "S19 CP05 FAIL: resource state changed because the server was paused"; exit 1; }

run_groovy_script_checked "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
LockableResourcesManager.get().setAcceptNewAcquires(true)
println('RESUMED=true')
" "RESUMED=true"

cat >"$SCENARIO_DIR/summary.txt" <<EOF
http_code=$http_code
exposed_resource=$EXPOSED
hidden_resource=$HIDDEN
body=$BODY_FILE
EOF

cat >"$DETAIL_FILE" <<EOF
### ${SCENARIO_ID}: ${SCENARIO}

#### Summary

- GET /resources: HTTP $http_code
- exposed resource listed: $EXPOSED
- unexposed resource withheld: $HIDDEN

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (HTTP 200, exposed resource listed) |
| CP02 | PASS (unexposed resource not listed — exposeLabel is the boundary) |
| CP03 | PASS (live state present; a reserved resource reports RESERVED) |
| CP04 | PASS (no note, no reserver name; only heldByKind) |
| CP05 | PASS (acceptNewAcquires travels with it, and pausing does not alter resource state) |

#### Artifacts

- response: $BODY_FILE
- response while paused: $SCENARIO_DIR/resources-paused.json
- summary: $SCENARIO_DIR/summary.txt
EOF

log "remote-resources-endpoint: completed"
