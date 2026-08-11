#!/usr/bin/env bash
set -euo pipefail

# S21: in delegated mode the page shows the target's resources next to the local ones.
#
# Delegated mode changes what `lock('x')` means on this controller, so the page has to say so - an
# administrator reading a resource list that no longer describes where locks go has been misled.
# The design decision worth protecting is the second one: local resources stay listed. They are
# still there and still lockable by other controllers, and hiding them would make a resource that
# exists look like one that does not.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "S21" "delegated-mode-page" "${1:-}"

STAMP="$(scenario_stamp)"
REMOTE_RESOURCE="s21-remote-$STAMP"
LOCAL_RESOURCE="s21-local-$STAMP"

fetch_lr_page() {
  curl -sS -u "$JENKINS_USER:$JENKINS_PASSWORD" -o "$1" "${CONTROLLER_A_URL}/lockable-resources/"
}

scenario_cleanup_hook configure_forced_server_id_empty "$CONTROLLER_A_URL"

scenario_step "B publishes a resource, A has one of its own, and A delegates to B"
setup_remote_pair "s21" "a" "b" "$REMOTE_RESOURCE"
configure_local_resource "$CONTROLLER_A_URL" "$LOCAL_RESOURCE"
configure_forced_server_id "$CONTROLLER_A_URL" "b"

# The catalogue is fetched in the background and cached for RLR_CATALOG_TTL_S; the first read only
# triggers the fetch, so the page is read again once the cache has had time to fill.
fetch_lr_page "$SCENARIO_DIR/page-warmup.html"
sleep "$(rlr_past "$RLR_CATALOG_TTL_S")"
fetch_lr_page "$SCENARIO_DIR/page-delegated.html"
scenario_artifact "page in delegated mode" "$SCENARIO_DIR/page-delegated.html"

scenario_check_contains "The page announces delegated mode" "$SCENARIO_DIR/page-delegated.html" "Delegated mode"
scenario_check_contains "Local resources are still listed" "$SCENARIO_DIR/page-delegated.html" "$LOCAL_RESOURCE"
scenario_check_contains "And the page explains why they still matter" \
  "$SCENARIO_DIR/page-delegated.html" "remain lockable by other controllers"
scenario_check_contains "The delegated target's resources are shown" \
  "$SCENARIO_DIR/page-delegated.html" "$REMOTE_RESOURCE"

scenario_step "Turn delegation off and read the page again"
configure_forced_server_id_empty "$CONTROLLER_A_URL"
fetch_lr_page "$SCENARIO_DIR/page-peer.html"
scenario_artifact "page after leaving delegated mode" "$SCENARIO_DIR/page-peer.html"

scenario_check_absent "The badge goes with the setting" "$SCENARIO_DIR/page-peer.html" "Delegated mode"
scenario_check_contains "Local resources survive the transition" "$SCENARIO_DIR/page-peer.html" "$LOCAL_RESOURCE"

scenario_fact "local_resource" "$LOCAL_RESOURCE"
scenario_fact "remote_resource" "$REMOTE_RESOURCE"

scenario_finish
