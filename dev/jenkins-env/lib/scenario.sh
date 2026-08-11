#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Scenario scaffolding: narrative, checkpoints, artifacts, and the details file.
#
# Why this exists
# ---------------
# Every scenario used to carry its own copy of this: three of them defined scenario_sequence /
# scenario_checkpoint / finalize_scenario_details verbatim, and the other twenty-two hand-wrote the
# checkpoint table as a heredoc at the very end of the script. That second form has a defect that
# matters: the table is written only if the script reaches the end, and it hardcodes "PASS" in every
# row. So a scenario that passes reports a table of PASSes it did not compute, and a scenario that
# FAILS exits before writing anything at all - run-e2e.sh then prints "Details file is not available"
# for exactly the scenario whose details you needed.
#
# Here the verdict is recorded where it is decided, and the details file is written from an EXIT
# trap, so it exists whatever happens - including an unexpected `set -e` death, which is recorded as
# an ABORT row naming the last step that started.
#
# Failure policy
# --------------
# Checks accumulate by default: a scenario runs all of its checkpoints and fails at the end, so one
# run tells you every broken thing rather than the first. Use scenario_require for preconditions
# where continuing would only produce noise (setup failed, the holder never acquired).
# ---------------------------------------------------------------------------

# Populated by scenario_init.
SCENARIO=""
SCENARIO_ID=""
SCENARIO_DIR=""
DETAIL_FILE=""

_SCENARIO_SEQ_FILE=""
_SCENARIO_CP_FILE=""
_SCENARIO_FACT_FILE=""
_SCENARIO_ARTIFACT_FILE=""
_SCENARIO_SEQ_NO=0
_SCENARIO_CP_NO=0
_SCENARIO_LAST_STEP="(none)"
_SCENARIO_COMPLETED=0
_SCENARIO_SKIP_REASON=""
_SCENARIO_CLEANUP_HOOKS=()

# scenario_init <id> <name> <results_dir>
scenario_init() {
  SCENARIO_ID="$1"
  SCENARIO="$2"
  local results_dir="$3"

  if [[ -z "$results_dir" ]]; then
    err "Results directory argument is required"
    exit 2
  fi

  SCENARIO_DIR="$results_dir/$SCENARIO"
  mkdir -p "$SCENARIO_DIR"
  DETAIL_FILE="$SCENARIO_DIR/scenario-details.md"

  _SCENARIO_SEQ_FILE="$SCENARIO_DIR/.sequence.tmp"
  _SCENARIO_CP_FILE="$SCENARIO_DIR/.checkpoints.tmp"
  _SCENARIO_FACT_FILE="$SCENARIO_DIR/.facts.tmp"
  _SCENARIO_ARTIFACT_FILE="$SCENARIO_DIR/.artifacts.tmp"
  : >"$_SCENARIO_SEQ_FILE"
  : >"$_SCENARIO_CP_FILE"
  : >"$_SCENARIO_FACT_FILE"
  : >"$_SCENARIO_ARTIFACT_FILE"

  trap _scenario_on_exit EXIT
}

# A unique, run-scoped suffix for resource and job names. Scenarios used to call `date +%s` two or
# three times and could straddle a second boundary, which produced names that no longer matched each
# other in the same run.
scenario_stamp() {
  printf '%s' "${_SCENARIO_STAMP:=$(date +%s)}"
}

# ---------------------------------------------------------------------------
# Narrative
# ---------------------------------------------------------------------------

scenario_step() {
  local text="$1"
  _SCENARIO_SEQ_NO=$((_SCENARIO_SEQ_NO + 1))
  _SCENARIO_LAST_STEP="$text"
  printf -- "- SEQ%02d %s\n" "$_SCENARIO_SEQ_NO" "$text" >>"$_SCENARIO_SEQ_FILE"
  log "$SCENARIO_ID SEQ$(printf '%02d' "$_SCENARIO_SEQ_NO"): $text"
}

