#!/usr/bin/env bash
set -euo pipefail

# B07: how the queue behaves as it gets deep.
#
# The load suite scales how many clients are locking at once, across many resources. This scales the
# other thing - how many of them are waiting for the *same* resource - which is the dimension a lock
# system is actually judged on. Everything else in the suite queues one or two waiters.
#
# Two questions, and the second is the one that bites:
#
#   * throughput: after a holder lets go, how long until the next waiter is in, and how long to drain
#     the whole queue. If promotion rescans the queue from the top each time this is quadratic, and
#     a deep queue is where that first becomes visible.
#
#   * fairness: does every waiter eventually get served. A queue that always promotes the same end
#     starves the other one, and starvation cannot be seen at depth 2 - at depth 2 everyone gets a
#     turn no matter how badly the queue is ordered.
#
# Fairness is asserted; the timings are measured and reported rather than thresholded, because they
# depend on the host. What does not depend on the host is the shape: promoting one waiter should cost
# about the same whether ten or five hundred are queued behind it.
#
# Two numbers, and only the first is about the server. Promotion latency is the gap between the
# holder releasing and the first waiter being served - nothing client-side is in it. Drain time is
# the whole queue, and draining is a chain: each promotion waits for the previous client to notice
# and release, so it carries client latency per waiter and says as much about the clients as about
# the server.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "B07" "queue-depth-scale" "${1:-}"

STAMP="$(scenario_stamp)"
RES="b07-res-$STAMP"
RESPONSE="$SCENARIO_DIR/response.json"
REPORT="$SCENARIO_DIR/queue-scaling.txt"

# Override for a deeper run: B07_DEPTHS="1 10 100 500" ./scenarios/queue-depth-scale.sh <dir>
read -r -a DEPTHS <<<"${B07_DEPTHS:-1 10 50}"

scenario_cleanup_hook drop_resources "b" "$RES"

scenario_step "Expose one resource on B - every waiter will want this same one"
configure_remote_server "$CONTROLLER_B_URL" "$RES" "remote-enabled" "authenticated"
verify_remote_server_config "$CONTROLLER_B_URL" "$RES" "authenticated"
TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-b07-token")"

: >"$REPORT"
scenario_artifact "scaling measurements" "$REPORT"

# Fires `depth` acquires at once and prints their lock ids, one per line. Parallel on purpose: the
# queue has to be built faster than it drains, and a serial loop at depth 50 would let the earlier
# ones start being served before the later ones are even in.
enqueue_waiters() {
  local depth="$1"
  local dir="$SCENARIO_DIR/.waiters"
  rm -rf "$dir"
  mkdir -p "$dir"

  local i
  for ((i = 0; i < depth; i++)); do
    (
      api_acquire "b" "$TOKEN_B" "{\"lockRequest\":{\"resource\":\"$RES\"}}" "$dir/$i.json" >/dev/null 2>&1 || true
    ) &
  done
  wait

  for ((i = 0; i < depth; i++)); do
    local id
    id="$(api_field "$dir/$i.json" lockId)" || id=""
    [[ -n "$id" ]] && printf '%s\n' "$id"
  done
}

# One client per waiter, each watching only its own lease and releasing the moment it is served.
# Prints "<served> <ms_to_first_promotion> <ms_to_drain>".
#
# One loop polling every outstanding id would be the obvious way to write this and would produce a
# fabricated result: each sweep costs one request per waiter still queued, so watching a queue of N
# costs O(N^2) requests overall, and the drain time it "measures" is mostly the harness talking to
# itself. At depth 50 that self-inflicted cost was the entire measurement. Real clients each watch
# their own lease, so that is what this does.
WATCH_INTERVAL_SECONDS=0.5

