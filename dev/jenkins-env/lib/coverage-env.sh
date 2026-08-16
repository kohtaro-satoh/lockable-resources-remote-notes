# Sourced by start.sh and by lib/common.sh. Sets LRR_JAVA_OPTS when coverage is on, and nothing else.
#
# It lives in its own file because both need it and neither should have to source the other: start.sh
# does not want common.sh's functions, and common.sh runs inside every scenario.
#
# Why it has to be shared at all: compose builds a container's environment fresh each time, so a
# scenario that restarts a controller (catalog-cache-ttl stops jenkins-b on purpose) would otherwise
# bring it back without the agent. Nothing would fail - the suite still passes, and the report simply
# stops seeing that controller.
#
# The options, one by one:
#   destfile   inside the bind-mounted home, so the host can read it without docker cp
#   output=file  the agent writes from a JVM shutdown hook; see stop_grace_period in the compose file
#   append=true  a controller may be restarted mid-suite, and each session has to add to the last
#   includes     without it the agent instruments Jenkins core: a far larger exec file, a slower run,
#                and a report in which the plugin is a rounding error

if [[ "${LRR_COVERAGE:-false}" == true && -z "${LRR_JAVA_OPTS:-}" ]]; then
  export LRR_JAVA_OPTS="-Djenkins.install.runSetupWizard=false -javaagent:/opt/jacoco/jacocoagent.jar=destfile=/var/jenkins_home/jacoco.exec,output=file,append=true,includes=org.jenkins.plugins.lockableresources.*"
fi
