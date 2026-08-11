#!/usr/bin/env bash
set -euo pipefail

RUN_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RUN_SCRIPT_DIR/lib/common.sh"

ONLY="all"
DEBUG_MODE=false
LIST_ONLY=false
ORIGINAL_ARGS=("$@")

RUN_ID="$(date '+%Y%m%d%H%M%S')"
REPORTS_ROOT="$RUN_SCRIPT_DIR/../reports"
REPORT_NAME="$RUN_ID-e2e-test"
RESULTS_DIR="$REPORTS_ROOT/$REPORT_NAME"
REPORT_FILE="$REPORTS_ROOT/$REPORT_NAME.md"

usage() {
  cat <<USAGE
Usage: ./run-e2e.sh [options]

Environment:
  PLUGIN_DIR            Required. Passed to start.sh to locate lockable-resources-plugin, and used
                        to check that lib/timings.sh still matches the plugin's own constants.

Options:
  --only <name|series>  Run one scenario or one series. Default: all.
                        Series: $(registry_series_list | tr '\n' ' ')
                        Names:  see --list
  --list                Print the scenario registry (lib/scenarios.tsv) and exit.
  --debug               Allow uncommitted changes in the plugin and in this harness. Still
                        rebuilds and redeploys, but from the working tree as-is. The report
                        lands in reports/debug/ and is marked NOT REPRODUCIBLE.
  -h, --help            Show this help.

Without --debug every run rebuilds and redeploys from the plugin repo's committed HEAD, so a report
always describes a state that can be reproduced.
USAGE
}

list_scenarios() {
  printf '%-5s %-28s %-9s %-6s %-9s %s\n' ID SCENARIO SERIES CTRLS AXIS SUMMARY
  local name
  while read -r name; do
    printf '%-5s %-28s %-9s %-6s %-9s %s\n' \
      "$(registry_id "$name")" "$name" "$(registry_series "$name")" \
      "$(registry_controllers "$name")" "$(registry_axis "$name")" "$(registry_summary "$name")"
  done < <(registry_names all)
}

format_command_line() {
  local rendered
  rendered="$(printf ' %q' "$0" "${ORIGINAL_ARGS[@]}")"
  printf '%s\n' "${rendered# }"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      DEBUG_MODE=true
      shift
      ;;
    --only)
      ONLY="${2:-}"
      if [[ -z "$ONLY" ]]; then
        err "--only requires a value"
        exit 2
      fi
      shift 2
      ;;
    --list)
      LIST_ONLY=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "Unknown option: $1"
      usage
      exit 2
      ;;
  esac
done

if [[ "$LIST_ONLY" == true ]]; then
  list_scenarios
  exit 0
fi

# --only is valid if it names the whole suite, a series, or a scenario - all three come from the
# registry, so a scenario added there is immediately selectable without touching this file.
select_scenarios() {
  local selection="$1"
  if [[ "$selection" == "all" ]] || registry_series_list | grep -Fxq "$selection"; then
    registry_names "$selection"
  elif registry_has "$selection"; then
    printf '%s\n' "$selection"
  else
    return 1
  fi
}

