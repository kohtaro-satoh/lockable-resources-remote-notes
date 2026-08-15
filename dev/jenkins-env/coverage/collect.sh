#!/usr/bin/env bash
#
# collect.sh - turn a coverage run into a report.
#
#   PLUGIN_DIR=../../../lockable-resources-plugin ./start.sh --clean --coverage
#   PLUGIN_DIR=../../../lockable-resources-plugin ./run-e2e.sh
#   ./coverage/collect.sh --label e2e
#
# The agent writes its exec file when the JVM exits, so this stops the controllers first. That is
# not a tidiness step: skip it and the file on disk is whatever the last graceful shutdown left,
# which for a fresh run is nothing at all.
set -euo pipefail

COVERAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$COVERAGE_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

LABEL="run"
KEEP_RUNNING=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --label) LABEL="$2"; shift 2 ;;
    --keep-running) KEEP_RUNNING=true; shift ;;
    -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) err "Unknown option: $1"; exit 2 ;;
  esac
done

PLUGIN_DIR="${PLUGIN_DIR:-$SCRIPT_DIR/../../../lockable-resources-plugin}"
PLUGIN_DIR="$(cd "$PLUGIN_DIR" && pwd)"
CLASSES="$PLUGIN_DIR/target/classes"
SOURCES="$PLUGIN_DIR/src/main/java"

if [[ ! -d "$CLASSES" ]]; then
  err "No compiled classes at $CLASSES."
  err "The report matches probes against bytecode, so the plugin must have been built:"
  err "  (cd $PLUGIN_DIR && mvn -DskipTests package)"
  exit 1
fi

MVN="$HOME/.local/apache-maven-3.9.9/bin/mvn"
[[ -x "$MVN" ]] || MVN=mvn

RUN_ID="${COVERAGE_RUN_ID:-$(date '+%Y%m%d%H%M%S')}"
OUT_DIR="$SCRIPT_DIR/../reports/$RUN_ID-coverage-$LABEL"
EXEC_DIR="$COVERAGE_DIR/target/exec"
rm -rf "$EXEC_DIR" "$COVERAGE_DIR/target/merged.exec" "$COVERAGE_DIR/target/site"
mkdir -p "$EXEC_DIR" "$OUT_DIR"

if ! $KEEP_RUNNING; then
  log "Stopping the controllers so the agent flushes its exec file"
  (cd "$SCRIPT_DIR" && docker compose stop) >/dev/null 2>&1 || true
fi

found=0
for k in a b c d; do
  src="$SCRIPT_DIR/jh$k/jacoco.exec"
  if [[ -s "$src" ]]; then
    cp "$src" "$EXEC_DIR/$k.exec"
    log "  jh$k/jacoco.exec  $(du -h "$src" | cut -f1)"
    found=$((found + 1))
  else
    log "  jh$k/jacoco.exec  (absent - was this run started with --coverage?)"
  fi
done

if [[ $found -eq 0 ]]; then
  err "No exec files. Start the environment with --coverage before running a suite."
  exit 1
fi

log "Merging $found controller(s) and reporting against $PLUGIN_DIR"
"$MVN" -q -f "$COVERAGE_DIR/pom.xml" verify \
  -Dlrr.plugin.classes="$CLASSES" \
  -Dlrr.plugin.sources="$SOURCES" \
  -Dlrr.exec.dir="$EXEC_DIR" \
  -Dlrr.report.dir="$OUT_DIR/site"

CSV="$OUT_DIR/site/jacoco.csv"
[[ -f "$CSV" ]] || { err "No jacoco.csv produced at $CSV"; exit 1; }

PLUGIN_SHA="$(git -C "$PLUGIN_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
python3 "$COVERAGE_DIR/summarize.py" "$CSV" "$LABEL" "$PLUGIN_SHA" > "$OUT_DIR.md"

log "Report:  $OUT_DIR.md"
log "Browse:  $OUT_DIR/site/index.html"
