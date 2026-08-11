#!/usr/bin/env bash
set -euo pipefail

# S16: a resource's properties reach the remote body as environment variables.
#
# Properties are how a lockable resource carries the thing the build actually needs - the address of
# the board, the port of the device. Locally lock(variable: 'V') publishes them as V0_<PROP>. If the
# remote path locks the resource but drops its properties, the build holds the right hardware and has
# no way to reach it, so the assertion is on the value arriving intact, not on the variable existing.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "S16" "remote-resource-properties" "${1:-}"

STAMP="$(scenario_stamp)"
RES="s16-board-$STAMP"
PROP_VALUE="10.9.8.${STAMP: -2}"

scenario_step "Expose a resource on B carrying property S16_IP=$PROP_VALUE, and link A"
setup_remote_pair "s16" "a" "b" "$RES"
run_groovy_script_checked "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager
import org.jenkins.plugins.lockableresources.LockableResourceProperty

def lrm = LockableResourcesManager.get()
def r = lrm.fromName('${RES}')
def p = new LockableResourceProperty()
p.setName('S16_IP')
p.setValue('${PROP_VALUE}')
r.setProperties([p])
lrm.save()
println('PROP_SET=' + r.getProperties().size())
" "PROP_SET=" >/dev/null

PIPELINE_SCRIPT="$(cat <<EOF
node {
  lock(resource: '$RES', variable: 'S16RES', serverId: 'b') {
    echo "S16_BODY_START"
    echo "S16RES=\${env.S16RES}"
    echo "S16RES0=\${env.S16RES0}"
    echo "S16RES0_S16_IP=\${env.S16RES0_S16_IP}"
    echo "S16_BODY_END"
  }
}
EOF
)"

scenario_step "Lock it remotely and read the property back inside the body"
upsert_pipeline_job "$CONTROLLER_A_URL" "s16-props" "$PIPELINE_SCRIPT"
build_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "s16-props" 120)"
result="$(wait_for_build_result "$build_url" 600)"
save_console_log "$build_url" "$SCENARIO_DIR/console.txt"
scenario_artifact "console" "$SCENARIO_DIR/console.txt"

combined="$(console_value "$SCENARIO_DIR/console.txt" S16RES)"
indexed="$(console_value "$SCENARIO_DIR/console.txt" S16RES0)"
property="$(console_value "$SCENARIO_DIR/console.txt" S16RES0_S16_IP)"

scenario_check "Build result" "Build API" "SUCCESS" "$result"
scenario_check "Combined variable names the resource" "lockEnvVars S16RES" "$RES" "$combined"
scenario_check "Indexed variable names the resource" "lockEnvVars S16RES0" "$RES" "$indexed"
scenario_check "Property arrived with its value intact" "lockEnvVars S16RES0_S16_IP" "$PROP_VALUE" "$property"
scenario_check_contains "Went over the remote path" "$SCENARIO_DIR/console.txt" "Remote lock acquired on"
scenario_check_resource_free "Resource released on B" "b" "$RES"

scenario_fact "build_url" "$build_url"
scenario_fact "result" "$result"
scenario_fact "property_value_on_server" "$PROP_VALUE"
scenario_fact "property_value_in_body" "$property"

scenario_finish