# ---------------------------------------------------------------------------
# Checkpoints
# ---------------------------------------------------------------------------

# Markdown table cells must not contain a raw pipe, and a multi-line value (Groovy output, a JSON
# body) would break the row entirely.
_scenario_cell() {
  printf '%s' "$1" | tr '\n' ';' | sed 's/|/\\|/g'
}

# scenario_record <label> <action> <expected> <actual> <PASS|FAIL|WARN|INFO>
scenario_record() {
  local label="$1" action="$2" expected="$3" actual="$4" result="$5"
  _SCENARIO_CP_NO=$((_SCENARIO_CP_NO + 1))
  printf '| CP%02d | %s | %s | %s | %s | %s |\n' \
    "$_SCENARIO_CP_NO" \
    "$(_scenario_cell "$label")" \
    "$(_scenario_cell "$action")" \
    "$(_scenario_cell "$expected")" \
    "$(_scenario_cell "$actual")" \
    "$result" >>"$_SCENARIO_CP_FILE"

  if [[ "$result" == "FAIL" ]]; then
    err "$SCENARIO_ID CP$(printf '%02d' "$_SCENARIO_CP_NO") FAIL: $label (expected='$expected' actual='$actual')"
  else
    log "$SCENARIO_ID CP$(printf '%02d' "$_SCENARIO_CP_NO") $result: $label"
  fi
}

# All scenario_check_* helpers record a row and return 0, so an accumulating scenario keeps going
# under `set -e`. Ask scenario_failed whether anything has failed so far.

# scenario_check <label> <action> <expected> <actual>
scenario_check() {
  local label="$1" action="$2" expected="$3" actual="$4"
  if [[ "$expected" == "$actual" ]]; then
    scenario_record "$label" "$action" "$expected" "$actual" "PASS"
  else
    scenario_record "$label" "$action" "$expected" "$actual" "FAIL"
  fi
}

# scenario_check_contains <label> <file> <needle> [action]
scenario_check_contains() {
  local label="$1" file="$2" needle="$3" action="${4:-grep $(basename "$2")}"
  if [[ -r "$file" ]] && grep -Fq "$needle" "$file"; then
    scenario_record "$label" "$action" "contains '$needle'" "found" "PASS"
  else
    scenario_record "$label" "$action" "contains '$needle'" "not found in $file" "FAIL"
  fi
}

# scenario_check_absent <label> <file> <needle> [action]
scenario_check_absent() {
  local label="$1" file="$2" needle="$3" action="${4:-grep $(basename "$2")}"
  if [[ -r "$file" ]] && grep -Fq "$needle" "$file"; then
    scenario_record "$label" "$action" "does not contain '$needle'" "found" "FAIL"
  else
    scenario_record "$label" "$action" "does not contain '$needle'" "absent" "PASS"
  fi
}

# scenario_check_matches <label> <file> <extended-regex> [action]
scenario_check_matches() {
  local label="$1" file="$2" pattern="$3" action="${4:-grep -E $(basename "$2")}"
  if [[ -r "$file" ]] && grep -Eq "$pattern" "$file"; then
    scenario_record "$label" "$action" "matches /$pattern/" "matched" "PASS"
  else
    scenario_record "$label" "$action" "matches /$pattern/" "no match in $file" "FAIL"
  fi
}

# scenario_check_ge <label> <actual> <minimum> [action]
scenario_check_ge() {
  local label="$1" actual="$2" minimum="$3" action="${4:-numeric compare}"
  if [[ "$actual" =~ ^-?[0-9]+$ ]] && ((actual >= minimum)); then
    scenario_record "$label" "$action" ">= $minimum" "$actual" "PASS"
  else
    scenario_record "$label" "$action" ">= $minimum" "$actual" "FAIL"
  fi
}

