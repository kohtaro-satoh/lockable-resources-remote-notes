#!/usr/bin/env bash
#
# run-capture.sh - UI screenshots for the PR.
#
# Builds a small, legible fixture (named like real hardware, not res-01..50), drives the
# controllers into the states worth showing, and photographs them.
#
# Usage:
#   PLUGIN_DIR=../../../lockable-resources-plugin ./capture/run-capture.sh --label after
#   PLUGIN_DIR=<worktree at upstream> ./capture/run-capture.sh --label before --shots tabbar,config
#
# --label decides the filename prefix and nothing else: which plugin is deployed comes from
# PLUGIN_DIR's HEAD, exactly as it does for run-e2e.sh. To photograph upstream without disturbing
# the working tree, point PLUGIN_DIR at a worktree:
#   git -C <plugin> worktree add --detach /tmp/lrr-before <upstream-sha>
set -euo pipefail

CAPTURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$CAPTURE_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LABEL="after"
SHOTS=""
SKIP_START=false
CHROME_IMAGE="zenika/alpine-chrome:with-puppeteer"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label) LABEL="$2"; shift 2 ;;
    --shots) SHOTS="$2"; shift 2 ;;
    --skip-start) SKIP_START=true; shift ;;
    -h|--help) sed -n '2,16p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

RUN_ID="${CAPTURE_RUN_ID:-$(date '+%Y%m%d%H%M%S')}"
OUT_DIR="$SCRIPT_DIR/../reports/$RUN_ID-ui-capture"
mkdir -p "$OUT_DIR"

log "Capture run $RUN_ID (label: $LABEL) -> $OUT_DIR"

if ! $SKIP_START; then
  log "Starting controllers (deploys PLUGIN_DIR's HEAD)"
  "$SCRIPT_DIR/start.sh" --clean
fi
wait_for_controllers 240 a b

DEPLOYED="$(cat "$SCRIPT_DIR/.deployed-plugin" 2>/dev/null || echo unknown)"
log "Deployed plugin: $DEPLOYED"

# ---------------------------------------------------------------------------
# Fixture
#
# Names carry their own meaning, so a reader of the PR can tell what the screen is about without
# the surrounding prose. b owns the hardware; a borrows it.
# ---------------------------------------------------------------------------
A_URL="$(controller_url a)"
B_URL="$(controller_url b)"

fixture_resources() {
  run_groovy_script_checked "$B_URL" '
    import org.jenkins.plugins.lockableresources.LockableResourcesManager
    def m = LockableResourcesManager.get()
    m.getResources().clear()
    ["hw-rig-01", "hw-rig-02", "licence-dongle"].each { n ->
      m.createResourceWithLabel(n, "remote-enabled hardware")
    }
    m.createResourceWithLabel("build-cache", "infra")
    m.save()
    println "FIXTURE_B_OK"
  ' "FIXTURE_B_OK"

  run_groovy_script_checked "$A_URL" '
    import org.jenkins.plugins.lockableresources.LockableResourcesManager
    def m = LockableResourcesManager.get()
    m.getResources().clear()
    m.createResourceWithLabel("staging-slot-1", "staging")
    m.createResourceWithLabel("staging-slot-2", "staging")
    m.save()
    println "FIXTURE_A_OK"
  ' "FIXTURE_A_OK"
}

log "Building the fixture"
fixture_resources
setup_remote_pair cap a b hw-rig-01
expose_resource b hw-rig-02
expose_resource b licence-dongle

# setup_remote_pair registers the server under the harness's own key ("b"), which says nothing to a
# reader of the PR. Keep its work - server config, API token, credential - and rename the single
# client entry to something that reads like a real lab.
SERVER_ID="hw-lab"
run_groovy_script_checked "$A_URL" "
  import org.jenkins.plugins.lockableresources.LockableResourcesManager
  import org.jenkins.plugins.lockableresources.RemoteConnection
  def m = LockableResourcesManager.get()
  def existing = m.getRemotes().find { it.serverId == 'b' }
  m.setRemotes([new RemoteConnection('$SERVER_ID', existing.url, existing.credentialsId)])
  m.save()
  println 'RENAMED_OK'
