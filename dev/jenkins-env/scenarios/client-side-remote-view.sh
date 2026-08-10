#!/usr/bin/env bash
set -euo pipefail

# S20 (P1M2M3): the Known limitation of #1055 — a controller that acquires locks elsewhere had
# nowhere to show it. While A holds a lock on B, A's own lockable resources page must list it, and
# once the lock is released the entry must go away rather than linger.
#
# The page is asserted through stable markers only (the tab's data attribute, the resource name, the
# state word), not layout or CSS, so a restyle does not break this scenario.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

RESULTS_DIR="${1:-}"
if [[ -z "$RESULTS_DIR" ]]; then
  err "Results directory argument is required"
  exit 2
fi

SCENARIO="client-side-remote-view"
SCENARIO_ID="S20"
SCENARIO_DIR="$RESULTS_DIR/$SCENARIO"
mkdir -p "$SCENARIO_DIR"

TS="$(date +%s)"
RESOURCE="s20-board-${TS}"
CREDENTIALS_ID="s20-a-for-b"
JOB="s20-hold"
DETAIL_FILE="$SCENARIO_DIR/scenario-details.md"

fetch_lr_page() {
  local out="$1"
  curl -sS -u "admin:admin" -o "$out" "${CONTROLLER_A_URL}/lockable-resources/"
}

# --- Setup B (server) and A (client) ---
configure_remote_server "$CONTROLLER_B_URL" "$RESOURCE" "remote-enabled" "authenticated"
verify_remote_server_config "$CONTROLLER_B_URL" "$RESOURCE" "authenticated"

TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-s20-b-token")"
upsert_username_password_credential "$CONTROLLER_A_URL" "$CREDENTIALS_ID" "admin" "$TOKEN_B"
configure_remote_client_for_server "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "$CREDENTIALS_ID"

# --- A holds the remote lock for a while, so the page can be inspected mid-hold ---
PIPELINE_SCRIPT="$(cat <<EOF
node {
  lock(resource: '$RESOURCE', serverId: 'b') {
    echo "S20_HOLDING"
    sleep 45
  }
  echo "S20_RELEASED"
}
EOF
)"

upsert_pipeline_job "$CONTROLLER_A_URL" "$JOB" "$PIPELINE_SCRIPT"
build_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "$JOB" 120)"
wait_for_console_contains "$build_url" "S20_HOLDING" 180

fetch_lr_page "$SCENARIO_DIR/page-holding.html"

# --- CP01: the page offers the Remote tab at all (it is hidden without a remote relation) ---
grep -Fq 'data-lr-tab="remote"' "$SCENARIO_DIR/page-holding.html" \
  || { err "S20 CP01 FAIL: the Remote tab is not present on the client page"; exit 1; }

# --- CP02: the held lock is listed, naming the server and the resource ---
grep -Fq "$RESOURCE" "$SCENARIO_DIR/page-holding.html" \
  || { err "S20 CP02 FAIL: the held remote lock is not listed on the client page"; exit 1; }
grep -Fq "ACQUIRED" "$SCENARIO_DIR/page-holding.html" \
  || { err "S20 CP02 FAIL: the held remote lock is not shown as ACQUIRED"; exit 1; }

# --- CP03: the page is honest about what it is showing ---
grep -Fq "source of truth" "$SCENARIO_DIR/page-holding.html" \
  || { err "S20 CP03 FAIL: the view does not say it is a client-side observation"; exit 1; }

# --- CP04: after the lock is released, the entry is gone ---
result="$(wait_for_build_result "$build_url" 300)"
save_console_log "$build_url" "$SCENARIO_DIR/console.txt"
[[ "$result" == "SUCCESS" ]] \
  || { err "S20 CP04 FAIL: the holding build did not succeed (result=$result)"; exit 1; }

fetch_lr_page "$SCENARIO_DIR/page-released.html"
if grep -Fq "$RESOURCE" "$SCENARIO_DIR/page-released.html"; then
  err "S20 CP04 FAIL: the released remote lock is still listed on the client page"
  exit 1
fi

cat >"$SCENARIO_DIR/summary.txt" <<EOF
build_url=$build_url
result=$result
resource=$RESOURCE
page_while_holding=$SCENARIO_DIR/page-holding.html
page_after_release=$SCENARIO_DIR/page-released.html
EOF

cat >"$DETAIL_FILE" <<EOF
### ${SCENARIO_ID}: ${SCENARIO}

#### Summary

- build result: $result
- remote resource held during the check: $RESOURCE

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (the client page offers a Remote tab) |
| CP02 | PASS (the held lock is listed as ACQUIRED, naming the resource) |
| CP03 | PASS (the view states that the remote is the source of truth) |
| CP04 | PASS (the entry disappears once the lock is released) |

#### Artifacts

- page while holding: $SCENARIO_DIR/page-holding.html
- page after release: $SCENARIO_DIR/page-released.html
- console: $SCENARIO_DIR/console.txt
EOF

log "client-side-remote-view: completed"
