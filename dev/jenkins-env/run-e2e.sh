#!/usr/bin/env bash
set -euo pipefail

RUN_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RUN_SCRIPT_DIR/lib/common.sh"

SKIP_START=false
CLEAN_START=false
ONLY="all"
ORIGINAL_ARGS=("$@")

RUN_ID="$(date '+%Y%m%d%H%M%S')"
REPORTS_ROOT="$RUN_SCRIPT_DIR/../reports"
REPORT_NAME="$RUN_ID-e2e-test"
RESULTS_DIR="$REPORTS_ROOT/$REPORT_NAME"
REPORT_FILE="$REPORTS_ROOT/$REPORT_NAME.md"

S_SCENARIOS=(
  "mutual-peer"
  "fan-in-contention"
  "server-self-use"
  "mixed-local-remote"
  "skip-if-locked"
  "three-way-mesh"
  "fail-closed"
)
M1A_SCENARIOS=(
  "label-env-vars"
  "delegated-mode"
)
M1B_SCENARIOS=(
  "extra-resources"
  "heartbeat-resilience"
  "priority-ordering"
  "stale-admin-release"
)
M1C_SCENARIOS=(
  "extra-label-resources"
  "label-quantity-all"
)
M1D_SCENARIOS=(
  "remote-resource-properties"
)
M1E_SCENARIOS=(
  "remote-unknown-rejected"
)
M1I_SCENARIOS=(
  "remote-acquire-timeout"
)
D_SCENARIOS=(
  "fan-in-4"
  "chain-4"
  "diamond"
)
ALL_SCENARIOS=(
  "mutual-peer"
  "fan-in-contention"
  "server-self-use"
  "mixed-local-remote"
  "skip-if-locked"
  "three-way-mesh"
  "fail-closed"
  "label-env-vars"
  "delegated-mode"
  "extra-resources"
  "heartbeat-resilience"
  "priority-ordering"
  "stale-admin-release"
  "extra-label-resources"
  "label-quantity-all"
  "remote-resource-properties"
  "remote-unknown-rejected"
  "remote-acquire-timeout"
  "fan-in-4"
  "chain-4"
  "diamond"
)

declare -A SCENARIO_IDS=(
  ["mutual-peer"]="S01"
  ["fan-in-contention"]="S02"
  ["server-self-use"]="S03"
  ["mixed-local-remote"]="S04"
  ["skip-if-locked"]="S05"
  ["three-way-mesh"]="S06"
  ["fail-closed"]="S07"
  ["label-env-vars"]="S08"
  ["delegated-mode"]="S09"
  ["extra-resources"]="S10"
  ["heartbeat-resilience"]="S11"
  ["priority-ordering"]="S12"
  ["stale-admin-release"]="S13"
  ["extra-label-resources"]="S14"
  ["label-quantity-all"]="S15"
  ["remote-resource-properties"]="S16"
  ["remote-unknown-rejected"]="S17"
  ["remote-acquire-timeout"]="S18"
  ["fan-in-4"]="D01"
  ["chain-4"]="D02"
  ["diamond"]="D03"
)

usage() {
  cat <<'USAGE'
Usage: ./run-e2e.sh [options]

Environment:
  PLUGIN_DIR            Required unless --skip-start is used.
                        Passed to start.sh to locate lockable-resources-plugin.

Options:
  --skip-start          Do not call ./start.sh before scenarios.
  --clean-start         Call ./start.sh --clean before scenarios.
  --only <name>         Run specific scenario or group.
                        mutual-peer | fan-in-contention | server-self-use |
                        mixed-local-remote | skip-if-locked | three-way-mesh |
                        fail-closed | label-env-vars | delegated-mode |
                        extra-resources | heartbeat-resilience |
                        priority-ordering | stale-admin-release |
                        extra-label-resources | label-quantity-all |
                        remote-resource-properties | remote-unknown-rejected |
                        remote-acquire-timeout |
                        fan-in-4 | chain-4 | diamond |
                        s-series | m1a-series | m1b-series | m1c-series | m1d-series | m1e-series | m1i-series | d-series | all
  -h, --help            Show this help.
USAGE
}

format_command_line() {
  local rendered
  rendered="$(printf ' %q' "$0" "${ORIGINAL_ARGS[@]}")"
  printf '%s\n' "${rendered# }"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-start)
      SKIP_START=true
      shift
      ;;
    --clean-start)
      CLEAN_START=true
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

is_valid_only=false
for allowed in all s-series m1a-series m1b-series m1c-series m1d-series m1e-series m1i-series d-series "${ALL_SCENARIOS[@]}"; do
  if [[ "$ONLY" == "$allowed" ]]; then
    is_valid_only=true
    break
  fi
done
if [[ "$is_valid_only" == false ]]; then
  err "Invalid --only value: $ONLY"
  exit 2
fi

