#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# The plugin's own timing constants, named.
#
# Every temporal scenario in this suite is really a statement about one of these numbers: "wait long
# enough that a heartbeat is missed", "poll after the terminal record is gone", "read the catalog
# before its TTL expires". Written as bare sleeps those statements are invisible - `sleep 25` says
# nothing about the 60s STALE threshold it was chosen to stay under, so the day the plugin moves the
# constant the test keeps passing while testing nothing.
#
# So the constants live here once, named after the field they mirror, and rlr_check_timing_drift()
# re-reads the plugin source at the start of every run to prove they still match. A scenario that
# needs "just under STALE" writes it as such and gets the margin arithmetic from a helper.
# ---------------------------------------------------------------------------

# --- Client side (RemoteClientDefaults) ---
RLR_POLL_INTERVAL_S=3       # DEFAULT_POLL_INTERVAL_SECONDS - acquire-status poll cadence
RLR_HEARTBEAT_INTERVAL_S=10 # DEFAULT_HEARTBEAT_INTERVAL_SECONDS - lease renewal cadence
RLR_REQUEST_TIMEOUT_S=5     # DEFAULT_REQUEST_TIMEOUT_SECONDS - per-HTTP-call timeout

# --- Client side (RemoteLockSession) ---
# Consecutive poll failures tolerated before the session gives up and fails closed (~60s at 3s).
RLR_MAX_POLL_FAILURES=20

# --- Server side (RemoteLockManager) ---
# max(heartbeat * 6, 60): how long a lease survives without a heartbeat before it is marked STALE.
RLR_STALE_THRESHOLD_S=60
# How long a terminal (SKIPPED/FAILED/RELEASED) record stays observable, measured from the instant it
# went terminal - not from enqueue. See the queued-expiry-poll-404 comment in RemoteLockManager.
RLR_TERMINAL_TTL_S=120

# --- Server side (RemoteCatalogCache) ---
# Client-side catalog freshness: a page may show state this old before a refresh is triggered.
RLR_CATALOG_TTL_S=10

# --- Server side (RemoteApiV1Action) ---
# POST /acquire body cap. Over this the endpoint answers 413 PAYLOAD_TOO_LARGE.
RLR_MAX_BODY_CHARS=1048576

# ---------------------------------------------------------------------------
# Derived waits
#
# Boundary scenarios need "safely inside" and "safely past" a threshold, and both need a margin: the
# client polls on a 3s cadence and Jenkins schedules the sweep on its own clock, so a wait aimed
# exactly at the constant lands on either side at random. The margin is one poll interval plus a
# second, which is the smallest gap that cannot be closed by cadence alone.
# ---------------------------------------------------------------------------

RLR_TIMING_MARGIN_S=$((RLR_POLL_INTERVAL_S + 1))

# Longest wait that must NOT cross the threshold (threshold - margin).
rlr_inside() {
  local threshold="$1"
  echo $((threshold - RLR_TIMING_MARGIN_S))
}

# Shortest wait that must definitely have crossed the threshold (threshold + margin).
rlr_past() {
  local threshold="$1"
  echo $((threshold + RLR_TIMING_MARGIN_S))
}

# ---------------------------------------------------------------------------
# Drift guard
#
# Re-reads the constants from the plugin source and compares. Called once per run, before any
# scenario, so a mismatch is reported as a harness error rather than as a mysterious flake three
# scenarios later. Silently skipped when the plugin source is not reachable (PLUGIN_DIR unset).
# ---------------------------------------------------------------------------

# Pulls the assigned integer out of the first line of $file matching $pattern.
#
# The declaration is the last number on the line once comments are gone - which is the point of
# stripping them first: `MAX_CONSECUTIVE_POLL_FAILURES = 20; // ~60s at 3s poll interval` otherwise
# reads as 3, and the guard reports a drift that is really a trailing comment.
rlr_grep_int() {
  local file="$1"
  local pattern="$2"
  grep -m1 -E "$pattern" "$file" 2>/dev/null |
    sed -E 's|//.*||; s|/\*.*\*/||' |
    grep -oE '[0-9][0-9_]*' | tail -n1 | tr -d '_'
}

