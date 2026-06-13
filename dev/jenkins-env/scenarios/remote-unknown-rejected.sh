#!/usr/bin/env bash
set -euo pipefail

# S17 (P1M1E): an acquire for a resource this client cannot lock (unknown / unexposed) is rejected up
# front with HTTP 404 (admission), and the server does NOT create an ephemeral resource for the unknown
# name. This is the H-1 regression guard: M1D let unknown names create+orphan ephemeral resources and
# queue forever; M1E rejects fast (404) and creates nothing. Also confirms M1E intentionally diverges
# from M1D's "unknown -> QUEUED" (the client fails quickly instead of hanging to the timeout).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

RESULTS_DIR="${1:-}"
if [[ -z "$RESULTS_DIR" ]]; then
  err "Results directory argument is required"
  exit 2
fi

SCENARIO="remote-unknown-rejected"
SCENARIO_ID="S17"
SCENARIO_DIR="$RESULTS_DIR/$SCENARIO"
mkdir -p "$SCENARIO_DIR"

TS="$(date +%s)"
EXPOSED="s17-exposed-${TS}"
UNKNOWN="s17-unknown-${TS}"
CREDENTIALS_ID="s17-a-for-b"
DETAIL_FILE="$SCENARIO_DIR/scenario-details.md"

# --- Setup B: remote API + auth + one exposed resource (exposeLabel = remote-enabled) ---
configure_remote_server "$CONTROLLER_B_URL" "$EXPOSED" "remote-enabled" "authenticated"
verify_remote_server_config "$CONTROLLER_B_URL" "$EXPOSED" "authenticated"

# --- Setup A: credentials + remote client config ---
TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-s17-b-token")"
upsert_username_password_credential "$CONTROLLER_A_URL" "$CREDENTIALS_ID" "admin" "$TOKEN_B"
configure_remote_client_for_server "$CONTROLLER_A_URL" "jenkins-a" "b" "$CONTROLLER_B_INTERNAL_URL" "$CREDENTIALS_ID"

# --- Pipeline (scripted): lock an UNKNOWN resource on b — must fail fast (404), not hang ---
PIPELINE_SCRIPT="$(cat <<EOF
node {
  lock(resource: '$UNKNOWN', serverId: 'b') {
    echo "S17_BODY_SHOULD_NOT_RUN"
  }
}
EOF
)"

upsert_pipeline_job "$CONTROLLER_A_URL" "s17-unknown" "$PIPELINE_SCRIPT"
build_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s17-unknown" 120)"
result="$(wait_for_build_result "$build_url" 300)"
save_console_log "$build_url" "$SCENARIO_DIR/console.txt"

# CP01: the build FAILED (M1E: 404 -> fast failure; it did not hang to the queue timeout)
[[ "$result" == "FAILURE" ]] \
  || { err "S17 CP01 FAIL: expected FAILURE for unknown-resource acquire, got result=$result"; exit 1; }

# CP02: the failure is the 404 admission rejection (ties the failure to M1E, not an unrelated error)
grep -Eq "HTTP 404|UNKNOWN_RESOURCE" "$SCENARIO_DIR/console.txt" \
  || { err "S17 CP02 FAIL: console does not show the 404/UNKNOWN_RESOURCE rejection"; exit 1; }

# CP03: the body did not run (nothing was locked)
if grep -Fq "S17_BODY_SHOULD_NOT_RUN" "$SCENARIO_DIR/console.txt"; then
  err "S17 CP03 FAIL: lock body ran despite rejection"
  exit 1
fi

# CP04: H-1 — the server did NOT create an ephemeral resource for the unknown name
not_created="$(run_groovy_script "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
def r = LockableResourcesManager.get().fromName('${UNKNOWN}')
println('NOT_CREATED=' + (r == null))
" | tr -d '\r')"
printf '%s' "$not_created" | grep -Fq "NOT_CREATED=true" \
  || { err "S17 CP04 FAIL: server created an ephemeral resource for unknown name (state: $not_created)"; exit 1; }

cat >"$SCENARIO_DIR/summary.txt" <<EOF
build_url=$build_url
result=$result
unknown_resource=$UNKNOWN
exposed_resource=$EXPOSED
no_ephemeral=$(printf '%s' "$not_created" | tr '\n' ';')
EOF

cat >"$DETAIL_FILE" <<EOF
### ${SCENARIO_ID}: ${SCENARIO}

#### Summary

- build result: $result (expected FAILURE — fast 404 rejection, not a hang)
- unknown resource: $UNKNOWN
- ephemeral created on server: no

#### Checkpoints

| ID | Result |
|---|---|
| CP01 | PASS (build FAILURE — unknown acquire rejected fast, not queued) |
| CP02 | PASS (console shows HTTP 404 / UNKNOWN_RESOURCE) |
| CP03 | PASS (lock body did not run) |
| CP04 | PASS (server created no ephemeral resource for the unknown name — H-1) |

#### Artifacts

- console: $SCENARIO_DIR/console.txt
- summary: $SCENARIO_DIR/summary.txt
EOF

log "remote-unknown-rejected: completed"
