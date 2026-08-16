#!/usr/bin/env bash
#
# union.sh - what none of the three layers reaches.
#
#   ./coverage/union.sh --unit <plugin>/target/jacoco.exec \
#                       --exec <reports>/…-coverage-e2e/exec \
#                       --exec <reports>/…-coverage-load-stress/exec
#
# Each layer on its own says how much it covers. Put together they answer the question worth asking:
# which code is held up by nothing at all. That is the shape of the gap that hid A6 and A7 - a green
# unit suite, a passing E2E run, and a branch neither of them ever took.
#
# A per-layer report cannot answer it. A line missed by the unit tests may well be covered by E2E;
# only the union tells you when the answer is nobody.
set -euo pipefail

COVERAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$COVERAGE_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

UNIT_EXEC=""
LAYER_DIRS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --unit) UNIT_EXEC="$2"; shift 2 ;;
    --exec) LAYER_DIRS+=("$2"); shift 2 ;;
    -h|--help) sed -n '2,15p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) err "Unknown option: $1"; exit 2 ;;
  esac
done

PLUGIN_DIR="${PLUGIN_DIR:-$SCRIPT_DIR/../../../lockable-resources-plugin}"
PLUGIN_DIR="$(cd "$PLUGIN_DIR" && pwd)"
CLASSES="$PLUGIN_DIR/target/classes"
SOURCES="$PLUGIN_DIR/src/main/java"
[[ -d "$CLASSES" ]] || { err "No compiled classes at $CLASSES"; exit 1; }

MVN="$HOME/.local/apache-maven-3.9.9/bin/mvn"
[[ -x "$MVN" ]] || MVN=mvn

RUN_ID="${COVERAGE_RUN_ID:-$(date '+%Y%m%d%H%M%S')}"
OUT_DIR="$SCRIPT_DIR/../reports/$RUN_ID-coverage-union"
POOL="$COVERAGE_DIR/target/union"
rm -rf "$POOL"; mkdir -p "$POOL" "$OUT_DIR"

n=0
if [[ -n "$UNIT_EXEC" ]]; then
  [[ -s "$UNIT_EXEC" ]] || { err "No unit exec at $UNIT_EXEC (run: mvn -P enable-jacoco verify)"; exit 1; }
  cp "$UNIT_EXEC" "$POOL/unit.exec"; n=$((n + 1))
  log "  unit  $UNIT_EXEC"
fi
for d in "${LAYER_DIRS[@]:-}"; do
  [[ -d "$d" ]] || { err "Not a directory: $d"; exit 1; }
  for f in "$d"/*.exec; do
    [[ -e "$f" ]] || continue
    cp "$f" "$POOL/$(basename "$(dirname "$d")")-$(basename "$f")"
    n=$((n + 1))
  done
  log "  layer $d"
done
[[ $n -gt 0 ]] || { err "Nothing to union."; exit 1; }

log "Reporting the union of $n exec file(s)"
"$MVN" -q -f "$COVERAGE_DIR/pom.xml" verify \
  -Dlrr.plugin.classes="$CLASSES" -Dlrr.plugin.sources="$SOURCES" \
  -Dlrr.exec.dir="$POOL" -Dlrr.report.dir="$OUT_DIR/site"

PLUGIN_SHA="$(git -C "$PLUGIN_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
python3 "$COVERAGE_DIR/summarize.py" "$OUT_DIR/site/jacoco.csv" "union of all layers" "$PLUGIN_SHA" > "$OUT_DIR.md"

log "Report:  $OUT_DIR.md"
log "Browse:  $OUT_DIR/site/index.html"