rlr_check_timing_drift() {
  local plugin_dir="${1:-${PLUGIN_DIR:-}}"
  if [[ -z "$plugin_dir" || ! -d "$plugin_dir" ]]; then
    return 0
  fi

  local remote_pkg="$plugin_dir/src/main/java/org/jenkins/plugins/lockableresources/remote"
  local actions_pkg="$plugin_dir/src/main/java/org/jenkins/plugins/lockableresources/actions"
  local defaults="$remote_pkg/RemoteClientDefaults.java"
  local manager="$remote_pkg/RemoteLockManager.java"
  local session="$remote_pkg/RemoteLockSession.java"
  local cache="$remote_pkg/RemoteCatalogCache.java"
  local api="$actions_pkg/RemoteApiV1Action.java"

  if [[ ! -r "$defaults" ]]; then
    return 0
  fi

  local drift=()
  local actual

  actual="$(rlr_grep_int "$defaults" 'DEFAULT_POLL_INTERVAL_SECONDS *=')"
  [[ -n "$actual" && "$actual" != "$RLR_POLL_INTERVAL_S" ]] &&
    drift+=("RLR_POLL_INTERVAL_S: harness=$RLR_POLL_INTERVAL_S plugin=$actual")

  actual="$(rlr_grep_int "$defaults" 'DEFAULT_HEARTBEAT_INTERVAL_SECONDS *=')"
  [[ -n "$actual" && "$actual" != "$RLR_HEARTBEAT_INTERVAL_S" ]] &&
    drift+=("RLR_HEARTBEAT_INTERVAL_S: harness=$RLR_HEARTBEAT_INTERVAL_S plugin=$actual")

  actual="$(rlr_grep_int "$defaults" 'DEFAULT_REQUEST_TIMEOUT_SECONDS *=')"
  [[ -n "$actual" && "$actual" != "$RLR_REQUEST_TIMEOUT_S" ]] &&
    drift+=("RLR_REQUEST_TIMEOUT_S: harness=$RLR_REQUEST_TIMEOUT_S plugin=$actual")

  if [[ -r "$session" ]]; then
    actual="$(rlr_grep_int "$session" 'MAX_CONSECUTIVE_POLL_FAILURES *=')"
    [[ -n "$actual" && "$actual" != "$RLR_MAX_POLL_FAILURES" ]] &&
      drift+=("RLR_MAX_POLL_FAILURES: harness=$RLR_MAX_POLL_FAILURES plugin=$actual")
  fi

  if [[ -r "$manager" ]]; then
    # STALE_THRESHOLD_MS = max(heartbeat * 6, 60) seconds - recompute rather than parse the expression.
    local expected_stale=$((RLR_HEARTBEAT_INTERVAL_S * 6))
    ((expected_stale < 60)) && expected_stale=60
    [[ "$expected_stale" != "$RLR_STALE_THRESHOLD_S" ]] &&
      drift+=("RLR_STALE_THRESHOLD_S: harness=$RLR_STALE_THRESHOLD_S derived=$expected_stale")

    actual="$(rlr_grep_int "$manager" 'TERMINAL_TTL_MS *=')"
    [[ -n "$actual" && "$actual" != "$RLR_TERMINAL_TTL_S" ]] &&
      drift+=("RLR_TERMINAL_TTL_S: harness=$RLR_TERMINAL_TTL_S plugin=$actual")
  fi

  if [[ -r "$cache" ]]; then
    actual="$(rlr_grep_int "$cache" 'TTL_MILLIS *=')"
    if [[ -n "$actual" ]]; then
      local ttl_s=$((actual / 1000))
      [[ "$ttl_s" != "$RLR_CATALOG_TTL_S" ]] &&
        drift+=("RLR_CATALOG_TTL_S: harness=$RLR_CATALOG_TTL_S plugin=$ttl_s")
    fi
  fi

  if [[ -r "$api" ]]; then
    # MAX_BODY_CHARS is written as an expression (1024 * 1024); evaluate what the source says.
    local expr
    expr="$(grep -m1 -E 'MAX_BODY_CHARS *=' "$api" | sed -E 's/.*= *([^;]+);.*/\1/' | tr -d ' _')"
    if [[ "$expr" =~ ^[0-9*+]+$ ]]; then
      actual=$((expr))
      [[ "$actual" != "$RLR_MAX_BODY_CHARS" ]] &&
        drift+=("RLR_MAX_BODY_CHARS: harness=$RLR_MAX_BODY_CHARS plugin=$actual")
    fi
  fi

  if ((${#drift[@]} > 0)); then
    err "Timing constants in lib/timings.sh no longer match the plugin source:"
    printf '          %s\n' "${drift[@]}" >&2
    err "Temporal scenarios are written against these numbers; update lib/timings.sh (and re-check"
    err "the scenarios that depend on the changed threshold) before trusting a run."
    return 1
  fi

  return 0
}
