#!/usr/bin/env bash
# Grid-storm load test harness (G01). See dev/docs-j/LOAD_TEST_SPECIFICATION.md.
# Reuses lib/common.sh. Separate from run-e2e.sh on purpose (metrics vs checkpoints).
set -euo pipefail

RUN_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RUN_SCRIPT_DIR/lib/common.sh"

# ---------------------------------------------------------------------------
# Defaults / presets
# ---------------------------------------------------------------------------
PRESET="smoke"
JOBS_PER_CONTROLLER=""
ITER=""
SLEEP_SEC=""
RLOCK_TO=""
LLOCK_TO=""
JOB_TO=""
ALLOW_SELF=false   # loopback (self as remote target) off by default for the load suite
SKIP_START=false
ONLY="grid-storm"
ORIGINAL_ARGS=("$@")

apply_preset() {
  case "$1" in
    smoke)    JOBS_PER_CONTROLLER=5;  ITER=1; SLEEP_SEC=10; RLOCK_TO=2; LLOCK_TO=2; JOB_TO=5 ;;
    converge) JOBS_PER_CONTROLLER=20; ITER=3; SLEEP_SEC=30; RLOCK_TO=3; LLOCK_TO=3; JOB_TO=15 ;;
    full)     JOBS_PER_CONTROLLER=50; ITER=3; SLEEP_SEC=30; RLOCK_TO=3; LLOCK_TO=3; JOB_TO=15 ;;
    stress)   JOBS_PER_CONTROLLER=50; ITER=3; SLEEP_SEC=60; RLOCK_TO=3; LLOCK_TO=3; JOB_TO=15 ;;
    *) err "Unknown preset: $1"; exit 2 ;;
  esac
}

usage() {
  cat <<'USAGE'
Usage: ./run-load.sh [options]
  --preset smoke|converge|full|stress   (default: smoke)
  --jobs-per-controller N
  --iterations N
  --sleep SEC
  --remote-timeout MIN
  --local-timeout MIN
  --job-timeout MIN
  --allow-loopback     remote target may be SELF (25% loopback; default: cross-controller only)
  --skip-start
  -h, --help
USAGE
}

apply_preset "$PRESET"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --preset) PRESET="${2:?}"; apply_preset "$PRESET"; shift 2 ;;
    --jobs-per-controller) JOBS_PER_CONTROLLER="${2:?}"; shift 2 ;;
    --iterations) ITER="${2:?}"; shift 2 ;;
    --sleep) SLEEP_SEC="${2:?}"; shift 2 ;;
    --remote-timeout) RLOCK_TO="${2:?}"; shift 2 ;;
    --local-timeout) LLOCK_TO="${2:?}"; shift 2 ;;
    --job-timeout) JOB_TO="${2:?}"; shift 2 ;;
    --allow-loopback) ALLOW_SELF=true; shift ;;
    --skip-start) SKIP_START=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown option: $1"; usage; exit 2 ;;
  esac
done

require_command curl
require_command docker
require_command python3

RUN_ID="$(date '+%Y%m%d%H%M%S')"
REPORTS_ROOT="$RUN_SCRIPT_DIR/../reports"
REPORT_NAME="$RUN_ID-load-test"
RESULTS_DIR="$REPORTS_ROOT/$REPORT_NAME/grid-storm"
CONSOLES_DIR="$RESULTS_DIR/consoles"
REPORT_FILE="$REPORTS_ROOT/$REPORT_NAME.md"
EVENTS_FILE="$RESULTS_DIR/events.csv"
mkdir -p "$CONSOLES_DIR"

CONTROLLERS=(a b c d)
declare -A CTRL_URL=(
  [a]="$CONTROLLER_A_URL" [b]="$CONTROLLER_B_URL" [c]="$CONTROLLER_C_URL" [d]="$CONTROLLER_D_URL")
declare -A CTRL_INTERNAL=(
  [a]="$CONTROLLER_A_INTERNAL_URL" [b]="$CONTROLLER_B_INTERNAL_URL"
  [c]="$CONTROLLER_C_INTERNAL_URL" [d]="$CONTROLLER_D_INTERNAL_URL")

EXPOSE_LABEL="remote-enabled"
POOL_LABEL="pool"
N_RESOURCES=50
N_EXPOSED=40
JOB_NAME="grid-storm"

log "Load run id: $RUN_ID  preset=$PRESET jobs/ctrl=$JOBS_PER_CONTROLLER iter=$ITER sleep=${SLEEP_SEC}s loopback=$ALLOW_SELF"
log "Results dir: $RESULTS_DIR"

