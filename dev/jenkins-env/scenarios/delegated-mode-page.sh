#!/usr/bin/env bash
set -euo pipefail

# S21 (P1M2M3): what delegated mode looks like on the page.
#
# The original design replaced the local resources with the remote's. That was reversed: roles are
# per relation, so a controller that delegates its own lock() calls can still be the server others
# lock against, and hiding its resources would hide the ones they are actively locking. This scenario
# is the regression guard for that decision - it fails if the local resources ever disappear again.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

RESULTS_DIR="${1:-}"
if [[ -z "$RESULTS_DIR" ]]; then
  err "Results directory argument is required"
  exit 2
fi

SCENARIO="delegated-mode-page"
SCENARIO_ID="S21"
SCENARIO_DIR="$RESULTS_DIR/$SCENARIO"
mkdir -p "$SCENARIO_DIR"

TS="$(date +%s)"
REMOTE_RESOURCE="s21-remote-${TS}"
LOCAL_RESOURCE="s21-local-${TS}"
CREDENTIALS_ID="s21-a-for-b"
DETAIL_FILE="$SCENARIO_DIR/scenario-details.md"

fetch_lr_page() {
  curl -sS -u "admin:admin" -o "$1" "${CONTROLLER_A_URL}/lockable-resources/"
}

cleanup() {
  configure_forced_server_id_empty "$CONTROLLER_A_URL" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# --- B publishes a resource; A has one of its own and delegates to B ---
configure_remote_server "$CONTROLLER_B_URL" "$REMOTE_RESOURCE" "remote-enabled" "authenticated"
verify_remote_server_config "$CONTROLLER_B_URL" "$REMOTE_RESOURCE" "authenticated"
configure_local_resource "$CONTROLLER_A_URL" "$LOCAL_RESOURCE"

TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-s21-b-token")"
upsert_username_password_credential "$CONTROLLER_A_URL" "$CREDENTIALS_ID" "admin" "$TOKEN_B"
configure_remote_client_for_server "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "$CREDENTIALS_ID"
configure_forced_server_id "$CONTROLLER_A_URL" "b"

# The catalog is fetched in the background with a short TTL; give the first refresh a moment.
fetch_lr_page "$SCENARIO_DIR/page-warmup.html"
sleep 12
fetch_lr_page "$SCENARIO_DIR/page-delegated.html"

# --- CP01: the badge tells the administrator the resolution semantics changed ---
grep -Fq "Delegated mode" "$SCENARIO_DIR/page-delegated.html" \
  || { err "S21 CP01 FAIL: no delegated-mode badge on the page"; exit 1; }

# --- CP02: local resources are still listed (the reversal of "replace them") ---
grep -Fq "$LOCAL_RESOURCE" "$SCENARIO_DIR/page-delegated.html" \
  || { err "S21 CP02 FAIL: local resources vanished in delegated mode"; exit 1; }
grep -Fq "remain lockable by other controllers" "$SCENARIO_DIR/page-delegated.html" \
  || { err "S21 CP02 FAIL: the page does not explain why local resources are still listed"; exit 1; }

# --- CP03: what the delegated target publishes is shown too ---
grep -Fq "$REMOTE_RESOURCE" "$SCENARIO_DIR/page-delegated.html" \
  || { err "S21 CP03 FAIL: the delegated target's resources are not shown"; exit 1; }

# --- CP04: turning delegation off returns the page to its ordinary state ---
configure_forced_server_id_empty "$CONTROLLER_A_URL"
fetch_lr_page "$SCENARIO_DIR/page-peer.html"
if grep -Fq "Delegated mode" "$SCENARIO_DIR/page-peer.html"; then
  err "S21 CP04 FAIL: the delegated badge survives clearing forcedServerId"
  exit 1
fi
grep -Fq "$LOCAL_RESOURCE" "$SCENARIO_DIR/page-peer.html" \
  || { err "S21 CP04 FAIL: local resources are missing after leaving delegated mode"; exit 1; }

cat >"$SCENARIO_DIR/summary.txt" <<EOF
local_resource=$LOCAL_RESOURCE
remote_resource=$REMOTE_RESOURCE
page_delegated=$SCENARIO_DIR/page-delegated.html
page_peer=$SCENARIO_DIR/page-peer.html
EOF

cat >"$DETAIL_FILE" <<EOF
### ${SCENARIO_ID}: ${SCENARIO}

#### Summary

- local resource on A: $LOCAL_RESOURCE (must stay visible while delegating)
- resource published by B: $REMOTE_RESOURCE

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (delegated-mode badge shown) |
| CP02 | PASS (local resources still listed, with the reason) |
| CP03 | PASS (the delegated target's published resources are shown) |
| CP04 | PASS (clearing forcedServerId removes the badge and keeps local resources) |

#### Artifacts

- page in delegated mode: $SCENARIO_DIR/page-delegated.html
- page after leaving delegated mode: $SCENARIO_DIR/page-peer.html
EOF

log "delegated-mode-page: completed"
