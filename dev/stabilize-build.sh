#!/bin/bash
#
# M1 Build Stabilization Script
# 最終版安定化手順を自動実行
# 使用法: ./stabilize-build.sh [--skip-extend-check] [--skip-test]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../../lockable-resources-plugin" && pwd)"
MAVEN_BIN="${HOME}/.local/apache-maven-3.9.9/bin/mvn"
EXTENSION_INDEX="${PLUGIN_ROOT}/target/classes/META-INF/annotations"
REPORTS_DIR="${SCRIPT_DIR}/reports"
LOCK_FILE="${SCRIPT_DIR}/.stabilize-build.lock"

SKIP_EXTEND_CHECK=false
SKIP_TEST=false

# parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-extend-check)
            SKIP_EXTEND_CHECK=true
            shift
            ;;
        --skip-test)
            SKIP_TEST=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--skip-extend-check] [--skip-test]"
            exit 1
            ;;
    esac
done

# colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[✗]${NC} $*"
}

# Prevent concurrent runs that can corrupt target/ while Maven is compiling/testing.
if ! command -v flock >/dev/null 2>&1; then
    log_error "flock command is required but not found"
    exit 1
fi

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    log_error "Another stabilize-build.sh process is running. Wait for it to finish and retry."
    log_info "Lock file: $LOCK_FILE"
    exit 1
fi

# check maven
if [[ ! -x "$MAVEN_BIN" ]]; then
    log_error "Maven not found at: $MAVEN_BIN"
    exit 1
fi

log_info "M1 Build Stabilization"
log_info "Plugin root: $PLUGIN_ROOT"
log_info ""

# Step 1: Stop parallel Maven executions
log_info "[Step 1/4] Stopping parallel Maven executions..."
if pgrep -f "mvn" > /dev/null; then
    log_warn "Found running Maven processes. Killing..."
    pkill -f "mvn" || true
    sleep 1
fi
log_success "Maven processes cleared"
echo ""

# Step 2: Reset target directory
log_info "[Step 2/4] Resetting target directory..."
if [[ -d "${PLUGIN_ROOT}/target" ]]; then
    log_warn "Removing ${PLUGIN_ROOT}/target..."
    rm -rf "${PLUGIN_ROOT}/target"
fi
log_success "Target directory cleaned"
echo ""

# Step 3: Generate and verify Extension index
log_info "[Step 3/4] Generating Extension annotation index..."
cd "$PLUGIN_ROOT"

# Run once and inspect the same output for stable failure classification.
STEP3_LOG="$(mktemp -t lrr-step3-compile-XXXXXX.log)"
set +e
"$MAVEN_BIN" -DskipTests test-compile 2>&1 | tee "$STEP3_LOG"
STEP3_RC=${PIPESTATUS[0]}
set -e

if [[ $STEP3_RC -ne 0 ]]; then
    if grep -Eq "cannot find symbol|COMPILATION ERROR" "$STEP3_LOG"; then
        log_warn ""
        log_error "Detected 'cannot find symbol' / compile resolution error (known WSL state issue)"
        log_warn ""
        log_warn "This typically happens after WSL restart or unstable build state."
        log_warn "Suggested fix:"
        log_warn "  1. Exit this script"
        log_warn "  2. Restart WSL: wsl --shutdown"
        log_warn "  3. Run this script again"
        log_warn ""
    else
        log_error "test-compile failed (other error)"
    fi
    log_warn "Step3 log: $STEP3_LOG"
    exit 1
fi
rm -f "$STEP3_LOG"

if [[ ! -d "$EXTENSION_INDEX" ]]; then
    log_error "Extension index directory not found: $EXTENSION_INDEX"
    exit 1
fi

if [[ ! -f "${EXTENSION_INDEX}/hudson.Extension" ]]; then
    log_error "hudson.Extension file not found"
    log_error "Checked: ${EXTENSION_INDEX}/hudson.Extension"
    exit 1
fi

if [[ ! -f "${EXTENSION_INDEX}/hudson.Extension.txt" ]]; then
    log_error "hudson.Extension.txt file not found"
    exit 1
fi

log_success "Extension index verified"
log_info "  - hudson.Extension: $(wc -c < "${EXTENSION_INDEX}/hudson.Extension") bytes"
log_info "  - hudson.Extension.txt: $(wc -l < "${EXTENSION_INDEX}/hudson.Extension.txt") entries"
echo ""

# Step 4: Run tests
if [[ "$SKIP_TEST" == "true" ]]; then
    log_warn "Skipping test execution (--skip-test)"
    echo ""
    log_success "Stabilization complete (without test execution)"
    exit 0
fi

log_info "[Step 4/4] Running full test suite..."
log_warn "This may take 10-15 minutes..."
echo ""

START_TIME=$(date +%s)
cd "$PLUGIN_ROOT"
mkdir -p "$REPORTS_DIR"
MVN_TEST_LOG="${REPORTS_DIR}/$(date +%Y%m%d%H%M%S)-mvn-test.log"
log_info "Saving mvn test log to: $MVN_TEST_LOG"

set +e
"$MAVEN_BIN" test 2>&1 | tee "$MVN_TEST_LOG"
MVN_TEST_RC=${PIPESTATUS[0]}
set -e

if [[ $MVN_TEST_RC -ne 0 ]]; then
    log_error "Test execution failed"
    log_warn "mvn test log: $MVN_TEST_LOG"
    exit 1
fi
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo "============================================"
log_success "Build Stabilization Complete!"
echo "============================================"
echo "Duration: $(printf '%d:%02d' $((DURATION / 60)) $((DURATION % 60)))"
log_info "mvn test log: $MVN_TEST_LOG"
echo ""
log_info "Expected: Tests run: 271, Failures: 0, Errors: 0, Skipped: 1"
echo ""