if [[ "$SKIP_START" == true && "$CLEAN_START" == true ]]; then
  err "--skip-start and --clean-start cannot be used together"
  exit 2
fi

require_command curl
require_command docker
require_command python3
require_command base64

mkdir -p "$REPORTS_ROOT" "$RESULTS_DIR"
log "E2E run id: $RUN_ID"
log "Results dir: $RESULTS_DIR"
log "Report file: $REPORT_FILE"

if [[ "$SKIP_START" == false ]]; then
  if [[ -z "${PLUGIN_DIR:-}" ]]; then
    err "PLUGIN_DIR is required when run-e2e.sh starts controllers."
    err "Example: PLUGIN_DIR=../../../lockable-resources-plugin ./run-e2e.sh"
    exit 2
  fi

  log "Starting Jenkins controllers via start.sh"
  log "Using PLUGIN_DIR=$PLUGIN_DIR"
  if [[ "$CLEAN_START" == true ]]; then
    PLUGIN_DIR="$PLUGIN_DIR" "$RUN_SCRIPT_DIR/start.sh" --clean
  else
    PLUGIN_DIR="$PLUGIN_DIR" "$RUN_SCRIPT_DIR/start.sh"
  fi
else
  log "Skipping start.sh (requested by --skip-start)"
fi

log "Waiting for controllers readiness (a/b/c)"
if ! wait_for_controllers 240; then
  err "Controller readiness check failed"
  exit 1
fi

run_scenario() {
  local name="$1"
  local script="$RUN_SCRIPT_DIR/scenarios/$name.sh"
  local rc

  log "Running scenario: $name"
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

append_scenario_details() {
  local scenario_name="$1"
  local scenario_id="${SCENARIO_IDS[$scenario_name]:-N/A}"
  local scenario_dir="$RESULTS_DIR/$scenario_name"
  local detail_file="$scenario_dir/scenario-details.md"

  if [[ -f "$detail_file" ]]; then
    cat "$detail_file"
  else
    echo "### $scenario_id: $scenario_name"
    echo ""
    echo "- Details file is not available: $detail_file"
  fi
  echo ""
}

select_scenarios() {
  local selection="$1"
  case "$selection" in
    all)
      printf '%s\n' "${ALL_SCENARIOS[@]}"
      ;;
    s-series)
      printf '%s\n' "${S_SCENARIOS[@]}"
      ;;
    m1a-series)
      printf '%s\n' "${M1A_SCENARIOS[@]}"
      ;;
    m1b-series)
      printf '%s\n' "${M1B_SCENARIOS[@]}"
      ;;
    m1c-series)
      printf '%s\n' "${M1C_SCENARIOS[@]}"
      ;;
    m1d-series)
      printf '%s\n' "${M1D_SCENARIOS[@]}"
      ;;
    m1e-series)
      printf '%s\n' "${M1E_SCENARIOS[@]}"
      ;;
    m1i-series)
      printf '%s\n' "${M1I_SCENARIOS[@]}"
      ;;
    d-series)
      printf '%s\n' "${D_SCENARIOS[@]}"
      ;;
    *)
      printf '%s\n' "$selection"
      ;;
  esac
}

pass_count=0
fail_count=0
skip_count=0

declare -A STATUS
for scenario in "${ALL_SCENARIOS[@]}"; do
  STATUS["$scenario"]="NOT_RUN"
done

mapfile -t SELECTED_SCENARIOS < <(select_scenarios "$ONLY")
COMMAND_LINE="$(format_command_line)"

for scenario in "${SELECTED_SCENARIOS[@]}"; do
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
  echo "- runId: $RUN_ID"
  echo "- executedAt: $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "- mode: ${ONLY}"
  echo "- commandLine: ${COMMAND_LINE}"
  echo "- skipStart: ${SKIP_START}"
  echo "- cleanStart: ${CLEAN_START}"
  echo "- reportFile: $REPORT_FILE"
  echo "- captureDir: $RESULTS_DIR"
  echo ""
  echo "## Summary"
  echo ""
  echo "- pass: $pass_count"
  echo "- fail: $fail_count"
  echo "- skip: $skip_count"
  echo ""
  echo "## Scenarios"
  echo ""
  echo "| ID | Scenario | Status | Output | Details |"
  echo "|---|---|---|---|---|"
  for scenario in "${ALL_SCENARIOS[@]}"; do
    echo "| ${SCENARIO_IDS[$scenario]} | $scenario | ${STATUS[$scenario]} | [${REPORT_NAME}/${scenario}/](./${REPORT_NAME}/${scenario}/) | [scenario-details.md](./${REPORT_NAME}/${scenario}/scenario-details.md) |"
  done
  echo ""
  echo "## Notes"
  echo ""
  echo "- Console logs and per-case summaries are stored under captureDir."
  echo "- D-series scenarios return SKIP when jenkins-d is unavailable."
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
