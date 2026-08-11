#!/usr/bin/env bash
set -euo pipefail

# B04: the client's view of a remote catalogue is cached, and both halves of that need checking.
#
# Rendering the page never makes the HTTP call. It shows the snapshot it has and, once that snapshot
# is older than RLR_CATALOG_TTL_S, asks for a refresh in the background. Two behaviours follow, and
# they are in tension:
#
#   * within the TTL the page is deliberately out of date - a resource added on the server is not
#     there yet, which is correct and is what makes the page cheap;
#   * past the TTL it must catch up, or "cached" quietly becomes "wrong forever".
#
# The third case is the one that justifies the design: when the server is unreachable the page must
# still render from what it last knew. Display is best-effort - unlike acquiring a lock, which stays
# fail-closed - so an outage on the server must cost an aged view here, not a page that hangs.
#
# Because the refresh is asynchronous, "past the TTL" means two reads: the first one triggers the
# fetch and still returns the old snapshot, the second sees the result.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "B04" "catalog-cache-ttl" "${1:-}"

STAMP="$(scenario_stamp)"
FIRST="b04-first-$STAMP"
LATER="b04-later-$STAMP"

scenario_cleanup_hook drop_resources "b" "$FIRST" "$LATER"
scenario_cleanup_hook configure_forced_server_id_empty "$CONTROLLER_A_URL"
scenario_cleanup_hook docker_compose up -d jenkins-b

fetch_page() {
  curl -sS -u "$JENKINS_USER:$JENKINS_PASSWORD" -o "$1" "${CONTROLLER_A_URL}/lockable-resources/"
}

# A page read that lets an already-triggered background refresh land first.
fetch_page_after_refresh() {
  fetch_page "$1.tmp"
  sleep 3
  fetch_page "$1"
  rm -f "$1.tmp"
}

scenario_step "B publishes one resource; A delegates to B so its page shows B's catalogue"
setup_remote_pair "b04" "a" "b" "$FIRST"
configure_forced_server_id "$CONTROLLER_A_URL" "b"

scenario_step "Warm the cache and confirm the first resource is visible"
fetch_page_after_refresh "$SCENARIO_DIR/page-warm.html"
scenario_artifact "page after warm-up" "$SCENARIO_DIR/page-warm.html"
scenario_require_contains "The catalogue reaches the client page" "$SCENARIO_DIR/page-warm.html" "$FIRST"

scenario_step "Add a resource on B and read the page immediately (inside the ${RLR_CATALOG_TTL_S}s TTL)"
expose_resource "b" "$LATER"
fetch_page "$SCENARIO_DIR/page-within-ttl.html"
scenario_artifact "page within TTL" "$SCENARIO_DIR/page-within-ttl.html"
# Not a defect - this is the cache doing its job. Asserting it is how the TTL stops being a number
# nobody depends on.
scenario_check_absent "Within the TTL the page still shows the old snapshot" \
  "$SCENARIO_DIR/page-within-ttl.html" "$LATER"

scenario_step "Wait past the TTL and read again"
sleep "$(rlr_past "$RLR_CATALOG_TTL_S")"
fetch_page_after_refresh "$SCENARIO_DIR/page-past-ttl.html"
scenario_artifact "page past TTL" "$SCENARIO_DIR/page-past-ttl.html"
scenario_check_contains "Past the TTL the new resource appears" "$SCENARIO_DIR/page-past-ttl.html" "$LATER"
scenario_check_contains "and the original is still there" "$SCENARIO_DIR/page-past-ttl.html" "$FIRST"

scenario_step "Stop the server and check the page still renders from what it last knew"
docker_compose stop jenkins-b
sleep "$(rlr_past "$RLR_CATALOG_TTL_S")"

page_start="$(date +%s)"
fetch_page "$SCENARIO_DIR/page-server-down.html"
page_elapsed="$(($(date +%s) - page_start))"
scenario_artifact "page while the server is down" "$SCENARIO_DIR/page-server-down.html"

scenario_check_contains "The page still renders with the server gone" \
  "$SCENARIO_DIR/page-server-down.html" "$FIRST"
# An outage should age the view, not empty it, and above all not block the render. The bound is
# generous: what is being ruled out is a page that waits on the remote's own request timeout.
scenario_check_lt "Rendering did not wait on the unreachable server" \
  "$page_elapsed" $((RLR_REQUEST_TIMEOUT_S + 10)) "seconds to render"

scenario_step "Bring the server back and check the view recovers"
docker_compose up -d jenkins-b
wait_for_url "$CONTROLLER_B_URL/login" 240 ||
  scenario_require_ok "Controller B recovers" "wait_for_url" "B did not come back"
# The resource list is rebuilt from disk on restart, so both resources should be published again.
sleep "$(rlr_past "$RLR_CATALOG_TTL_S")"
fetch_page_after_refresh "$SCENARIO_DIR/page-recovered.html"
scenario_artifact "page after recovery" "$SCENARIO_DIR/page-recovered.html"
scenario_check_contains "The view recovers once the server is back" \
  "$SCENARIO_DIR/page-recovered.html" "$LATER"

scenario_fact "catalog_ttl_seconds" "$RLR_CATALOG_TTL_S"
scenario_fact "render_seconds_with_server_down" "$page_elapsed"

scenario_finish
