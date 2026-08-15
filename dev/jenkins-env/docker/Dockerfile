FROM jenkins/jenkins:lts-jdk21

# Install dependency plugins at image build time
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Install the locally built lockable-resources plugin
# (built by start.sh before docker compose build is invoked)
COPY lockable-resources.hpi /usr/share/jenkins/ref/plugins/lockable-resources.hpi

# Dev init scripts (create admin user, disable setup wizard)
COPY init.groovy.d/ /usr/share/jenkins/ref/init.groovy.d/

# The JaCoCo agent, inert unless JAVA_OPTS names it (see start.sh --coverage). It is baked in
# rather than mounted so that a coverage run needs no change to the compose file, and it is off by
# default because instrumentation would distort what the load test measures.
COPY jacocoagent.jar /opt/jacoco/jacocoagent.jar

# Disable the setup wizard. Overridable so a coverage run can add -javaagent.
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"

# Serve under /jenkins/ to match hpi:run default
ENV JENKINS_OPTS="--prefix=/jenkins"
