#!/usr/bin/env bash
set -euo pipefail

# B03: resource names that stress the encodings they pass through.
#
# A name written on a server travels a long way to reach a build on a client: into a JSON body, out
# of a JSON parser, into an environment variable, into a shell. Every scenario so far uses names
# that survive all of those trivially - lowercase, hyphens, digits - so nothing checks the encoding
# at all. These do not: a space, a multibyte character, a name long enough to be truncated
# somewhere, and a comma.
#
# The comma is the one that matters, and it is not an encoding question. lock(variable: 'V') sets V
# to the locked names joined by commas, which is unambiguous only while no name contains one. A
# single resource called "a,b" produces exactly the V that two resources "a" and "b" would, so a
# pipeline doing V.split(',') gets two names that do not exist. The indexed V0, V1... form has no
# such problem, which is what makes it the right thing to recommend - and this scenario measures the
# ambiguity rather than asserting it away, because the current behaviour is not a bug the plugin has
# chosen to fix.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

scenario_init "B03" "resource-name-boundaries" "${1:-}"

STAMP="$(scenario_stamp)"
PLAIN="b03-plain-$STAMP"
SPACED="b03 spaced $STAMP"
MULTIBYTE="b03-日本語-リソース-$STAMP"
COMMA="b03-comma,inside-$STAMP"
# Long enough to catch a column or buffer that was sized for "a reasonable name".
LONG="b03-$(printf 'x%.0s' $(seq 1 240))-$STAMP"

ALL_NAMES=("$PLAIN" "$SPACED" "$MULTIBYTE" "$COMMA" "$LONG")

scenario_cleanup_hook drop_resources "b" "${ALL_NAMES[@]}"

scenario_step "Create the awkwardly named resources on B and link A"
setup_remote_pair "b03" "a" "b" "$PLAIN"

# createResourceWithLabel through a triple-quoted Groovy string: the names contain characters that
# would otherwise need escaping at three levels (bash, the Groovy literal, and the name itself).
create_named_resource() {
  local name="$1"
  run_groovy_script_checked "$CONTROLLER_B_URL" "
import org.jenkins.plugins.lockableresources.LockableResourcesManager

def lrm = LockableResourcesManager.get()
def name = \"\"\"$name\"\"\"
if (lrm.fromName(name) == null) {
  lrm.createResourceWithLabel(name, 'remote-enabled')
}
lrm.save()
println('CREATED=' + (lrm.fromName(name) != null))
" "CREATED=true" >/dev/null
}

for name in "$SPACED" "$MULTIBYTE" "$COMMA" "$LONG"; do
  create_named_resource "$name"
done

# lock_and_read <case> <resource-name> - runs a real pipeline so the name is checked where it
# actually lands: in the build's environment, not just in the JSON on the wire.
lock_and_read() {
  local case_name="$1"
  local name="$2"
  local job="b03-$case_name"
  local console="$SCENARIO_DIR/$case_name-console.txt"

  upsert_pipeline_job "$CONTROLLER_A_URL" "$job" "$(cat <<EOF
node {
  lock(resource: '''$name''', variable: 'B03RES', serverId: 'b') {
    echo "B03_V=\${env.B03RES}"
    echo "B03_V0=\${env.B03RES0}"
  }
}
EOF
)"

  local build_url result
  build_url="$(trigger_and_resolve_build_url "$CONTROLLER_A_URL" "$job" 120)"
  result="$(wait_for_build_result "$build_url" 300)" || result="TIMEOUT"
  save_console_log "$build_url" "$console"
  scenario_artifact "$case_name console" "$console"

  LAST_V="$(console_value "$console" B03_V)"
  LAST_V0="$(console_value "$console" B03_V0)"
  LAST_RESULT="$result"
}

scenario_step "A name containing a space"
lock_and_read "spaced" "$SPACED"
scenario_check "spaced: build result" "Build API" "SUCCESS" "$LAST_RESULT"
scenario_check "spaced: the name survives the round trip" "lockEnvVars B03RES0" "$SPACED" "$LAST_V0"
scenario_check_resource_free "spaced: released" "b" "$SPACED"

scenario_step "A name in a non-Latin script"
lock_and_read "multibyte" "$MULTIBYTE"
scenario_check "multibyte: build result" "Build API" "SUCCESS" "$LAST_RESULT"
# JSON carries this as \uXXXX escapes; what matters is what the build ends up with.
scenario_check "multibyte: the name survives the round trip" "lockEnvVars B03RES0" "$MULTIBYTE" "$LAST_V0"
scenario_check_resource_free "multibyte: released" "b" "$MULTIBYTE"

scenario_step "A ${#LONG}-character name"
lock_and_read "long" "$LONG"
scenario_check "long: build result" "Build API" "SUCCESS" "$LAST_RESULT"
scenario_check "long: the name is not truncated" "lockEnvVars B03RES0" "$LONG" "$LAST_V0"
scenario_check_resource_free "long: released" "b" "$LONG"

scenario_step "A name containing the separator the combined variable uses"
lock_and_read "comma" "$COMMA"
scenario_check "comma: build result" "Build API" "SUCCESS" "$LAST_RESULT"
scenario_check "comma: the indexed variable is exact" "lockEnvVars B03RES0" "$COMMA" "$LAST_V0"

# One resource was locked. Splitting the combined variable on its documented separator should
# therefore yield one name; it yields two, and neither of them exists.
parts="$(printf '%s' "$LAST_V" | awk -F, '{print NF}')"
scenario_observe "comma: splitting the combined variable" \
  "B03RES split on ','" \
  "$parts parts from 1 locked resource (V=$LAST_V)"
scenario_check_resource_free "comma: released" "b" "$COMMA"

scenario_step "Check the awkward names did not disturb the catalogue"
# A name that breaks the JSON encoder would take the whole listing with it, not just its own entry.
TOKEN_B="$(issue_user_api_token "$CONTROLLER_B_URL" "admin" "e2e-b03-token")"
code="$(api_resources "b" "$TOKEN_B" "$SCENARIO_DIR/resources.json")"
scenario_artifact "catalogue" "$SCENARIO_DIR/resources.json"
scenario_check "The catalogue still serves" "GET /resources" "200" "$code"
scenario_check_contains "and lists the multibyte name" "$SCENARIO_DIR/resources.json" "$(printf '%s' "$MULTIBYTE" | sed 's/.*/&/')"

scenario_fact "spaced_name" "$SPACED"
scenario_fact "multibyte_name" "$MULTIBYTE"
scenario_fact "comma_name" "$COMMA"
scenario_fact "comma_combined_variable" "$LAST_V"
scenario_fact "long_name_length" "${#LONG}"

scenario_finish