" "RENAMED_OK" >/dev/null

# ---------------------------------------------------------------------------
# States
# ---------------------------------------------------------------------------
shots_include() { [[ -z "$SHOTS" ]] || [[ ",$SHOTS," == *",$1,"* ]]; }

run_shots() {
  local label="$1" shots="$2"
  docker run --rm --network jenkins-env_default \
    -v "$CAPTURE_DIR:/app:ro" -v "$OUT_DIR:/out" \
    -e "CAP_LABEL=$label" -e "CAP_SHOTS=$shots" \
    --entrypoint node "$CHROME_IMAGE" /app/shots.js
}

# The Remote tab is only worth photographing with something in it: one lock held on b and one
# build queued behind it, so the table shows both states it can show.
if shots_include remote-own-locks || shots_include tabbar || shots_include lr-page; then
  log "State: a holding and queueing a remote lock on b"
  upsert_pipeline_job "$A_URL" "nightly-hardware-test" "
    lock(resource: 'hw-rig-01', serverId: '$SERVER_ID', variable: 'RIG') {
      echo \"holding \${env.RIG}\"
      sleep 600
    }"
  upsert_pipeline_job "$A_URL" "smoke-on-rig" "
    lock(resource: 'hw-rig-01', serverId: '$SERVER_ID') {
      echo 'got it'
    }"
  HOLDER_BUILD_URL="$(trigger_and_resolve_build_url "$A_URL" "nightly-hardware-test")"
  wait_for_console_contains "$HOLDER_BUILD_URL" "holding hw-rig-01" 120
  trigger_job "$A_URL" "smoke-on-rig" >/dev/null
  sleep 12   # let the second request reach the server queue and the client registry
  run_shots "$LABEL" "lr-page,tabbar,remote-own-locks"
fi

if shots_include delegated-badge || shots_include remote-catalog; then
  log "State: a in delegated mode, routed to $SERVER_ID"
  run_groovy_script_checked "$A_URL" "
    import org.jenkins.plugins.lockableresources.LockableResourcesManager
    LockableResourcesManager.get().setForcedServerId('$SERVER_ID')
    LockableResourcesManager.get().save()
    println 'DELEGATED_OK'
  " "DELEGATED_OK"
  sleep 12   # the catalogue is fetched on view and cached for 10s
  run_shots "$LABEL" "delegated-badge,remote-catalog"
  run_groovy_script_checked "$A_URL" '
    import org.jenkins.plugins.lockableresources.LockableResourcesManager
    LockableResourcesManager.get().setForcedServerId("")
    LockableResourcesManager.get().save()
    println "NORMAL_OK"
  ' "NORMAL_OK"
fi

if shots_include config; then
  run_shots "$LABEL" "config"
fi

if shots_include paused-banner; then
  log "State: b not accepting new acquires"
  run_groovy_script_checked "$B_URL" '
    import org.jenkins.plugins.lockableresources.LockableResourcesManager
    LockableResourcesManager.get().setAcceptNewAcquires(false)
    LockableResourcesManager.get().save()
    println "PAUSED_OK"
  ' "PAUSED_OK"
  run_shots "$LABEL" "paused-banner"
  run_groovy_script_checked "$B_URL" '
    import org.jenkins.plugins.lockableresources.LockableResourcesManager
    LockableResourcesManager.get().setAcceptNewAcquires(true)
    LockableResourcesManager.get().save()
    println "RESUMED_OK"
  ' "RESUMED_OK"
fi

abort_build "$A_URL" "${HOLDER_BUILD_URL:-}" 2>/dev/null || true

log "Captured:"
ls -1 "$OUT_DIR" | sed 's/^/  /'
log "Plugin: $DEPLOYED"