# scenario_check_lt <label> <actual> <bound> [action]
scenario_check_lt() {
  local label="$1" actual="$2" bound="$3" action="${4:-numeric compare}"
  if [[ "$actual" =~ ^-?[0-9]+$ ]] && ((actual < bound)); then
    scenario_record "$label" "$action" "< $bound" "$actual" "PASS"
  else
    scenario_record "$label" "$action" "< $bound" "$actual" "FAIL"
  fi
}

# Records a fact that is measured but not asserted (elapsed times, counts). Keeps a number in the
# report without inventing a threshold the scenario cannot justify.
scenario_observe() {
  local label="$1" action="$2" value="$3"
  scenario_record "$label" "$action" "(observed)" "$value" "INFO"
}

# A soft expectation: worth seeing in the report, not worth failing the run over. Used for timing
# that depends on the host (the "did these run in parallel" elapsed-time checks).
scenario_check_soft() {
  local label="$1" action="$2" expected="$3" actual="$4" ok="$5"
  if [[ "$ok" == "true" ]]; then
    scenario_record "$label" "$action" "$expected" "$actual" "PASS"
  else
    scenario_record "$label" "$action" "$expected" "$actual" "WARN"
  fi
}

# True when at least one checkpoint has failed.
scenario_failed() {
  grep -q '| FAIL |$' "$_SCENARIO_CP_FILE" 2>/dev/null
}

_scenario_fail_count() {
  grep -c '| FAIL |$' "$_SCENARIO_CP_FILE" 2>/dev/null || true
}

# scenario_require <label> <action> <expected> <actual>
# A precondition: records like scenario_check, but stops the scenario when it fails. For setup that
# everything downstream depends on, where continuing only produces cascading noise.
scenario_require() {
  scenario_check "$@"
  if scenario_failed; then
    err "$SCENARIO_ID: precondition failed, stopping scenario"
    exit 1
  fi
}

# scenario_require_contains <label> <file> <needle>
scenario_require_contains() {
  scenario_check_contains "$@"
  if scenario_failed; then
    err "$SCENARIO_ID: precondition failed, stopping scenario"
    exit 1
  fi
}

# scenario_require_ok <label> <action> <message> - a precondition expressed as an exit status.
#   wait_for_console_contains "$url" MARK 120 || scenario_require_ok "holder acquired" "console" "no marker"
scenario_require_ok() {
  local label="$1" action="$2" detail="$3"
  scenario_record "$label" "$action" "success" "$detail" "FAIL"
  err "$SCENARIO_ID: precondition failed, stopping scenario"
  exit 1
}

# ---------------------------------------------------------------------------
# Facts, artifacts, cleanup
# ---------------------------------------------------------------------------

# scenario_fact <key> <value> - lands in both the details file and summary.txt.
scenario_fact() {
  printf '%s=%s\n' "$1" "$(printf '%s' "$2" | tr '\n' ';')" >>"$_SCENARIO_FACT_FILE"
}

# scenario_artifact <label> <path>
scenario_artifact() {
  printf '%s\t%s\n' "$1" "$2" >>"$_SCENARIO_ARTIFACT_FILE"
}

# scenario_cleanup_hook <command> [args...] - run in reverse order on exit, failures ignored.
# The scenario owns one EXIT trap (installed by scenario_init); this is how to add to it.
#
# Arguments are quoted as they are stored, so they survive the eval that runs them. Joining them
# with a space instead would split any argument containing one - and resource names containing a
# space are a thing B03 deliberately creates, so its own cleanup would have been the first casualty.
scenario_cleanup_hook() {
  local quoted
  quoted="$(printf '%q ' "$@")"
  _SCENARIO_CLEANUP_HOOKS+=("${quoted% }")
}

# scenario_skip <reason> - exits 10, which run-e2e.sh reports as SKIP.
scenario_skip() {
  _SCENARIO_SKIP_REASON="$1"
  log "[SKIP] $SCENARIO: $1"
  exit 10
}

