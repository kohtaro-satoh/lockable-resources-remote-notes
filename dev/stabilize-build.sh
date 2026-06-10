#!/bin/bash
#
# M1 Build Stabilization Script
# 最終版安定化手順を自動実行
# 使用法: ./stabilize-build.sh [--in-place] [--skip-extend-check] [--skip-test]
#
# 既定では plugin リポジトリ HEAD の隔離 worktree（/tmp 配下）でビルドする。
# これにより VS Code Java 拡張 (jdt.ls) が target/ へ書き込む競合を回避できる。
# リポジトリ直下でビルドしたい場合のみ --in-place を指定する
# （その場合は VS Code の Java 拡張を止めておくこと）。
# 注意: worktree モードはコミット済み HEAD をビルドする。未コミット変更は含まれない。
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_REPO="$(cd "${SCRIPT_DIR}/../../lockable-resources-plugin" && pwd)"
PLUGIN_ROOT="$PLUGIN_REPO"   # --in-place の場合はこのまま使う
MAVEN_BIN="${HOME}/.local/apache-maven-3.9.9/bin/mvn"
REPORTS_DIR="${SCRIPT_DIR}/reports"
LOCK_FILE="${SCRIPT_DIR}/.stabilize-build.lock"

IN_PLACE=false
SKIP_EXTEND_CHECK=false
SKIP_TEST=false

# parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --in-place)
            IN_PLACE=true
            shift
            ;;
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
            echo "Usage: $0 [--in-place] [--skip-extend-check] [--skip-test]"
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

# Isolated worktree setup (default).
# VS Code の Java 拡張 (jdt.ls) はリポジトリ直下の target/ にビルド出力を書き込むため、
# CLI Maven と競合してクラスファイル消失や Extension index 欠落を引き起こす。
# 既定では HEAD の隔離 worktree でビルドしてこれを回避する。
WORKTREE_DIR=""
WORKTREE_KEEP=false

cleanup_worktree() {
    [[ -z "$WORKTREE_DIR" ]] && return 0
    if [[ "$WORKTREE_KEEP" == "true" ]]; then
        log_warn "Keeping worktree for inspection: $WORKTREE_DIR"
        log_warn "Remove later with: git -C $PLUGIN_REPO worktree remove --force $WORKTREE_DIR"
        return 0
    fi
    git -C "$PLUGIN_REPO" worktree remove --force "$WORKTREE_DIR" >/dev/null 2>&1 || true
    rm -rf "$(dirname "$WORKTREE_DIR")"
}

if [[ "$IN_PLACE" != "true" ]]; then
    HEAD_DESC="$(git -C "$PLUGIN_REPO" log -1 --format='%h %s')"
    if [[ -n "$(git -C "$PLUGIN_REPO" status --porcelain)" ]]; then
        log_warn "Plugin repo has uncommitted changes. Worktree mode builds committed HEAD only."
        log_warn "Use --in-place to build the working tree as-is (stop the VS Code Java extension first)."
    fi
    WORKTREE_DIR="$(mktemp -d -t lrr-build-XXXXXX)/plugin"
    git -C "$PLUGIN_REPO" worktree add --detach "$WORKTREE_DIR" HEAD >/dev/null
    trap cleanup_worktree EXIT
    PLUGIN_ROOT="$WORKTREE_DIR"
    log_info "Build mode: isolated worktree (HEAD: ${HEAD_DESC})"
    log_info "Worktree: $WORKTREE_DIR"
else
    log_info "Build mode: in-place (${PLUGIN_ROOT})"
    log_warn "Make sure the VS Code Java extension (jdt.ls) is not running on this repo."
fi
EXTENSION_INDEX="${PLUGIN_ROOT}/target/classes/META-INF/annotations"

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
    if grep -Eq "cannot find symbol|cannot access|bad class file|COMPILATION ERROR" "$STEP3_LOG"; then
        log_warn ""
        log_error "Detected compile resolution error (known unstable build state issue)"
        log_warn ""
        log_warn "Typical cause: another process (e.g. the VS Code Java extension / jdt.ls)"
        log_warn "writing to the same target/ directory, or an unstable WSL state."
        log_warn "Suggested fix:"
        log_warn "  1. Re-run this script in default worktree mode (avoids the VS Code conflict)"
        log_warn "  2. If it persists: close the VS Code Java workspace, or restart WSL (wsl --shutdown)"
        log_warn ""
    else
        log_error "test-compile failed (other error)"
    fi
    log_warn "Step3 log: $STEP3_LOG"
    WORKTREE_KEEP=true
    exit 1
fi
rm -f "$STEP3_LOG"

if [[ ! -d "$EXTENSION_INDEX" ]]; then
    log_error "Extension index directory not found: $EXTENSION_INDEX"
    WORKTREE_KEEP=true
    exit 1
fi

if [[ ! -f "${EXTENSION_INDEX}/hudson.Extension" ]]; then
    log_error "hudson.Extension file not found"
    log_error "Checked: ${EXTENSION_INDEX}/hudson.Extension"
    WORKTREE_KEEP=true
    exit 1
fi

if [[ ! -f "${EXTENSION_INDEX}/hudson.Extension.txt" ]]; then
    log_error "hudson.Extension.txt file not found"
    WORKTREE_KEEP=true
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
log_warn "This may take 10-20 minutes..."
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
    WORKTREE_KEEP=true
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
log_info "Expected: Tests run: 326, Failures: 0, Errors: 0, Skipped: 1"
echo ""