if ! mapfile -t SELECTED_SCENARIOS < <(select_scenarios "$ONLY") || ((${#SELECTED_SCENARIOS[@]} == 0)); then
  err "Invalid --only value: $ONLY"
  err "Expected 'all', a series ($(registry_series_list | tr '\n' ' ')), or a scenario name (--list)."
  exit 2
fi

require_clean_harness
if [[ "$DEBUG_MODE" == true ]]; then
  # Keep debug output out of reports/: the retention policy keeps "the latest of each", and a
  # throwaway run must not evict the report that closed a cycle.
  REPORTS_ROOT="$REPORTS_ROOT/debug"
  RESULTS_DIR="$REPORTS_ROOT/$REPORT_NAME"
  REPORT_FILE="$REPORTS_ROOT/$REPORT_NAME.md"
  log "--debug: uncommitted changes allowed; report goes to reports/debug/ and is NOT reproducible"
fi
require_command curl
require_command docker
require_command python3
require_command base64

mkdir -p "$REPORTS_ROOT" "$RESULTS_DIR"
log "E2E run id: $RUN_ID"
log "Results dir: $RESULTS_DIR"
log "Report file: $REPORT_FILE"

# Always a clean start: the containers are rebuilt from the plugin repo's committed HEAD, so the
# SHA this report carries is the one that was actually measured. start.sh refuses a dirty tree.
if [[ -z "${PLUGIN_DIR:-}" ]]; then
  err "PLUGIN_DIR is required."
  err "Example: PLUGIN_DIR=../../../lockable-resources-plugin ./run-e2e.sh"
  exit 2
fi

# Before anything runs: the temporal scenarios are written against the plugin's timing constants, and
# a run where those have moved measures nothing. Cheaper to catch here than as a flake later.
if ! rlr_check_timing_drift "$PLUGIN_DIR"; then
  exit 2
fi

log "Starting Jenkins controllers via start.sh --clean"
log "Using PLUGIN_DIR=$PLUGIN_DIR"
if [[ "$DEBUG_MODE" == true ]]; then
  PLUGIN_DIR="$PLUGIN_DIR" "$RUN_SCRIPT_DIR/start.sh" --clean --debug
else
  PLUGIN_DIR="$PLUGIN_DIR" "$RUN_SCRIPT_DIR/start.sh" --clean
fi

# Which controllers the selected scenarios actually need, and which of those came up. A scenario
# whose controllers are not all available is SKIPped by name here rather than by a copy of the same
# probe inside each script.
declare -A NEEDED_CONTROLLERS=()
for scenario in "${SELECTED_SCENARIOS[@]}"; do
  for key in $(registry_controller_keys "$scenario"); do
    NEEDED_CONTROLLERS["$key"]=1
  done
done

log "Waiting for controllers readiness (${!NEEDED_CONTROLLERS[*]})"
declare -A CONTROLLER_UP=()
for key in "${!NEEDED_CONTROLLERS[@]}"; do
  if wait_for_url "$(controller_url "$key")/login" 240; then
    CONTROLLER_UP["$key"]=1
    log "Controller ready: $(controller_url "$key")"
  else
    CONTROLLER_UP["$key"]=0
    err "Controller not ready: $(controller_url "$key")"
  fi
done

# a and b carry the bulk of the suite; without them there is nothing worth reporting.
for key in a b; do
  if [[ -n "${NEEDED_CONTROLLERS[$key]:-}" && "${CONTROLLER_UP[$key]:-0}" != "1" ]]; then
    err "Controller $key is required by the selected scenarios but did not come up"
    exit 1
  fi
done

missing_controllers_for() {
  local scenario="$1"
  local missing=""
  local key
  for key in $(registry_controller_keys "$scenario"); do
    [[ "${CONTROLLER_UP[$key]:-0}" == "1" ]] || missing+="$key "
  done
  printf '%s' "${missing% }"
}

run_scenario() {
  local name="$1"
  local script="$RUN_SCRIPT_DIR/scenarios/$name.sh"
  local rc

  log "Running scenario: $name ($(registry_id "$name"))"
  if [[ ! -x "$script" ]]; then
    err "Scenario script is missing or not executable: $script"
    return 1
  fi

  set +e
  "$script" "$RESULTS_DIR"
  rc=$?
  set -e

  if [[ "$rc" -eq 0 ]]; then
    log "[PASS] $name"
    return 0
  fi
  if [[ "$rc" -eq 10 ]]; then
    log "[SKIP] $name"
    return 10
  fi

  err "[FAIL] $name (exit code: $rc)"
  return "$rc"
}

# Writes a details file for a scenario that never ran, so the report has no silent holes.
write_skip_details() {
  local name="$1"
  local reason="$2"
  local dir="$RESULTS_DIR/$name"
  mkdir -p "$dir"
  {
    echo "### $(registry_id "$name"): $name"
    echo ""
    echo "**Result: SKIP**"
    echo ""
    echo "$reason"
  } >"$dir/scenario-details.md"
}

append_scenario_details() {
  local scenario_name="$1"
  local detail_file="$RESULTS_DIR/$scenario_name/scenario-details.md"

  if [[ -f "$detail_file" ]]; then
    cat "$detail_file"
  else
    echo "### $(registry_id "$scenario_name"): $scenario_name"
    echo ""
    echo "**Result: NO DETAILS** - the scenario produced no details file: $detail_file"
  fi
  echo ""
}

pass_count=0
fail_count=0
skip_count=0

declare -A STATUS
while read -r scenario; do
  STATUS["$scenario"]="NOT_RUN"
done < <(registry_names all)

# The report is written after every scenario has run, and it re-reads the registry to lay out its
# rows. Reading STATUS directly there made the whole report die on `unbound variable` if the registry
# had gained a row since the run started - losing the record of 31 scenarios that had already passed,
# at the last possible moment. A missing entry means "this did not run", which is exactly what the
# report should say.
scenario_status() {
  printf '%s' "${STATUS[$1]:-NOT_RUN}"
}

COMMAND_LINE="$(format_command_line)"

for scenario in "${SELECTED_SCENARIOS[@]}"; do
  missing="$(missing_controllers_for "$scenario")"
  if [[ -n "$missing" ]]; then
    log "[SKIP] $scenario (controllers unavailable: $missing)"
    write_skip_details "$scenario" "Controllers unavailable: $missing (needs $(registry_controllers "$scenario"))."
    skip_count=$((skip_count + 1))
    STATUS["$scenario"]="SKIP"
    continue
  fi

  if run_scenario "$scenario"; then
    pass_count=$((pass_count + 1))
    STATUS["$scenario"]="PASS"
  else
    rc=$?
    if [[ "$rc" -eq 10 ]]; then
      skip_count=$((skip_count + 1))
      STATUS["$scenario"]="SKIP"
    else
      fail_count=$((fail_count + 1))
      STATUS["$scenario"]="FAIL"
    fi
  fi
done

log "Scenario summary: pass=$pass_count fail=$fail_count skip=$skip_count"

{
  echo "# E2E Test Report"
  echo ""
  if [[ "$DEBUG_MODE" == true ]]; then
    echo "> **NOT REPRODUCIBLE** - run with --debug, which allows uncommitted changes."
    echo ""
  fi
  echo "- runId: $RUN_ID"
  echo "- executedAt: $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "- mode: ${ONLY}"
  echo "- commandLine: ${COMMAND_LINE}"
  echo "- plugin: \`$(deployed_plugin_desc)\` $(deployed_plugin_subject)"
  echo "- harness (notes): \`$(harness_desc)\`"
  echo "- reportFile: $REPORT_FILE"
  echo "- captureDir: $RESULTS_DIR"
  echo ""
  echo "## Summary"
  echo ""
  echo "- pass: $pass_count"
  echo "- fail: $fail_count"
  echo "- skip: $skip_count"
  echo ""
  echo "### Coverage by axis"
  echo ""
  echo "| Axis | Pass | Fail | Skip | Not run |"
  echo "|---|---|---|---|---|"
  for axis in function data time scale; do
    a_pass=0; a_fail=0; a_skip=0; a_notrun=0
    while read -r scenario; do
      [[ "$(registry_axis "$scenario")" == "$axis" ]] || continue
      case "$(scenario_status "$scenario")" in
        PASS) a_pass=$((a_pass + 1)) ;;
        FAIL) a_fail=$((a_fail + 1)) ;;
        SKIP) a_skip=$((a_skip + 1)) ;;
        *) a_notrun=$((a_notrun + 1)) ;;
      esac
    done < <(registry_names all)
    echo "| $axis | $a_pass | $a_fail | $a_skip | $a_notrun |"
  done
  echo ""
  echo "## Scenarios"
  echo ""
  echo "| ID | Scenario | Axis | Status | Output | Details |"
  echo "|---|---|---|---|---|---|"
  while read -r scenario; do
    echo "| $(registry_id "$scenario") | $scenario | $(registry_axis "$scenario") | $(scenario_status "$scenario") | [${REPORT_NAME}/${scenario}/](./${REPORT_NAME}/${scenario}/) | [scenario-details.md](./${REPORT_NAME}/${scenario}/scenario-details.md) |"
  done < <(registry_names all)
  echo ""
  echo "## Notes"
  echo ""
  echo "- Console logs and per-case summaries are stored under captureDir."
  echo "- A scenario is skipped when a controller it declares in lib/scenarios.tsv is unavailable."
  echo "- Axis: function = behaviour, data = value boundaries, time = temporal boundaries, scale = size/load boundaries."
  echo ""
  echo "## Scenario Details"
  echo ""
  for scenario in "${SELECTED_SCENARIOS[@]}"; do
    append_scenario_details "$scenario"
  done
} >"$REPORT_FILE"

log "Report generated: $REPORT_FILE"

if [[ "$fail_count" -gt 0 ]]; then
  err "E2E failed. See report: $REPORT_FILE"
  exit 1
fi

log "E2E harness finished"