drain_queue() {
  local deadline_seconds="$1"
  shift
  local ids=("$@")

  local dir="$SCENARIO_DIR/.drain"
  rm -rf "$dir"
  mkdir -p "$dir"

  local deadline_polls=$((deadline_seconds * 2)) # WATCH_INTERVAL_SECONDS is 0.5

  local start
  start="$(date +%s%3N)"

  local id
  for id in "${ids[@]}"; do
    (
      # Counted in polls rather than seconds: working out elapsed time in a subprocess twice a second
      # per worker would put more load on the host than the thing being measured.
      local polls=0
      local state
      while ((polls < deadline_polls)); do
        api_poll "b" "$TOKEN_B" "$id" "$dir/$id.json" >/dev/null 2>&1 || true
        state="$(api_field "$dir/$id.json" state)" || state=""
        if [[ "$state" == "ACQUIRED" ]]; then
          date +%s%3N >"$dir/$id.at"
          api_release "b" "$TOKEN_B" "$id" /dev/null >/dev/null 2>&1 || true
          exit 0
        fi
        # Anything not still queued is terminal: this one will never be served.
        [[ "$state" == "QUEUED" ]] || exit 1
        sleep "$WATCH_INTERVAL_SECONDS"
        polls=$((polls + 1))
      done
      exit 2
    ) &
  done
  wait

  local served=0 first_at="" last_at=""
  local stamp_file
  for stamp_file in "$dir"/*.at; do
    [[ -e "$stamp_file" ]] || continue
    served=$((served + 1))
  done
  if ((served > 0)); then
    first_at="$(cat "$dir"/*.at | sort -n | head -1)"
    last_at="$(cat "$dir"/*.at | sort -n | tail -1)"
  fi

  local now
  now="$(date +%s%3N)"
  # Newline included: the caller reads this with `read`, which reports failure on an unterminated
  # line and would take the scenario down with it.
  printf '%s %s %s\n' "$served" "$(( ${first_at:-$now} - start ))" "$(( ${last_at:-$now} - start ))"
}

for depth in "${DEPTHS[@]}"; do
  scenario_step "Queue depth $depth"

  # A holder first, so every request that follows has to wait.
  api_acquire "b" "$TOKEN_B" "{\"lockRequest\":{\"resource\":\"$RES\"}}" "$RESPONSE" >/dev/null
  holder_id="$(api_field "$RESPONSE" lockId)"
  scenario_require "depth $depth: holder took the resource" "POST /acquire" \
    "ACQUIRED" "$(api_field "$RESPONSE" state)"

  mapfile -t waiters < <(enqueue_waiters "$depth")
  scenario_check "depth $depth: every waiter was accepted" "POST /acquire x$depth" "$depth" "${#waiters[@]}"

  # Everything is queued behind the holder; letting go starts the clock.
  api_release "b" "$TOKEN_B" "$holder_id" /dev/null >/dev/null

  read -r served first_ms drain_ms < <(drain_queue $((60 + depth * 2)) "${waiters[@]}")

  printf 'depth=%s served=%s promotion_ms=%s drain_ms=%s\n' \
    "$depth" "$served" "$first_ms" "$drain_ms" >>"$REPORT"

  # Fairness: a queue that starves its tail serves fewer than it accepted.
  scenario_check "depth $depth: every waiter was eventually served" \
    "each waiter watched its own lease" "$depth" "$served"

  # The clean server-side number. One waiter is promoted the instant the holder lets go, with the
  # rest of the queue sitting behind it - so this is the cost of promotion at this depth, with no
  # client-side notice latency in it.
  scenario_observe "depth $depth: promotion latency" "holder release -> first waiter served" "${first_ms}ms"
  # Draining is a chain: each promotion waits for the previous client to notice and release, so this
  # carries up to one WATCH_INTERVAL_SECONDS of client latency per waiter and is not a server metric.
  scenario_observe "depth $depth: drain time (includes client notice latency)" \
    "holder release -> last waiter served" "${drain_ms}ms"

  scenario_check_resource_free "depth $depth: resource free afterwards" "b" "$RES"

  scenario_fact "depth_${depth}_served" "$served"
  scenario_fact "depth_${depth}_first_ms" "$first_ms"
  scenario_fact "depth_${depth}_drain_ms" "$drain_ms"
done

rm -rf "$SCENARIO_DIR/.waiters" "$SCENARIO_DIR/.drain"

scenario_step "Compare promotion latency across depths"
# The shape, not the absolute numbers. Promoting one waiter should cost about the same whether ten
# or five hundred are queued behind it; a promotion latency that climbs steeply with depth means the
# promotion path is re-scanning the queue, and the deepest queue a site actually runs is where that
# stops being free.
promotion_at() {
  sed -E "/^depth=$1 /!d; s/.*promotion_ms=([0-9]+).*/\1/" "$REPORT"
}
shallow_ms="$(promotion_at "${DEPTHS[0]}")"
deep_ms="$(promotion_at "${DEPTHS[-1]}")"
scenario_observe "Promotion latency, shallowest vs deepest queue" \
  "depth ${DEPTHS[0]} vs depth ${DEPTHS[-1]}" "${shallow_ms}ms vs ${deep_ms}ms"

scenario_fact "depths" "${DEPTHS[*]}"
scenario_fact "promotion_ms_shallow" "$shallow_ms"
scenario_fact "promotion_ms_deep" "$deep_ms"

scenario_finish