if [[ "$SKIP_START" == false ]]; then
  log "Assuming controllers already started (use start.sh separately). Proceeding to readiness check."
fi
if ! wait_for_controllers_with_d 240; then
  err "Controllers a/b/c/d not all ready"; exit 10
fi

# ---------------------------------------------------------------------------
# 1. Per-controller server config: remote API + 50 resources + executors
# ---------------------------------------------------------------------------
configure_load_server() {
  local id="$1" base="$2"
  log "[$id] configure remote server + $N_RESOURCES resources + executors=$JOBS_PER_CONTROLLER"
  run_groovy_script_checked "$base" "
import jenkins.model.Jenkins
import hudson.security.FullControlOnceLoggedInAuthorizationStrategy
import hudson.security.HudsonPrivateSecurityRealm
import hudson.security.csrf.DefaultCrumbIssuer
import org.jenkins.plugins.lockableresources.LockableResourcesManager

def j = Jenkins.get()
if (!(j.getSecurityRealm() instanceof HudsonPrivateSecurityRealm)) {
  def realm = new HudsonPrivateSecurityRealm(false)
  realm.createAccount('admin','admin')
  j.setSecurityRealm(realm)
}
def strat = new FullControlOnceLoggedInAuthorizationStrategy()
strat.setAllowAnonymousRead(false)
j.setAuthorizationStrategy(strat)
j.setCrumbIssuer(new DefaultCrumbIssuer(false))
j.setNumExecutors(${JOBS_PER_CONTROLLER})

def lrm = LockableResourcesManager.get()
lrm.setRemoteApiEnabled(true)
lrm.setExposeLabel('${EXPOSE_LABEL}')
for (int k = 1; k <= ${N_RESOURCES}; k++) {
  def name = sprintf('${id}-res-%02d', k)
  def labels = (k <= ${N_EXPOSED}) ? '${EXPOSE_LABEL} ${POOL_LABEL}' : '${POOL_LABEL}'
  def r = lrm.fromName(name)
  if (r == null) { lrm.createResourceWithLabel(name, labels) }
  else { r.setLabels(labels) }
}
lrm.save(); j.save()
println('OK: load server ${id} configured')
" "OK: load server ${id} configured" >/dev/null
}

# ---------------------------------------------------------------------------
# 2. Mutual client wiring: each controller gets creds + remote for ALL 4 ids
#    (self included → enables server-self-use targeting)
# ---------------------------------------------------------------------------
declare -A TOKEN
issue_tokens() {
  for id in "${CONTROLLERS[@]}"; do
    TOKEN[$id]="$(issue_user_api_token "${CTRL_URL[$id]}" "admin" "load-${id}-token-$RUN_ID")"
    [[ -n "${TOKEN[$id]}" ]] || { err "token issue failed for $id"; exit 1; }
  done
}

wire_clients() {
  local id base
  for id in "${CONTROLLERS[@]}"; do
    base="${CTRL_URL[$id]}"
    for srv in "${CONTROLLERS[@]}"; do
      local cred="load-${srv}-token"
      upsert_username_password_credential "$base" "$cred" "admin" "${TOKEN[$srv]}"
      configure_remote_client_for_server "$base" "$id" "$srv" "${CTRL_INTERNAL[$srv]}" "$cred"
    done
    log "[$id] wired remotes -> a,b,c,d (self included)"
  done
}

# ---------------------------------------------------------------------------
# 3. Inject grid-storm job (sandbox=false) per controller with config header
# ---------------------------------------------------------------------------
inject_job() {
  local id="$1" base="$2"
  local header="SELF='${id}'; SERVERS=['a','b','c','d']; ALLOW_SELF=${ALLOW_SELF}; ITER=${ITER}; SLEEP=${SLEEP_SEC}; RLOCK_TO=${RLOCK_TO}; LLOCK_TO=${LLOCK_TO}; JOB_TO=${JOB_TO}"
  local body; body="$(cat "$RUN_SCRIPT_DIR/load/Jenkinsfile.grid")"
  local script="$header"$'\n'"$body"
  local b64; b64="$(printf '%s' "$script" | base64 | tr -d '\n')"
  run_groovy_script_checked "$base" "
import jenkins.model.Jenkins
import hudson.model.ParametersDefinitionProperty
import hudson.model.StringParameterDefinition
import org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition
import org.jenkinsci.plugins.workflow.job.WorkflowJob
import org.jenkinsci.plugins.scriptsecurity.scripts.ScriptApproval
import org.jenkinsci.plugins.scriptsecurity.scripts.languages.GroovyLanguage

def j = Jenkins.get()
def script = new String('${b64}'.decodeBase64(), 'UTF-8')
WorkflowJob job = j.getItem('${JOB_NAME}')
if (job == null) { job = j.createProject(WorkflowJob.class, '${JOB_NAME}') }
job.setConcurrentBuild(true)
// STORM_IDX makes each trigger a distinct queue item (defeats queue coalescing)
job.removeProperty(ParametersDefinitionProperty.class)
job.addProperty(new ParametersDefinitionProperty(new StringParameterDefinition('STORM_IDX','0')))
job.setDefinition(new CpsFlowDefinition(script, false))
job.save()
// sandbox=false scripts require approval; preapprove this exact script text
ScriptApproval.get().preapprove(script, GroovyLanguage.get())
println('OK: grid-storm injected on ${id}')
" "OK: grid-storm injected on ${id}" >/dev/null
}