# Marks the scenario as having run to its end. Anything else is an abort.
scenario_finish() {
  _SCENARIO_COMPLETED=1
}

# ---------------------------------------------------------------------------
# Exit handling and rendering
# ---------------------------------------------------------------------------

_scenario_on_exit() {
  local rc=$?
  trap - EXIT

  local i
  for ((i = ${#_SCENARIO_CLEANUP_HOOKS[@]} - 1; i >= 0; i--)); do
    eval "${_SCENARIO_CLEANUP_HOOKS[$i]}" >/dev/null 2>&1 || true
  done

  if [[ -n "$_SCENARIO_SKIP_REASON" ]]; then
    _scenario_render "SKIP"
    exit 10
  fi

  # An unexpected death (set -e, a helper that exited) leaves no checkpoint explaining it. Record one
  # naming the last step that started, so the details file is still worth reading.
  if [[ "$rc" -ne 0 ]] && ! scenario_failed; then
    scenario_record \
      "scenario aborted" \
      "step in progress: $_SCENARIO_LAST_STEP" \
      "scenario runs to completion" \
      "exited with status $rc" \
      "FAIL"
  elif [[ "$rc" -eq 0 && "$_SCENARIO_COMPLETED" -eq 0 ]] && ! scenario_failed; then
    scenario_record \
      "scenario truncated" \
      "step in progress: $_SCENARIO_LAST_STEP" \
      "scenario_finish is reached" \
      "script ended early with status 0" \
      "FAIL"
  fi

  local verdict="PASS"
  scenario_failed && verdict="FAIL"
  _scenario_render "$verdict"

  [[ "$verdict" == "FAIL" ]] && exit 1
  exit 0
}

_scenario_render() {
  local verdict="$1"
  local failures
  failures="$(_scenario_fail_count)"

  {
    echo "### ${SCENARIO_ID}: ${SCENARIO}"
    echo ""
    echo "**Result: ${verdict}** (${_SCENARIO_CP_NO} checkpoints, ${failures:-0} failed)"
    echo ""

    if [[ -n "$_SCENARIO_SKIP_REASON" ]]; then
      echo "Skipped: ${_SCENARIO_SKIP_REASON}"
      echo ""
    fi

    if [[ -s "$_SCENARIO_SEQ_FILE" ]]; then
      echo "#### Sequence"
      echo ""
      cat "$_SCENARIO_SEQ_FILE"
      echo ""
    fi

    echo "#### Checkpoints"
    echo ""
    if [[ -s "$_SCENARIO_CP_FILE" ]]; then
      echo "| ID | Step | API / Action | Expected | Actual | Result |"
      echo "|---|---|---|---|---|---|"
      cat "$_SCENARIO_CP_FILE"
    else
      echo "- No checkpoints were recorded."
    fi
    echo ""

    if [[ -s "$_SCENARIO_FACT_FILE" ]]; then
      echo "#### Summary"
      echo ""
      sed 's/^/- /; s/=/: /' "$_SCENARIO_FACT_FILE"
      echo ""
    fi

    if [[ -s "$_SCENARIO_ARTIFACT_FILE" ]]; then
      echo "#### Artifacts"
      echo ""
      while IFS=$'\t' read -r label path; do
        echo "- ${label}: ${path}"
      done <"$_SCENARIO_ARTIFACT_FILE"
      echo ""
    fi
  } >"$DETAIL_FILE"

  # summary.txt stays a flat key=value file: it is what the load analysis and ad-hoc greps read.
  if [[ -s "$_SCENARIO_FACT_FILE" ]]; then
    cp "$_SCENARIO_FACT_FILE" "$SCENARIO_DIR/summary.txt"
  fi

  rm -f "$_SCENARIO_SEQ_FILE" "$_SCENARIO_CP_FILE" "$_SCENARIO_FACT_FILE" "$_SCENARIO_ARTIFACT_FILE"
}
