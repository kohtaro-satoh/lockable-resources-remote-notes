#!/usr/bin/env bash
set -euo pipefail

# B06: what discovery costs as the catalogue grows, and what it costs everyone else.
#
# The load suite scales one dimension - how many clients are locking at once - and holds every other
# one fixed at "a handful". Catalogue size is the dimension nobody scales, and it is the one where
# the new discovery endpoint has a structural risk: GET /resources serialises every exposed resource
# in a single response, with no paging, and it does that while holding syncResources - the same
# monitor every lock acquisition needs.
#
# So the size question and the interference question are really one question. A server with a few
# hundred boards is fine; the thing worth knowing before a site with thousands finds out is whether
# serving the list starts to cost lock latency. This scenario measures both: how the response grows,
# and how an acquire behaves while the catalogue is being fetched continuously.
#
# The assertions are deliberately loose - absolute bounds a healthy system clears easily, not
# regression thresholds - because the numbers depend on the host. The measurements are recorded
# either way, so a run-to-run comparison is possible even where a pass/fail is not honest.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "B06" "catalog-scale" "${1:-}"

STAMP="$(scenario_stamp)"
PREFIX="b06-bulk-$STAMP"
PROBE_RES="b06-probe-$STAMP"

# Sizes to grow the catalogue through. Override for a deeper run:
#   B06_SIZES="100 1000 5000" ./scenarios/catalog-scale.sh <dir>
read -r -a SIZES <<<"${B06_SIZES:-100 500 2000}"
LARGEST="${SIZES[-1]}"

# A single acquire is a handful of milliseconds; anything approaching these means the catalogue is
# costing lock latency, which is the failure this scenario exists to catch.
ACQUIRE_BOUND_MS=5000
CATALOG_BOUND_MS=15000

drop_bulk_resources() {
  run_groovy_script "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager

def lrm = LockableResourcesManager.get()
def doomed = lrm.getResources().findAll {
  it.getName().startsWith('${PREFIX}-') && !it.isLocked() && it.getRemoteLockedBy() == null
}
lrm.getResources().removeAll(doomed)
lrm.save()
println('REMOVED=' + doomed.size())
" >/dev/null 2>&1 || true
}
scenario_cleanup_hook drop_bulk_resources
scenario_cleanup_hook drop_resources "b" "$PROBE_RES"

scenario_step "Expose a probe resource on B and link A to it"
setup_remote_pair "b06" "a" "b" "$PROBE_RES"
TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-b06-token")"

# grow_catalog_to <n> - creates bulk resources up to n, in one call.
grow_catalog_to() {
  run_groovy_script_checked "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager

def lrm = LockableResourcesManager.get()
(1..$1).each { i ->
  def n = '${PREFIX}-' + i
  if (lrm.fromName(n) == null) {
    lrm.createResourceWithLabel(n, 'remote-enabled')
  }
}
lrm.save()
println('BULK=' + lrm.getResources().findAll { it.getName().startsWith('${PREFIX}-') }.size())
" "BULK=" >/dev/null
}

# Seconds and bytes for one GET /resources. The trailing newline matters: the callers read this
# with `read`, which reports failure on an unterminated line and would abort the scenario.
time_catalog_fetch() {
  local out="$1"
  curl -sS -o "$out" -w '%{time_total} %{size_download}\n' \
    -u "admin:$TOKEN_B" -H 'Accept: application/json' \
    "${CONTROLLER_B_URL}${REMOTE_API_BASE}/resources/"
}

# Milliseconds for one acquire + release of the probe resource.
time_acquire_cycle() {
  local response="$SCENARIO_DIR/.acquire.json"
  local start end lock_id
  start="$(date +%s%3N)"
  api_acquire "b" "$TOKEN_B" "{\"lockRequest\":{\"resource\":\"$PROBE_RES\"}}" "$response" >/dev/null
  lock_id="$(api_field "$response" lockId)" || lock_id=""
  [[ -n "$lock_id" ]] && api_release "b" "$TOKEN_B" "$lock_id" /dev/null >/dev/null
  end="$(date +%s%3N)"
  printf '%s' "$((end - start))"
}