# Trigger with a unique STORM_IDX so queue items are not coalesced. Echoes queue URL.
trigger_job_idx() {
  local base="$1" job="$2" idx="$3"
  local cookie_jar headers_file crumb_header location
  cookie_jar="$(mktemp)"; headers_file="$(mktemp)"
  crumb_header="$(get_crumb_header "$base" "$cookie_jar")"
  if [[ -n "$crumb_header" ]]; then
    curl -sS -u "$JENKINS_USER:$JENKINS_PASSWORD" -b "$cookie_jar" -X POST -H "$crumb_header" \
      -D "$headers_file" -o /dev/null "$base/job/$job/buildWithParameters?STORM_IDX=$idx"
  else
    curl -sS -u "$JENKINS_USER:$JENKINS_PASSWORD" -b "$cookie_jar" -X POST \
      -D "$headers_file" -o /dev/null "$base/job/$job/buildWithParameters?STORM_IDX=$idx"
  fi
  location="$(awk 'BEGIN{IGNORECASE=1} /^Location:/{print $2}' "$headers_file" | tr -d '\r' | tail -n 1)"
  rm -f "$cookie_jar" "$headers_file"
  [[ -n "$location" ]] || { err "trigger_job_idx: no queue Location ($job idx=$idx)"; return 1; }
  printf '%s\n' "$location"
}

# ---------------------------------------------------------------------------
# Run setup
# ---------------------------------------------------------------------------
for id in "${CONTROLLERS[@]}"; do configure_load_server "$id" "${CTRL_URL[$id]}"; done
issue_tokens
wire_clients
for id in "${CONTROLLERS[@]}"; do inject_job "$id" "${CTRL_URL[$id]}"; done

# ---------------------------------------------------------------------------
# 3b. Start docker stats sampler (network/CPU/mem load over the run)
# ---------------------------------------------------------------------------
NETSTATS_FILE="$RESULTS_DIR/netstats.csv"
SAMPLE_INTERVAL=3
SAMPLER_FLAG="$(mktemp)"
echo "epochMs,name,cpu,mem,net,block" >"$NETSTATS_FILE"
sample_docker_stats() {
  while [[ -f "$SAMPLER_FLAG" ]]; do
    local ts; ts="$(date +%s%3N)"
    docker stats --no-stream \
      --format '{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}|{{.NetIO}}|{{.BlockIO}}' 2>/dev/null \
      | grep lrr | while IFS='|' read -r nm cpu mem net blk; do
          echo "$ts,$nm,$cpu,$mem,$net,$blk" >>"$NETSTATS_FILE"
        done
    sleep "$SAMPLE_INTERVAL"
  done
}
sample_docker_stats & SAMPLER_PID=$!
log "docker stats sampler started (pid=$SAMPLER_PID, every ${SAMPLE_INTERVAL}s) -> netstats.csv"

# ---------------------------------------------------------------------------
# 4. Trigger JOBS_PER_CONTROLLER concurrent builds on each controller
# ---------------------------------------------------------------------------
QUEUE_URLS=()
log "Triggering $JOBS_PER_CONTROLLER builds x ${#CONTROLLERS[@]} controllers"
for id in "${CONTROLLERS[@]}"; do
  base="${CTRL_URL[$id]}"
  for ((n=1; n<=JOBS_PER_CONTROLLER; n++)); do
    qurl="$(trigger_job_idx "$base" "$JOB_NAME" "${id}${n}")" || { err "[$id] trigger failed"; continue; }
    QUEUE_URLS+=("$id|$base|$qurl")
  done
