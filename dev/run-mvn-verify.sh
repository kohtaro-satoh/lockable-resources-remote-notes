#!/bin/bash
#
# run-mvn-verify.sh - CI-equivalent local check before pushing.
#
# ci.jenkins.io runs buildPlugin() (jenkins-infra/pipeline-library), which drives
# `mvn clean verify` with the plugin parent POM's quality gates:
#   - spotless:check        (code formatting)
#   - spotbugs:check        (effort=Max, threshold=Low -> even Low findings fail)
#   - checkstyle / pmd / cpd
#   - the full test suite
# `mvn test` (used by stabilize-build.sh) stops at the test phase and skips all of
# the above gates, so they were only caught on CI. This script runs `mvn clean verify`
# locally so they are caught before push.
#
# Builds the working tree IN-PLACE (no worktree, no lock): the VS Code Java extension
# (jdt.ls) is disabled, so the old target/ contention workaround is unnecessary.
#
# Note: `mvn verify` stops at the first failing gate; fix it and re-run to reach the next.
#
# Usage: ./run-mvn-verify.sh [--skip-tests]
#   --skip-tests   add -DskipTests (fast: static gates + compile only, no test run)
#
# Output: reports/yyyymmddhhmmss-mvn-verify.md
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_REPO="$(cd "${SCRIPT_DIR}/../../lockable-resources-plugin" && pwd)"
MAVEN_BIN="${HOME}/.local/apache-maven-3.9.9/bin/mvn"
REPORTS_DIR="${SCRIPT_DIR}/reports"

SKIP_TESTS=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-tests) SKIP_TESTS=true; shift ;;
        *) echo "Unknown option: $1"; echo "Usage: $0 [--skip-tests]"; exit 1 ;;
    esac
done

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[✗]${NC} $*"; }

if [[ ! -x "$MAVEN_BIN" ]]; then
    log_error "Maven not found at: $MAVEN_BIN"
    exit 1
fi

mkdir -p "$REPORTS_DIR"
TS="$(date +%Y%m%d%H%M%S)"
REPORT_MD="${REPORTS_DIR}/${TS}-mvn-verify.md"
RAW_LOG="$(mktemp -t lrr-verify-XXXXXX.log)"

MVN_ARGS=(-B -ntp -Dstyle.color=never clean verify)
if [[ "$SKIP_TESTS" == "true" ]]; then
    MVN_ARGS+=(-DskipTests)
fi

HEAD_DESC="$(git -C "$PLUGIN_REPO" log -1 --format='%h %s' 2>/dev/null || echo 'n/a')"
DIRTY_COUNT="$(git -C "$PLUGIN_REPO" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$DIRTY_COUNT" -eq 0 ]]; then TREE_LABEL="clean"; else TREE_LABEL="dirty (${DIRTY_COUNT} files)"; fi

log_info "run-mvn-verify (CI-equivalent local gate)"
log_info "Plugin repo (in-place): $PLUGIN_REPO"
log_info "HEAD: ${HEAD_DESC}   working tree: ${TREE_LABEL}"
log_info "Command: mvn ${MVN_ARGS[*]}"
log_warn "Runs spotless/spotbugs/checkstyle/pmd${SKIP_TESTS:+ (tests skipped)}; may take 10-20 min."
echo ""

# From here, do not abort on non-zero: capture the result and always write the report.
set +e
START=$(date +%s)
cd "$PLUGIN_REPO"
"$MAVEN_BIN" "${MVN_ARGS[@]}" 2>&1 | tee "$RAW_LOG"
RC=${PIPESTATUS[0]}
END=$(date +%s)
DUR=$((END - START))

if [[ $RC -eq 0 ]]; then RESULT="SUCCESS"; else RESULT="FAILURE"; fi

TESTS_LINE="$(grep -E "Tests run: [0-9]+, Failures: [0-9]+, Errors: [0-9]+, Skipped: [0-9]+" "$RAW_LOG" | tail -1 | sed -E 's/^\[INFO\] *//')"
[[ -z "$TESTS_LINE" ]] && TESTS_LINE="(no test summary - tests skipped or not reached)"

gate_status() { # $1 = plugin artifactId fragment
    if grep -qE "Failed to execute goal .*${1}" "$RAW_LOG"; then echo "FAIL"; else echo "ok"; fi
}
SPOTLESS="$(gate_status 'spotless-maven-plugin')"
SPOTBUGS="$(gate_status 'spotbugs-maven-plugin')"
CHECKSTYLE="$(gate_status 'maven-checkstyle-plugin')"
PMD="$(gate_status 'maven-pmd-plugin')"

# Write the markdown report.
{
    echo "# mvn verify report (${TS})"
    echo ""
    echo "- Result: **BUILD ${RESULT}** (exit ${RC})"
    echo "- Duration: $(printf '%d:%02d' $((DUR / 60)) $((DUR % 60)))"
    echo "- Command: \`mvn ${MVN_ARGS[*]}\` (in-place)"
    echo "- Plugin repo: \`${PLUGIN_REPO}\`"
    echo "- HEAD: \`${HEAD_DESC}\`"
    echo "- Working tree: ${TREE_LABEL}"
    echo ""
    echo "## Quality gates"
    echo ""
    echo "| Gate | Status |"
    echo "|---|---|"
    echo "| spotless:check | ${SPOTLESS} |"
    echo "| spotbugs:check (effort=Max, threshold=Low) | ${SPOTBUGS} |"
    echo "| checkstyle:check | ${CHECKSTYLE} |"
    echo "| pmd:check | ${PMD} |"
    echo "| tests | ${TESTS_LINE} |"
    echo ""
    echo "> A gate shows \`ok\` when it did not fail the build. \`mvn verify\` stops at the"
    echo "> first failing gate, so gates after the failing one may simply not have run yet."
    echo ""
    if [[ $RC -ne 0 ]]; then
        echo "## Failing goal(s)"
        echo ""
        echo '```'
        grep -E "Failed to execute goal " "$RAW_LOG" | sed -E 's/^\[ERROR\] *//' | head -10
        echo '```'
        echo ""
        echo "## Error excerpt"
        echo ""
        echo '```'
        grep -E "^\[ERROR\]" "$RAW_LOG" | head -100
        echo '```'
        echo ""
    fi
    echo "<details><summary>Full mvn log</summary>"
    echo ""
    echo '```'
    cat "$RAW_LOG"
    echo '```'
    echo ""
    echo "</details>"
} > "$REPORT_MD"

rm -f "$RAW_LOG"

echo ""
echo "============================================"
if [[ $RC -eq 0 ]]; then
    log_success "mvn verify: BUILD SUCCESS"
else
    log_error "mvn verify: BUILD FAILURE (exit ${RC})"
    log_info "Gates - spotless:${SPOTLESS} spotbugs:${SPOTBUGS} checkstyle:${CHECKSTYLE} pmd:${PMD}"
fi
echo "============================================"
log_info "Duration: $(printf '%d:%02d' $((DUR / 60)) $((DUR % 60)))"
log_info "Tests: ${TESTS_LINE}"
log_info "Report: ${REPORT_MD}"

exit $RC
