#!/usr/bin/env bash
set -euo pipefail

RUN_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$RUN_SCRIPT_DIR/lib/common.sh"

SKIP_START=false
CLEAN_START=false
ONLY="all"

RUN_ID="$(date '+%Y%m%d%H%M%S')"
REPORTS_ROOT="$RUN_SCRIPT_DIR/../reports"
REPORT_NAME="$RUN_ID-e2e-test"
RESULTS_DIR="$REPORTS_ROOT/$REPORT_NAME"
REPORT_FILE="$REPORTS_ROOT/$REPORT_NAME.md"

usage() {
  cat <<'EOF'
Usage: ./run-e2e.sh [options]

Environment:
  PLUGIN_DIR            Required unless --skip-start is used.
                        Passed to start.sh to locate lockable-resources-plugin.

Options:
  --skip-start          Do not call ./start.sh before scenarios.
  --clean-start         Call ./start.sh --clean before scenarios.
  --only <name>         Run only one scenario: peer-basic | fail-closed | all
  -h, --help            Show this help.
EOF
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

if [[ "$ONLY" != "all" && "$ONLY" != "peer-basic" && "$ONLY" != "fail-closed" ]]; then
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

mkdir -p "$REPORTS_ROOT"
mkdir -p "$RESULTS_DIR"
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

log "Waiting for controllers readiness"
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

pass_count=0
fail_count=0
skip_count=0
peer_basic_status="NOT_RUN"
fail_closed_status="NOT_RUN"

if [[ "$ONLY" == "all" || "$ONLY" == "peer-basic" ]]; then
  if run_scenario "peer-basic"; then
    pass_count=$((pass_count + 1))
    peer_basic_status="PASS"
  else
    rc=$?
    if [[ "$rc" -eq 10 ]]; then
      skip_count=$((skip_count + 1))
      peer_basic_status="SKIP"
    else
      fail_count=$((fail_count + 1))
      peer_basic_status="FAIL"
    fi
  fi
fi

if [[ "$ONLY" == "all" || "$ONLY" == "fail-closed" ]]; then
  if run_scenario "fail-closed"; then
    pass_count=$((pass_count + 1))
    fail_closed_status="PASS"
  else
    rc=$?
    if [[ "$rc" -eq 10 ]]; then
      skip_count=$((skip_count + 1))
      fail_closed_status="SKIP"
    else
      fail_count=$((fail_count + 1))
      fail_closed_status="FAIL"
    fi
  fi
fi

log "Scenario summary: pass=$pass_count fail=$fail_count skip=$skip_count"

append_scenario_details() {
  local scenario_name="$1"
  local scenario_dir="$RESULTS_DIR/$scenario_name"
  local detail_file="$scenario_dir/scenario-details.md"

  echo "### $scenario_name"
  echo ""
  if [[ -f "$detail_file" ]]; then
    cat "$detail_file"
  else
    echo "- Details file is not available: $detail_file"
  fi
  echo ""
}

{
  echo "# E2E Test Report"
  echo ""
  echo "- runId: $RUN_ID"
  echo "- executedAt: $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "- mode: ${ONLY}"
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
  echo "| Scenario | Status | Output |"
  echo "|---|---|---|"
  echo "| peer-basic | $peer_basic_status | $RESULTS_DIR/peer-basic |"
  echo "| fail-closed | $fail_closed_status | $RESULTS_DIR/fail-closed |"
  echo ""
  echo "## Notes"
  echo ""
  echo "- Console logs and per-case summaries are stored under captureDir."
  echo "- Image capture is not automated in this script; place manual screenshots under captureDir if needed."
  echo ""
  echo "## Scenario Details"
  echo ""
  if [[ "$ONLY" == "all" || "$ONLY" == "peer-basic" ]]; then
    append_scenario_details "peer-basic"
  fi
  if [[ "$ONLY" == "all" || "$ONLY" == "fail-closed" ]]; then
    append_scenario_details "fail-closed"
  fi
} >"$REPORT_FILE"

log "Report generated: $REPORT_FILE"

if [[ "$fail_count" -gt 0 ]]; then
  err "E2E failed. See report: $REPORT_FILE"
  exit 1
fi

log "E2E harness finished"