# The median of a handful of cycles: one sample is mostly noise, and a mean is dominated by whatever
# garbage collection happened to land in the window.
median_acquire_ms() {
  local samples=()
  local i
  for ((i = 0; i < 9; i++)); do
    samples+=("$(time_acquire_cycle)")
  done
  printf '%s\n' "${samples[@]}" | sort -n | sed -n '5p'
}

scenario_step "Measure the baseline acquire latency on a small catalogue"
baseline_ms="$(median_acquire_ms)"
scenario_observe "Acquire + release, small catalogue" "median of 9 cycles" "${baseline_ms}ms"

scenario_step "Grow the catalogue and measure discovery at each size"
catalog_report="$SCENARIO_DIR/catalog-scaling.txt"
: >"$catalog_report"
scenario_artifact "scaling measurements" "$catalog_report"

for size in "${SIZES[@]}"; do
  grow_catalog_to "$size"
  read -r seconds bytes < <(time_catalog_fetch "$SCENARIO_DIR/resources-$size.json")
  ms="$(python3 -c "print(round(float('$seconds') * 1000))")"

  listed="$(python3 - "$SCENARIO_DIR/resources-$size.json" "$PREFIX" <<'PY'
import json, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
print(sum(1 for r in data.get("resources", []) if r["name"].startswith(sys.argv[2] + "-")))
PY
)"

  printf 'resources=%s listed=%s bytes=%s ms=%s\n' "$size" "$listed" "$bytes" "$ms" >>"$catalog_report"
  scenario_observe "Catalogue of $size" "GET /resources" "${ms}ms, ${bytes} bytes, ${listed} of $size listed"

  # No paging means the whole list every time, so a short answer is a truncated one.
  scenario_check "All $size resources are listed" "GET /resources body" "$size" "$listed"
done

read -r largest_seconds largest_bytes < <(time_catalog_fetch "$SCENARIO_DIR/resources-final.json")
largest_ms="$(python3 -c "print(round(float('$largest_seconds') * 1000))")"
scenario_check_lt "Discovery still answers promptly at $LARGEST resources" \
  "$largest_ms" "$CATALOG_BOUND_MS" "milliseconds for GET /resources"

scenario_step "Measure acquire latency while the catalogue is being fetched continuously"
# The interference test. describe() runs under syncResources, so a large catalogue served in a loop
# is the cheapest way to find out whether discovery and acquisition contend for the same monitor.
fetch_loop() {
  local deadline=$((SECONDS + 60))
  while ((SECONDS < deadline)); do
    curl -sS -o /dev/null -u "admin:$TOKEN_B" -H 'Accept: application/json' \
      "${CONTROLLER_B_URL}${REMOTE_API_BASE}/resources/" || true
  done
}

for _ in 1 2 3 4; do
  fetch_loop &
done
loaded_ms="$(median_acquire_ms)"
wait

scenario_observe "Acquire + release, catalogue of $LARGEST served by 4 clients in a loop" \
  "median of 9 cycles" "${loaded_ms}ms"

ratio="$(python3 -c "print(round($loaded_ms / max($baseline_ms, 1), 2))")"
scenario_observe "Latency multiple under discovery load" "loaded / baseline" "${ratio}x"

# The bound is absolute, not a ratio: a baseline of a few milliseconds makes any ratio look alarming,
# while what actually matters is whether a lock takes long enough for a build to notice.
scenario_check_lt "Acquiring stays responsive while discovery is under load" \
  "$loaded_ms" "$ACQUIRE_BOUND_MS" "milliseconds, median"

scenario_step "Check the probe resource survived it all"
scenario_check_resource_free "Probe resource free at the end" "b" "$PROBE_RES"

scenario_fact "sizes" "${SIZES[*]}"
scenario_fact "baseline_acquire_ms" "$baseline_ms"
scenario_fact "loaded_acquire_ms" "$loaded_ms"
scenario_fact "latency_multiple" "$ratio"
scenario_fact "catalog_ms_at_${LARGEST}" "$largest_ms"
scenario_fact "catalog_bytes_at_${LARGEST}" "$largest_bytes"

scenario_finish