done
log "Triggered ${#QUEUE_URLS[@]} builds total"

# ---------------------------------------------------------------------------
# 5. Resolve build URLs and wait for completion
# ---------------------------------------------------------------------------
BUILD_URLS=()
for entry in "${QUEUE_URLS[@]}"; do
  IFS='|' read -r id base qurl <<<"$entry"
  if burl="$(wait_for_queue_executable "$qurl" 180 2>/dev/null)"; then
    BUILD_URLS+=("$id|$base|$burl")
  else
    err "[$id] queue did not become executable: $qurl"
  fi
done
log "Resolved ${#BUILD_URLS[@]} build URLs; waiting for completion"

# job wall budget + margin
WAIT_BUDGET=$(( JOB_TO * 60 + 120 ))
declare -A RESULTS
for entry in "${BUILD_URLS[@]}"; do
  IFS='|' read -r id base burl <<<"$entry"
  res="$(wait_for_build_result "$burl" "$WAIT_BUDGET" 2>/dev/null || echo "UNKNOWN")"
  RESULTS["$burl"]="$id|$res"
done

# stop docker stats sampler
rm -f "$SAMPLER_FLAG"
wait "$SAMPLER_PID" 2>/dev/null || true
log "docker stats sampler stopped ($(($(wc -l <"$NETSTATS_FILE") - 1)) samples)"

# ---------------------------------------------------------------------------
# 6. Collect consoles + extract LLT events
# ---------------------------------------------------------------------------
log "Collecting consoles and LLT events"
: >"$EVENTS_FILE"
echo "epochMs,jobUid,self,iter,phase,event,target,resources" >>"$EVENTS_FILE"
for entry in "${BUILD_URLS[@]}"; do
  IFS='|' read -r id base burl <<<"$entry"
  bn="$(basename "$(dirname "$burl")")_$(basename "$burl")"
  cfile="$CONSOLES_DIR/${id}-${bn}.txt"
  save_console_log "$burl" "$cfile" 2>/dev/null || true
  # resources may hold multiple names ("r1,r2"); use ';' inside the CSV cell to keep columns aligned
  grep '^LLT|' "$cfile" 2>/dev/null | while IFS='|' read -r _ ms uid self it ph ev tg rs; do
    printf '%s,%s,%s,%s,%s,%s,%s,%s\n' "$ms" "$uid" "$self" "$it" "$ph" "$ev" "$tg" "${rs//,/;}"
  done >>"$EVENTS_FILE" || true
done

# build result summary file
SUMMARY_FILE="$RESULTS_DIR/job-results.csv"
: >"$SUMMARY_FILE"
echo "buildUrl,controller,result" >>"$SUMMARY_FILE"
for burl in "${!RESULTS[@]}"; do
  IFS='|' read -r id res <<<"${RESULTS[$burl]}"
  echo "$burl,$id,$res" >>"$SUMMARY_FILE"
done

# ---------------------------------------------------------------------------
# 7. Analyze + report
# ---------------------------------------------------------------------------
log "Analyzing"
# Prefer the venv python (has matplotlib for PNG plots) if it exists
PY="python3"
if [[ -x "$RUN_SCRIPT_DIR/../.venv/bin/python" ]]; then PY="$RUN_SCRIPT_DIR/../.venv/bin/python"; fi
PLUGIN_COMMIT="$(git -C "$RUN_SCRIPT_DIR/../../../lockable-resources-plugin" rev-parse --short HEAD 2>/dev/null || echo unknown)"
"$PY" "$RUN_SCRIPT_DIR/lib/analyze_load.py" \
  --events "$EVENTS_FILE" \
  --results "$SUMMARY_FILE" \
  --netstats "$NETSTATS_FILE" \
  --capacity-exposed "$N_EXPOSED" \
  --out-metrics "$RESULTS_DIR/metrics.json" \
  --out-overlaps "$RESULTS_DIR/overlaps.txt" \
  --out-classification "$RESULTS_DIR/job-classification.csv" \
  --report "$REPORT_FILE" \
  --run-id "$RUN_ID" --preset "$PRESET" \
  --jobs-per-controller "$JOBS_PER_CONTROLLER" --iter "$ITER" \
  --sleep "$SLEEP_SEC" --remote-timeout "$RLOCK_TO" --local-timeout "$LLOCK_TO" \
  --job-timeout "$JOB_TO" --loopback "$ALLOW_SELF" --plugin-commit "$PLUGIN_COMMIT" || {
    err "analysis failed"; exit 1; }

log "Report: $REPORT_FILE"
log "Load harness finished"
