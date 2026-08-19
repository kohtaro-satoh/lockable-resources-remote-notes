# Windows container unit test report (20260819160127)

- Result: **PASS** (exit 0)
- Duration: 2m15s
- Revision requested: `bdca858`
- Revision tested: `bdca858ec712ad7304252bce1dc2a64c6adb2cd5 2026-08-14 19:28:21 +0900 [B7] Annotate the remote resources endpoint with GET`
- Test pattern: `LockStepWithRestartTest`  (repeat 1)
- Image: `lrr-win-test:ltsc2022-jdk21` (`3f7c2a589530`), hyperv isolation, memory 8g, cpus 6
- Harness (notes): `bd60a84 + local changes`
- Raw artifacts: `20260819160127-windows-unittest/`

## Runs

| Run | Verdict | Tests | Failures | Errors | Skipped |
|---|---|---|---|---|---|
| run-1 | PASS | 5 | 0 | 0 | 0 |

## Logs

<details><summary>mvn log (run-1)</summary>


```
[INFO] Scanning for projects...
[INFO] Artifact org.jenkins-ci.tools:maven-hpi-plugin:pom:3.1814.v77d15159f9b_d is present in the local repository, but cached from a remote repository ID that is unavailable in current build context, verifying that is downloadable from [incrementals (https://repo.jenkins-ci.org/incrementals/, default, releases), central (https://repo.maven.apache.org/maven2, default, releases)]
[INFO] Artifact org.jenkins-ci.tools:maven-hpi-plugin:pom:3.1814.v77d15159f9b_d is present in the local repository, but cached from a remote repository ID that is unavailable in current build context, verifying that is downloadable from [incrementals (https://repo.jenkins-ci.org/incrementals/, default, releases), central (https://repo.maven.apache.org/maven2, default, releases)]
[WARNING] The POM for org.jenkins-ci.tools:maven-hpi-plugin:jar:3.1814.v77d15159f9b_d is missing, no dependency information available
[INFO] Artifact org.jenkins-ci.tools:maven-hpi-plugin:jar:3.1814.v77d15159f9b_d is present in the local repository, but cached from a remote repository ID that is unavailable in current build context, verifying that is downloadable from [incrementals (https://repo.jenkins-ci.org/incrementals/, default, releases), central (https://repo.maven.apache.org/maven2, default, releases)]
[INFO] Artifact org.jenkins-ci.tools:maven-hpi-plugin:jar:3.1814.v77d15159f9b_d is present in the local repository, but cached from a remote repository ID that is unavailable in current build context, verifying that is downloadable from [incrementals (https://repo.jenkins-ci.org/incrementals/, default, releases), central (https://repo.maven.apache.org/maven2, default, releases)]
[WARNING] Failed to build parent project for org.6wind.jenkins:lockable-resources:hpi:999999-SNAPSHOT
[INFO] 
[INFO] ----------------< org.6wind.jenkins:lockable-resources >----------------
[INFO] Building Lockable Resources plugin 999999-SNAPSHOT
[INFO]   from pom.xml
[INFO] --------------------------------[ hpi ]---------------------------------
[INFO] 
[INFO] --- hpi:3.1814.v77d15159f9b_d:validate (default-validate) @ lockable-resources ---
[INFO] Created marker file C:\src\lrp\target\java-level\17
[INFO] 
[INFO] --- hpi:3.1814.v77d15159f9b_d:validate-hpi (default-validate-hpi) @ lockable-resources ---
[INFO] 
[INFO] --- enforcer:3.6.3:enforce (display-info) @ lockable-resources ---
[INFO] Rule 0: org.apache.maven.enforcer.rules.version.RequireMavenVersion passed
[INFO] Rule 1: org.apache.maven.enforcer.rules.version.RequireJavaVersion passed
[INFO] Rule 2: org.apache.maven.enforcer.rules.version.RequireJavaVersion passed
[INFO] Rule 3: org.apache.maven.enforcer.rules.RequirePluginVersions passed
[INFO] Rule 4: org.codehaus.mojo.extraenforcer.dependencies.EnforceBytecodeVersion passed
[INFO] Rule 5: org.apache.maven.enforcer.rules.dependency.BannedDependencies passed
[INFO] Rule 6: org.apache.maven.enforcer.rules.dependency.BannedDependencies passed
[INFO] Ignoring requireUpperBoundDeps in org.ow2.asm:asm
[INFO] Rule 7: org.apache.maven.enforcer.rules.dependency.RequireUpperBoundDeps passed
[INFO] banObsoleteDependencyOverrides skipped
[INFO] Rule 8: io.jenkins.tools.maven.jenkins_enforcer_rules.BanObsoleteDependencyOverrides passed
[INFO] 
[INFO] --- enforcer:3.6.3:enforce (no-snapshots-in-release) @ lockable-resources ---
[INFO] Rule 0: org.apache.maven.enforcer.rules.dependency.RequireReleaseDeps passed
[INFO] 
[INFO] --- localizer:1.31:generate (default) @ lockable-resources ---
[INFO] 
[INFO] --- enforcer:3.6.3:enforce (check-junit-imports) @ lockable-resources ---
[INFO] Rule 0: org.apache.maven.plugins.enforcer.RestrictImports passed
[INFO] 
[INFO] --- enforcer:3.6.3:enforce (check-commons-lang-imports) @ lockable-resources ---
[INFO] Skipping Rule Enforcement.
[INFO] 
[INFO] --- enforcer:3.6.3:enforce (check-deprecated-stapler-imports) @ lockable-resources ---
[INFO] Skipping Rule Enforcement.
[INFO] 
[INFO] --- resources:3.5.0:resources (default-resources) @ lockable-resources ---
[INFO] Copying 121 resources from src\main\resources to target\classes
[INFO] 
[INFO] --- flatten:1.7.3:flatten (flatten) @ lockable-resources ---
[INFO] Generating flattened POM of project org.6wind.jenkins:lockable-resources:hpi:999999-SNAPSHOT...
[INFO] 
[INFO] --- compiler:3.15.0:compile (default-compile) @ lockable-resources ---
[INFO] Recompiling the module because of changed source code.
[INFO] Compiling 48 source files with javac [debug parameters release 17] to target\classes
[WARNING] unknown enum constant javax.annotation.meta.When.MAYBE
  reason: class file for javax.annotation.meta.When not found
[WARNING] unknown enum constant javax.annotation.meta.When.ALWAYS
[WARNING] unknown enum constant javax.annotation.meta.When.UNKNOWN
[INFO] org.jenkins.plugins.lockableresources.queue.Utils.MatrixImpl indexed under org.jenkinsci.plugins.variant.OptionalExtension
[INFO] org.jenkins.plugins.lockableresources.LockStep.DescriptorImpl indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.LockStepResource.DescriptorImpl indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.LockableResource.DescriptorImpl indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.LockableResourceProperty.DescriptorImpl indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.LockableResourcesManager indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.RemoteConnection.DescriptorImpl indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.RequiredResourcesProperty.DescriptorImpl indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.UpdateLockStep.DescriptorImpl indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.actions.LockableResourcesManagementLink indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.actions.LockableResourcesRootAction indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.actions.ResourceVariableNameAction.ResourceVariableNameActionEnvironmentContributor indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.nodes.NodesMirror indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.queue.LockRunListener indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.queue.LockWaitTimeoutPeriodicWork indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.queue.LockableResourcesQueueTaskDispatcher indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.remote.RemoteCatalogCache indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.remote.RemoteClientRegistry indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.remote.RemoteLockManager indexed under hudson.Extension
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStep.java:[96,12] Generating org/jenkins/plugins/lockableresources/LockStep.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStepResource.java:[55,12] Generating org/jenkins/plugins/lockableresources/LockStepResource.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockableResource.java:[204,12] Generating org/jenkins/plugins/lockableresources/LockableResource.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockableResourceProperty.java:[21,12] Generating org/jenkins/plugins/lockableresources/LockableResourceProperty.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RemoteConnection.java:[48,12] Generating org/jenkins/plugins/lockableresources/RemoteConnection.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RequiredResourcesProperty.java:[55,12] Generating org/jenkins/plugins/lockableresources/RequiredResourcesProperty.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/UpdateLockStep.java:[66,12] Generating org/jenkins/plugins/lockableresources/UpdateLockStep.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/actions/LockableResourcesRootAction.java:[57,8] Generating org/jenkins/plugins/lockableresources/actions/LockableResourcesRootAction.javadoc
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockableResources.java:[15,8] Generating org/jenkins/plugins/lockableresources/LockableResources.javadoc
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockableResource.java:[58,8] Generating org/jenkins/plugins/lockableresources/LockableResource.javadoc
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockableResourceProperty.java:[14,8] Generating org/jenkins/plugins/lockableresources/LockableResourceProperty.javadoc
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RequiredResourcesProperty.java:[242,31] Generating org/jenkins/plugins/lockableresources/RequiredResourcesProperty/DescriptorImpl/doCheckLabelName.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStepResource.java:[217,38] Generating org/jenkins/plugins/lockableresources/LockStepResource/DescriptorImpl/doCheckResource.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStepResource.java:[187,41] Generating org/jenkins/plugins/lockableresources/LockStepResource/DescriptorImpl/doAutoCompleteResource.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStep.java:[255,38] Generating org/jenkins/plugins/lockableresources/LockStep/DescriptorImpl/doCheckResourceSelectStrategy.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/UpdateLockStep.java:[232,31] Generating org/jenkins/plugins/lockableresources/UpdateLockStep/DescriptorImpl/doCheckResource.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RemoteConnection.java:[150,31] Generating org/jenkins/plugins/lockableresources/RemoteConnection/DescriptorImpl/doCheckUrl.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RequiredResourcesProperty.java:[315,41] Generating org/jenkins/plugins/lockableresources/RequiredResourcesProperty/DescriptorImpl/doAutoCompleteLabelName.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RemoteConnection.java:[131,29] Generating org/jenkins/plugins/lockableresources/RemoteConnection/DescriptorImpl/doFillCredentialsIdItems.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RequiredResourcesProperty.java:[205,31] Generating org/jenkins/plugins/lockableresources/RequiredResourcesProperty/DescriptorImpl/doCheckResourceNames.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStep.java:[243,38] Generating org/jenkins/plugins/lockableresources/LockStep/DescriptorImpl/doCheckLabel.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/UpdateLockStep.java:[284,31] Generating org/jenkins/plugins/lockableresources/UpdateLockStep/DescriptorImpl/doCheckDeleteResource.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/UpdateLockStep.java:[249,31] Generating org/jenkins/plugins/lockableresources/UpdateLockStep/DescriptorImpl/doCheckAddLabels.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RequiredResourcesProperty.java:[337,48] Generating org/jenkins/plugins/lockableresources/RequiredResourcesProperty/DescriptorImpl/doAutoCompleteResourceNames.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RequiredResourcesProperty.java:[271,31] Generating org/jenkins/plugins/lockableresources/RequiredResourcesProperty/DescriptorImpl/doCheckResourceNumber.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/UpdateLockStep.java:[263,31] Generating org/jenkins/plugins/lockableresources/UpdateLockStep/DescriptorImpl/doCheckRemoveLabels.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockableResourcesManager.java:[313,27] Generating org/jenkins/plugins/lockableresources/LockableResourcesManager/doCheckForcedServerId.stapler
[WARNING] unknown enum constant javax.annotation.meta.When.MAYBE
  reason: class file for javax.annotation.meta.When not found
[WARNING] unknown enum constant javax.annotation.meta.When.ALWAYS
[WARNING] unknown enum constant javax.annotation.meta.When.UNKNOWN
[WARNING] unknown enum constant javax.annotation.meta.When.MAYBE
  reason: class file for javax.annotation.meta.When not found
[WARNING] unknown enum constant javax.annotation.meta.When.ALWAYS
[WARNING] unknown enum constant javax.annotation.meta.When.UNKNOWN
[WARNING] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockableResource.java:[334,17] deprecated item is not annotated with @Deprecated
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStepResource.java: Some input files use or override a deprecated API.
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStepResource.java: Recompile with -Xlint:deprecation for details.
[INFO] 
[INFO] --- access-modifier-checker:1.35:enforce (default-enforce) @ lockable-resources ---
[INFO] 
[INFO] --- bridge-method-injector:1.32:process (default) @ lockable-resources ---
[INFO] 
[INFO] --- hpi:3.1814.v77d15159f9b_d:insert-test (default-insert-test) @ lockable-resources ---
[INFO] 
[INFO] --- antrun:3.2.0:run (createTempDir) @ lockable-resources ---
[INFO] Executing tasks
[INFO]     [mkdir] Created dir: C:\src\lrp\target\tmp
[INFO] Executed tasks
[INFO] 
[INFO] --- resources:3.5.0:testResources (default-testResources) @ lockable-resources ---
[INFO] Copying 5 resources from src\test\resources to target\test-classes
[INFO] 
[INFO] --- compiler:3.15.0:testCompile (default-testCompile) @ lockable-resources ---
[INFO] Recompiling the module because of changed dependency.
[INFO] Compiling 53 source files with javac [debug parameters release 17] to target\test-classes
[INFO] /C:/src/lrp/src/test/java/org/jenkins/plugins/lockableresources/ConcurrentModificationExceptionTest.java: Some input files use or override a deprecated API.
[INFO] /C:/src/lrp/src/test/java/org/jenkins/plugins/lockableresources/ConcurrentModificationExceptionTest.java: Recompile with -Xlint:deprecation for details.
[INFO] 
[INFO] --- hpi:3.1814.v77d15159f9b_d:test-hpl (default-test-hpl) @ lockable-resources ---
[INFO] Generating C:\src\lrp\target\test-classes\the.hpl
[INFO] 
[INFO] --- hpi:3.1814.v77d15159f9b_d:resolve-test-dependencies (default-resolve-test-dependencies) @ lockable-resources ---
[INFO] 
[INFO] --- hpi:3.1814.v77d15159f9b_d:test-runtime (default-test-runtime) @ lockable-resources ---
[INFO] Setting jenkins.addOpens to --add-opens java.base/java.lang=ALL-UNNAMED --add-opens java.base/java.io=ALL-UNNAMED --add-opens java.base/java.util=ALL-UNNAMED
[INFO] Setting jenkins.insaneHook to --patch-module='java.base=C:\src\lrp\target\patch-modules\org-netbeans-insane-hook.jar' --add-exports=java.base/org.netbeans.insane.hook=ALL-UNNAMED
[INFO] Setting jenkins.javaAgent to -javaagent:'C:\m2\org\mockito\mockito-core\5.23.0\mockito-core-5.23.0.jar'
[INFO] 
[INFO] --- surefire:3.5.6:test (default-test) @ lockable-resources ---
[INFO] Using auto detected provider org.apache.maven.surefire.junitplatform.JUnitPlatformProvider
[INFO] 
[INFO] -------------------------------------------------------
[INFO]  T E S T S
[INFO] -------------------------------------------------------
[INFO] Running org.jenkins.plugins.lockableresources.LockStepWithRestartTest
=== Starting lockOrderRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   0.218 [id=31]	INFO	o.jvnet.hudson.test.WarExploder#explode: Exploding C:\m2\org\jenkins-ci\main\jenkins-war\2.541.3\jenkins-war-2.541.3.war into C:\src\lrp\target\jenkins-for-test
  13.141 [id=31]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49170/jenkins/
  14.125 [id=31]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
  14.280 [id=46]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
  19.148 [id=51]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
  19.164 [id=53]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h13719803211674125417\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
  21.672 [id=54]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
  21.701 [id=49]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
  21.701 [id=53]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
  22.897 [id=49]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
  22.960 [id=47]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
  22.960 [id=47]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
  22.960 [id=54]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
  22.968 [id=50]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
  22.984 [id=47]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
  23.109 [id=31]	INFO	o.j.p.w.t.s.SemaphoreStep$State#get: Initializing state in C:\src\lrp\target\tmp\j h13719803211674125417
  24.281 [id=90]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart/1
  24.520 [id=31]	WARNING	o.j.h.t.RemainingActivityListener#onTearDown: p #1 still seems to be running, which could break deletion of log files or metadata
  24.539 [id=31]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
  24.603 [id=31]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
=== Starting lockOrderRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   1.156 [id=108]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49170/jenkins/
   1.719 [id=108]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.734 [id=120]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.740 [id=127]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.741 [id=125]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h13719803211674125417\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.928 [id=131]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.928 [id=128]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.928 [id=129]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   2.139 [id=125]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   2.154 [id=127]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   2.159 [id=121]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   2.159 [id=128]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   2.166 [id=123]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   2.316 [id=129]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   2.320 [id=90]	WARNING	o.j.p.w.f.FlowExecutionList$ResumeStepExecutionListener$1#onSuccess: Resuming p#1, which is missing from FlowExecutionList, so registering it now
   2.320 [id=90]	WARNING	o.j.p.w.f.FlowExecutionList$DefaultStorage#register: p#1 was already in the list: [p#1, p#2, p#3]
   2.400 [id=108]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart/1 as success
   2.477 [id=89]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart/2
   2.555 [id=108]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart/2 as success
   2.605 [id=89]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #1
   2.620 [id=160]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart/3
   2.620 [id=108]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart/3 as success
   2.692 [id=160]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #2
   2.739 [id=108]	WARNING	o.j.h.t.RemainingActivityListener#onTearDown: p #3 still seems to be running, which could break deletion of log files or metadata
   2.739 [id=160]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #3
   2.755 [id=108]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   2.771 [id=108]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
   2.849 [id=1]	INFO	o.j.h.t.TemporaryDirectoryAllocator#dispose: deleting C:\src\lrp\target\tmp\j h13719803211674125417
=== Starting interoperabilityOnRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   0.969 [id=171]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49176/jenkins/
   1.547 [id=171]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.562 [id=184]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.572 [id=183]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.572 [id=187]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h12053016002729696298\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.738 [id=187]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.754 [id=193]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.754 [id=184]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   2.579 [id=185]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   2.594 [id=188]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   2.594 [id=188]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   2.594 [id=187]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   2.605 [id=191]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   2.637 [id=187]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   2.668 [id=171]	INFO	o.j.p.w.t.s.SemaphoreStep$State#get: Initializing state in C:\src\lrp\target\tmp\j h12053016002729696298
   2.778 [id=161]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-interoperabilityOnRestart/1
   2.793 [id=171]	INFO	o.j.p.l.TestHelpers#waitForQueue: Waiting for job to be queued...
   2.793 [id=171]	WARNING	o.j.h.t.RemainingActivityListener#onTearDown: p #1 still seems to be running, which could break deletion of log files or metadata
   2.812 [id=171]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   2.825 [id=171]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
=== Starting interoperabilityOnRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   1.204 [id=222]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49176/jenkins/
   1.704 [id=222]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.719 [id=234]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.729 [id=242]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.729 [id=235]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h12053016002729696298\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.912 [id=242]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.927 [id=234]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.927 [id=234]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   2.036 [id=245]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   2.052 [id=238]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   2.054 [id=242]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   2.054 [id=245]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   2.056 [id=243]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   2.092 [id=242]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   2.097 [id=160]	WARNING	o.j.p.w.f.FlowExecutionList$ResumeStepExecutionListener$1#onSuccess: Resuming p#1, which is missing from FlowExecutionList, so registering it now
   2.099 [id=160]	WARNING	o.j.p.w.f.FlowExecutionList$DefaultStorage#register: p#1 was already in the list: [p#1]
   2.099 [id=222]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-interoperabilityOnRestart/1 as success
   2.148 [id=247]	INFO	o.j.p.l.queue.LockRunListener#onStarted: f #1 acquired lock on [resource1]
   2.195 [id=160]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #1
   2.215 [id=222]	INFO	o.j.p.l.LockStepWithRestartTest#lambda$interoperabilityOnRestart$3: Waiting for freestyle #1 to start building
   2.215 [id=247]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: f #1
   2.337 [id=222]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   2.346 [id=222]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
   2.409 [id=1]	INFO	o.j.h.t.TemporaryDirectoryAllocator#dispose: deleting C:\src\lrp\target\tmp\j h12053016002729696298
=== Starting checkQueueAfterRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   0.921 [id=274]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49181/jenkins/
   1.468 [id=274]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.484 [id=287]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.486 [id=294]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.487 [id=290]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h9236166034356968514\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.670 [id=296]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.670 [id=294]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.670 [id=293]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   2.569 [id=292]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   2.585 [id=294]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   2.585 [id=287]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   2.585 [id=287]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   2.589 [id=289]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   2.624 [id=294]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   2.702 [id=274]	INFO	o.j.p.l.LockableResourcesManager#reserve: reserve() called user='test' resources=[resource1] reason='null'
   2.702 [id=274]	INFO	o.j.p.l.LockableResourcesManager#reserve: reserve() succeeded user='test' resources=[resource1]
   2.702 [id=274]	INFO	o.j.p.l.LockableResourcesManager#reserve: reserve() called user='test' resources=[resource2] reason='null'
   2.702 [id=274]	INFO	o.j.p.l.LockableResourcesManager#reserve: reserve() succeeded user='test' resources=[resource2]
   2.827 [id=274]	WARNING	o.j.h.t.RemainingActivityListener#onTearDown: p #1 still seems to be running, which could break deletion of log files or metadata
   2.840 [id=274]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   2.850 [id=274]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
=== Starting checkQueueAfterRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   0.875 [id=326]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49181/jenkins/
   1.344 [id=326]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.359 [id=338]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.374 [id=346]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.374 [id=349]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h9236166034356968514\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.578 [id=348]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.593 [id=342]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.593 [id=343]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   1.695 [id=349]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   1.711 [id=346]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   1.711 [id=347]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   1.711 [id=347]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   1.715 [id=341]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   1.733 [id=347]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
  10.280 [id=326]	INFO	o.j.p.l.TestHelpers#clickButton: unreserve on resource1
  10.440 [id=326]	WARNING	o.j.h.t.RemainingActivityListener#onTearDown: p #1 still seems to be running, which could break deletion of log files or metadata
  10.440 [id=160]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #1
  10.465 [id=326]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
  10.474 [id=326]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
  10.583 [id=1]	INFO	o.j.h.t.TemporaryDirectoryAllocator#dispose: deleting C:\src\lrp\target\tmp\j h9236166034356968514
=== Starting testReserveOverRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   0.953 [id=392]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49188/jenkins/
   1.515 [id=392]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.531 [id=405]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.542 [id=408]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.543 [id=406]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h8184156230465144897\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.784 [id=415]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.799 [id=414]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.799 [id=414]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   2.166 [id=414]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   2.197 [id=409]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   2.197 [id=408]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   2.197 [id=406]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   2.205 [id=404]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   2.237 [id=415]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   2.253 [id=392]	INFO	o.j.p.l.LockableResourcesManager#reserve: reserve() called user='user' resources=[resource1] reason='null'
   2.253 [id=392]	INFO	o.j.p.l.LockableResourcesManager#reserve: reserve() succeeded user='user' resources=[resource1]
   2.380 [id=392]	INFO	o.j.p.l.TestHelpers#waitForQueue: Waiting for job to be queued...
   2.380 [id=392]	WARNING	o.j.h.t.RemainingActivityListener#onTearDown: p #1 still seems to be running, which could break deletion of log files or metadata
   2.400 [id=392]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   2.420 [id=392]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
=== Starting testReserveOverRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   0.953 [id=443]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49188/jenkins/
   1.484 [id=443]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.484 [id=455]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.501 [id=460]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.501 [id=459]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h8184156230465144897\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.673 [id=456]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.682 [id=461]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.682 [id=461]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   1.806 [id=461]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   1.822 [id=461]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   1.826 [id=465]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   1.826 [id=463]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   1.828 [id=457]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   1.863 [id=464]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   1.954 [id=467]	INFO	o.j.p.l.queue.LockRunListener#onStarted: f #1 acquired lock on [resource1]
   1.980 [id=467]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: f #1
   2.011 [id=161]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #1
   2.135 [id=443]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   2.144 [id=443]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
   2.269 [id=1]	INFO	o.j.h.t.TemporaryDirectoryAllocator#dispose: deleting C:\src\lrp\target\tmp\j h8184156230465144897
=== Starting chaosOnRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   1.141 [id=495]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49193/jenkins/
   1.688 [id=495]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.703 [id=508]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.708 [id=508]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.709 [id=517]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h17230439526421249769\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.896 [id=510]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.896 [id=513]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.896 [id=512]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   3.631 [id=518]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   3.647 [id=510]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   3.647 [id=513]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   3.647 [id=513]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   3.653 [id=515]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   3.685 [id=513]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   3.732 [id=495]	INFO	o.j.p.w.t.s.SemaphoreStep$State#get: Initializing state in C:\src\lrp\target\tmp\j h17230439526421249769
   4.312 [id=161]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-1/1
   4.328 [id=161]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-2/1
   4.344 [id=161]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-3/1
   4.359 [id=161]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-4/1
   4.375 [id=161]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-5/1
   5.244 [id=495]	WARNING	o.j.h.t.RemainingActivityListener#onTearDown: p #1 still seems to be running, which could break deletion of log files or metadata
   5.260 [id=495]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   5.293 [id=495]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
=== Starting chaosOnRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   1.203 [id=569]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49193/jenkins/
   1.672 [id=569]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.672 [id=581]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.684 [id=583]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.684 [id=584]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h17230439526421249769\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.882 [id=588]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.882 [id=584]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.882 [id=582]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   2.016 [id=582]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   2.031 [id=590]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   2.031 [id=583]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   2.031 [id=584]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   2.038 [id=581]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   2.104 [id=89]	WARNING	o.j.p.w.f.FlowExecutionList$ResumeStepExecutionListener$1#onSuccess: Resuming p#1, which is missing from FlowExecutionList, so registering it now
   2.105 [id=89]	WARNING	o.j.p.w.f.FlowExecutionList$DefaultStorage#register: p#1 was already in the list: [p#1, p#2, p#3]
   2.176 [id=589]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   2.191 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-1/1 as success
   2.191 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-2/1 as success
   2.191 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-3/1 as success
   2.191 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-4/1 as success
   2.191 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-5/1 as success
   2.288 [id=160]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-1/2
   2.319 [id=160]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-2/2
   2.366 [id=89]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-3/2
   2.366 [id=160]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-4/2
   2.382 [id=160]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-5/2
   2.413 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-1/2 as success
   2.413 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-2/2 as success
   2.413 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-3/2 as success
   2.413 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-4/2 as success
   2.413 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-5/2 as success
   2.446 [id=161]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-1/3
   2.507 [id=160]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-2/3
   2.561 [id=161]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-3/3
   2.576 [id=161]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-4/3
   2.592 [id=89]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-5/3
   2.592 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-1/3 as success
   2.592 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-2/3 as success
   2.592 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-3/3 as success
   2.592 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-4/3 as success
   2.592 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-5/3 as success
   2.781 [id=89]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #1
   2.955 [id=89]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #2
   3.065 [id=160]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #3
   3.091 [id=569]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   3.096 [id=569]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
   3.174 [id=1]	INFO	o.j.h.t.TemporaryDirectoryAllocator#dispose: deleting C:\src\lrp\target\tmp\j h17230439526421249769
[INFO] Tests run: 5, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 60.49 s -- in org.jenkins.plugins.lockableresources.LockStepWithRestartTest
[INFO] 
[INFO] Results:
[INFO] 
[INFO] Tests run: 5, Failures: 0, Errors: 0, Skipped: 0
[INFO] 
[INFO] ------------------------------------------------------------------------
[INFO] BUILD SUCCESS
[INFO] ------------------------------------------------------------------------
[INFO] Total time:  01:58 min
[INFO] Finished at: 2026-08-19T16:03:39+09:00
[INFO] ------------------------------------------------------------------------
```
</details>

<details><summary>docker run console output</summary>


```

=== Checking out bdca858 ===
Previous HEAD position was 148d8eb Annotate remote acquire status endpoint with GET (#1076)
HEAD is now at bdca858 [B7] Annotate the remote resources endpoint with GET
bdca858ec712ad7304252bce1dc2a64c6adb2cd5 2026-08-14 19:28:21 +0900 [B7] Annotate the remote resources endpoint with GET

=== Environment ===
rev.requested   : bdca858
rev.head        : bdca858ec712ad7304252bce1dc2a64c6adb2cd5 2026-08-14 19:28:21 +0900 [B7] Annotate the remote resources endpoint with GET
test.pattern    : LockStepWithRestartTest
repeat          : 1
extra.mvn.args  : 

os              : Microsoft Windows Server 2022 Datacenter build 10.0.20348.0
cpu.count       : 6
memory.total.mb : 8703
temp            : C:\t

java            : openjdk version "21.0.11" 2026-04-21 LTS | OpenJDK Runtime Environment Temurin-21.0.11+10 (build 21.0.11+10-LTS) | OpenJDK 64-Bit Server VM Temurin-21.0.11+10 (build 21.0.11+10-LTS, mixed mode, sharing)
maven           : Apache Maven 3.9.9 (8e8579a9e76f7d015ee5ec7bfcdc97d260186937) | Maven home: C:\tools\maven | Java version: 21.0.11, vendor: Eclipse Adoptium, runtime: C:\openjdk-21 | Default locale: en_US, platform encoding: UTF-8 | OS name: "windows server 2022", version: "10.0", arch: "amd64", family: "windows"
git             : git version 2.55.0.windows.4

=== Run 1/1 : mvn -B -ntp -Dstyle.color=never -Dmaven.repo.local=C:\m2 -Dtest=LockStepWithRestartTest test ===
[INFO] Scanning for projects...
[INFO] Artifact org.jenkins-ci.tools:maven-hpi-plugin:pom:3.1814.v77d15159f9b_d is present in the local repository, but cached from a remote repository ID that is unavailable in current build context, verifying that is downloadable from [incrementals (https://repo.jenkins-ci.org/incrementals/, default, releases), central (https://repo.maven.apache.org/maven2, default, releases)]
[INFO] Artifact org.jenkins-ci.tools:maven-hpi-plugin:pom:3.1814.v77d15159f9b_d is present in the local repository, but cached from a remote repository ID that is unavailable in current build context, verifying that is downloadable from [incrementals (https://repo.jenkins-ci.org/incrementals/, default, releases), central (https://repo.maven.apache.org/maven2, default, releases)]
[WARNING] The POM for org.jenkins-ci.tools:maven-hpi-plugin:jar:3.1814.v77d15159f9b_d is missing, no dependency information available
[INFO] Artifact org.jenkins-ci.tools:maven-hpi-plugin:jar:3.1814.v77d15159f9b_d is present in the local repository, but cached from a remote repository ID that is unavailable in current build context, verifying that is downloadable from [incrementals (https://repo.jenkins-ci.org/incrementals/, default, releases), central (https://repo.maven.apache.org/maven2, default, releases)]
[INFO] Artifact org.jenkins-ci.tools:maven-hpi-plugin:jar:3.1814.v77d15159f9b_d is present in the local repository, but cached from a remote repository ID that is unavailable in current build context, verifying that is downloadable from [incrementals (https://repo.jenkins-ci.org/incrementals/, default, releases), central (https://repo.maven.apache.org/maven2, default, releases)]
[WARNING] Failed to build parent project for org.6wind.jenkins:lockable-resources:hpi:999999-SNAPSHOT
[INFO] 
[INFO] ----------------< org.6wind.jenkins:lockable-resources >----------------
[INFO] Building Lockable Resources plugin 999999-SNAPSHOT
[INFO]   from pom.xml
[INFO] --------------------------------[ hpi ]---------------------------------
[INFO] 
[INFO] --- hpi:3.1814.v77d15159f9b_d:validate (default-validate) @ lockable-resources ---
[INFO] Created marker file C:\src\lrp\target\java-level\17
[INFO] 
[INFO] --- hpi:3.1814.v77d15159f9b_d:validate-hpi (default-validate-hpi) @ lockable-resources ---
[INFO] 
[INFO] --- enforcer:3.6.3:enforce (display-info) @ lockable-resources ---
[INFO] Rule 0: org.apache.maven.enforcer.rules.version.RequireMavenVersion passed
[INFO] Rule 1: org.apache.maven.enforcer.rules.version.RequireJavaVersion passed
[INFO] Rule 2: org.apache.maven.enforcer.rules.version.RequireJavaVersion passed
[INFO] Rule 3: org.apache.maven.enforcer.rules.RequirePluginVersions passed
[INFO] Rule 4: org.codehaus.mojo.extraenforcer.dependencies.EnforceBytecodeVersion passed
[INFO] Rule 5: org.apache.maven.enforcer.rules.dependency.BannedDependencies passed
[INFO] Rule 6: org.apache.maven.enforcer.rules.dependency.BannedDependencies passed
[INFO] Ignoring requireUpperBoundDeps in org.ow2.asm:asm
[INFO] Rule 7: org.apache.maven.enforcer.rules.dependency.RequireUpperBoundDeps passed
[INFO] banObsoleteDependencyOverrides skipped
[INFO] Rule 8: io.jenkins.tools.maven.jenkins_enforcer_rules.BanObsoleteDependencyOverrides passed
[INFO] 
[INFO] --- enforcer:3.6.3:enforce (no-snapshots-in-release) @ lockable-resources ---
[INFO] Rule 0: org.apache.maven.enforcer.rules.dependency.RequireReleaseDeps passed
[INFO] 
[INFO] --- localizer:1.31:generate (default) @ lockable-resources ---
[INFO] 
[INFO] --- enforcer:3.6.3:enforce (check-junit-imports) @ lockable-resources ---
[INFO] Rule 0: org.apache.maven.plugins.enforcer.RestrictImports passed
[INFO] 
[INFO] --- enforcer:3.6.3:enforce (check-commons-lang-imports) @ lockable-resources ---
[INFO] Skipping Rule Enforcement.
[INFO] 
[INFO] --- enforcer:3.6.3:enforce (check-deprecated-stapler-imports) @ lockable-resources ---
[INFO] Skipping Rule Enforcement.
[INFO] 
[INFO] --- resources:3.5.0:resources (default-resources) @ lockable-resources ---
[INFO] Copying 121 resources from src\main\resources to target\classes
[INFO] 
[INFO] --- flatten:1.7.3:flatten (flatten) @ lockable-resources ---
[INFO] Generating flattened POM of project org.6wind.jenkins:lockable-resources:hpi:999999-SNAPSHOT...
[INFO] 
[INFO] --- compiler:3.15.0:compile (default-compile) @ lockable-resources ---
[INFO] Recompiling the module because of changed source code.
[INFO] Compiling 48 source files with javac [debug parameters release 17] to target\classes
[WARNING] unknown enum constant javax.annotation.meta.When.MAYBE
  reason: class file for javax.annotation.meta.When not found
[WARNING] unknown enum constant javax.annotation.meta.When.ALWAYS
[WARNING] unknown enum constant javax.annotation.meta.When.UNKNOWN
[INFO] org.jenkins.plugins.lockableresources.queue.Utils.MatrixImpl indexed under org.jenkinsci.plugins.variant.OptionalExtension
[INFO] org.jenkins.plugins.lockableresources.LockStep.DescriptorImpl indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.LockStepResource.DescriptorImpl indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.LockableResource.DescriptorImpl indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.LockableResourceProperty.DescriptorImpl indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.LockableResourcesManager indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.RemoteConnection.DescriptorImpl indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.RequiredResourcesProperty.DescriptorImpl indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.UpdateLockStep.DescriptorImpl indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.actions.LockableResourcesManagementLink indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.actions.LockableResourcesRootAction indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.actions.ResourceVariableNameAction.ResourceVariableNameActionEnvironmentContributor indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.nodes.NodesMirror indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.queue.LockRunListener indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.queue.LockWaitTimeoutPeriodicWork indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.queue.LockableResourcesQueueTaskDispatcher indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.remote.RemoteCatalogCache indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.remote.RemoteClientRegistry indexed under hudson.Extension
[INFO] org.jenkins.plugins.lockableresources.remote.RemoteLockManager indexed under hudson.Extension
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStep.java:[96,12] Generating org/jenkins/plugins/lockableresources/LockStep.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStepResource.java:[55,12] Generating org/jenkins/plugins/lockableresources/LockStepResource.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockableResource.java:[204,12] Generating org/jenkins/plugins/lockableresources/LockableResource.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockableResourceProperty.java:[21,12] Generating org/jenkins/plugins/lockableresources/LockableResourceProperty.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RemoteConnection.java:[48,12] Generating org/jenkins/plugins/lockableresources/RemoteConnection.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RequiredResourcesProperty.java:[55,12] Generating org/jenkins/plugins/lockableresources/RequiredResourcesProperty.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/UpdateLockStep.java:[66,12] Generating org/jenkins/plugins/lockableresources/UpdateLockStep.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/actions/LockableResourcesRootAction.java:[57,8] Generating org/jenkins/plugins/lockableresources/actions/LockableResourcesRootAction.javadoc
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockableResources.java:[15,8] Generating org/jenkins/plugins/lockableresources/LockableResources.javadoc
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockableResource.java:[58,8] Generating org/jenkins/plugins/lockableresources/LockableResource.javadoc
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockableResourceProperty.java:[14,8] Generating org/jenkins/plugins/lockableresources/LockableResourceProperty.javadoc
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RequiredResourcesProperty.java:[242,31] Generating org/jenkins/plugins/lockableresources/RequiredResourcesProperty/DescriptorImpl/doCheckLabelName.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStepResource.java:[217,38] Generating org/jenkins/plugins/lockableresources/LockStepResource/DescriptorImpl/doCheckResource.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStepResource.java:[187,41] Generating org/jenkins/plugins/lockableresources/LockStepResource/DescriptorImpl/doAutoCompleteResource.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStep.java:[255,38] Generating org/jenkins/plugins/lockableresources/LockStep/DescriptorImpl/doCheckResourceSelectStrategy.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/UpdateLockStep.java:[232,31] Generating org/jenkins/plugins/lockableresources/UpdateLockStep/DescriptorImpl/doCheckResource.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RemoteConnection.java:[150,31] Generating org/jenkins/plugins/lockableresources/RemoteConnection/DescriptorImpl/doCheckUrl.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RequiredResourcesProperty.java:[315,41] Generating org/jenkins/plugins/lockableresources/RequiredResourcesProperty/DescriptorImpl/doAutoCompleteLabelName.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RemoteConnection.java:[131,29] Generating org/jenkins/plugins/lockableresources/RemoteConnection/DescriptorImpl/doFillCredentialsIdItems.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RequiredResourcesProperty.java:[205,31] Generating org/jenkins/plugins/lockableresources/RequiredResourcesProperty/DescriptorImpl/doCheckResourceNames.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStep.java:[243,38] Generating org/jenkins/plugins/lockableresources/LockStep/DescriptorImpl/doCheckLabel.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/UpdateLockStep.java:[284,31] Generating org/jenkins/plugins/lockableresources/UpdateLockStep/DescriptorImpl/doCheckDeleteResource.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/UpdateLockStep.java:[249,31] Generating org/jenkins/plugins/lockableresources/UpdateLockStep/DescriptorImpl/doCheckAddLabels.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RequiredResourcesProperty.java:[337,48] Generating org/jenkins/plugins/lockableresources/RequiredResourcesProperty/DescriptorImpl/doAutoCompleteResourceNames.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RequiredResourcesProperty.java:[271,31] Generating org/jenkins/plugins/lockableresources/RequiredResourcesProperty/DescriptorImpl/doCheckResourceNumber.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/UpdateLockStep.java:[263,31] Generating org/jenkins/plugins/lockableresources/UpdateLockStep/DescriptorImpl/doCheckRemoveLabels.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockableResourcesManager.java:[313,27] Generating org/jenkins/plugins/lockableresources/LockableResourcesManager/doCheckForcedServerId.stapler
[WARNING] unknown enum constant javax.annotation.meta.When.MAYBE
  reason: class file for javax.annotation.meta.When not found
[WARNING] unknown enum constant javax.annotation.meta.When.ALWAYS
[WARNING] unknown enum constant javax.annotation.meta.When.UNKNOWN
[WARNING] unknown enum constant javax.annotation.meta.When.MAYBE
  reason: class file for javax.annotation.meta.When not found
[WARNING] unknown enum constant javax.annotation.meta.When.ALWAYS
[WARNING] unknown enum constant javax.annotation.meta.When.UNKNOWN
[WARNING] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockableResource.java:[334,17] deprecated item is not annotated with @Deprecated
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStepResource.java: Some input files use or override a deprecated API.
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStepResource.java: Recompile with -Xlint:deprecation for details.
[INFO] 
[INFO] --- access-modifier-checker:1.35:enforce (default-enforce) @ lockable-resources ---
[INFO] 
[INFO] --- bridge-method-injector:1.32:process (default) @ lockable-resources ---
[INFO] 
[INFO] --- hpi:3.1814.v77d15159f9b_d:insert-test (default-insert-test) @ lockable-resources ---
[INFO] 
[INFO] --- antrun:3.2.0:run (createTempDir) @ lockable-resources ---
[INFO] Executing tasks
[INFO]     [mkdir] Created dir: C:\src\lrp\target\tmp
[INFO] Executed tasks
[INFO] 
[INFO] --- resources:3.5.0:testResources (default-testResources) @ lockable-resources ---
[INFO] Copying 5 resources from src\test\resources to target\test-classes
[INFO] 
[INFO] --- compiler:3.15.0:testCompile (default-testCompile) @ lockable-resources ---
[INFO] Recompiling the module because of changed dependency.
[INFO] Compiling 53 source files with javac [debug parameters release 17] to target\test-classes
[INFO] /C:/src/lrp/src/test/java/org/jenkins/plugins/lockableresources/ConcurrentModificationExceptionTest.java: Some input files use or override a deprecated API.
[INFO] /C:/src/lrp/src/test/java/org/jenkins/plugins/lockableresources/ConcurrentModificationExceptionTest.java: Recompile with -Xlint:deprecation for details.
[INFO] 
[INFO] --- hpi:3.1814.v77d15159f9b_d:test-hpl (default-test-hpl) @ lockable-resources ---
[INFO] Generating C:\src\lrp\target\test-classes\the.hpl
[INFO] 
[INFO] --- hpi:3.1814.v77d15159f9b_d:resolve-test-dependencies (default-resolve-test-dependencies) @ lockable-resources ---
[INFO] 
[INFO] --- hpi:3.1814.v77d15159f9b_d:test-runtime (default-test-runtime) @ lockable-resources ---
[INFO] Setting jenkins.addOpens to --add-opens java.base/java.lang=ALL-UNNAMED --add-opens java.base/java.io=ALL-UNNAMED --add-opens java.base/java.util=ALL-UNNAMED
[INFO] Setting jenkins.insaneHook to --patch-module='java.base=C:\src\lrp\target\patch-modules\org-netbeans-insane-hook.jar' --add-exports=java.base/org.netbeans.insane.hook=ALL-UNNAMED
[INFO] Setting jenkins.javaAgent to -javaagent:'C:\m2\org\mockito\mockito-core\5.23.0\mockito-core-5.23.0.jar'
[INFO] 
[INFO] --- surefire:3.5.6:test (default-test) @ lockable-resources ---
[INFO] Using auto detected provider org.apache.maven.surefire.junitplatform.JUnitPlatformProvider
[INFO] 
[INFO] -------------------------------------------------------
[INFO]  T E S T S
[INFO] -------------------------------------------------------
[INFO] Running org.jenkins.plugins.lockableresources.LockStepWithRestartTest
=== Starting lockOrderRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   0.218 [id=31]	INFO	o.jvnet.hudson.test.WarExploder#explode: Exploding C:\m2\org\jenkins-ci\main\jenkins-war\2.541.3\jenkins-war-2.541.3.war into C:\src\lrp\target\jenkins-for-test
  13.141 [id=31]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49170/jenkins/
  14.125 [id=31]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
  14.280 [id=46]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
  19.148 [id=51]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
  19.164 [id=53]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h13719803211674125417\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
  21.672 [id=54]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
  21.701 [id=49]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
  21.701 [id=53]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
  22.897 [id=49]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
  22.960 [id=47]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
  22.960 [id=47]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
  22.960 [id=54]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
  22.968 [id=50]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
  22.984 [id=47]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
  23.109 [id=31]	INFO	o.j.p.w.t.s.SemaphoreStep$State#get: Initializing state in C:\src\lrp\target\tmp\j h13719803211674125417
  24.281 [id=90]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart/1
  24.520 [id=31]	WARNING	o.j.h.t.RemainingActivityListener#onTearDown: p #1 still seems to be running, which could break deletion of log files or metadata
  24.539 [id=31]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
  24.603 [id=31]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
=== Starting lockOrderRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   1.156 [id=108]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49170/jenkins/
   1.719 [id=108]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.734 [id=120]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.740 [id=127]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.741 [id=125]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h13719803211674125417\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.928 [id=131]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.928 [id=128]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.928 [id=129]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   2.139 [id=125]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   2.154 [id=127]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   2.159 [id=121]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   2.159 [id=128]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   2.166 [id=123]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   2.316 [id=129]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   2.320 [id=90]	WARNING	o.j.p.w.f.FlowExecutionList$ResumeStepExecutionListener$1#onSuccess: Resuming p#1, which is missing from FlowExecutionList, so registering it now
   2.320 [id=90]	WARNING	o.j.p.w.f.FlowExecutionList$DefaultStorage#register: p#1 was already in the list: [p#1, p#2, p#3]
   2.400 [id=108]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart/1 as success
   2.477 [id=89]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart/2
   2.555 [id=108]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart/2 as success
   2.605 [id=89]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #1
   2.620 [id=160]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart/3
   2.620 [id=108]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart/3 as success
   2.692 [id=160]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #2
   2.739 [id=108]	WARNING	o.j.h.t.RemainingActivityListener#onTearDown: p #3 still seems to be running, which could break deletion of log files or metadata
   2.739 [id=160]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #3
   2.755 [id=108]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   2.771 [id=108]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
   2.849 [id=1]	INFO	o.j.h.t.TemporaryDirectoryAllocator#dispose: deleting C:\src\lrp\target\tmp\j h13719803211674125417
=== Starting interoperabilityOnRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   0.969 [id=171]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49176/jenkins/
   1.547 [id=171]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.562 [id=184]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.572 [id=183]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.572 [id=187]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h12053016002729696298\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.738 [id=187]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.754 [id=193]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.754 [id=184]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   2.579 [id=185]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   2.594 [id=188]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   2.594 [id=188]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   2.594 [id=187]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   2.605 [id=191]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   2.637 [id=187]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   2.668 [id=171]	INFO	o.j.p.w.t.s.SemaphoreStep$State#get: Initializing state in C:\src\lrp\target\tmp\j h12053016002729696298
   2.778 [id=161]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-interoperabilityOnRestart/1
   2.793 [id=171]	INFO	o.j.p.l.TestHelpers#waitForQueue: Waiting for job to be queued...
   2.793 [id=171]	WARNING	o.j.h.t.RemainingActivityListener#onTearDown: p #1 still seems to be running, which could break deletion of log files or metadata
   2.812 [id=171]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   2.825 [id=171]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
=== Starting interoperabilityOnRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   1.204 [id=222]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49176/jenkins/
   1.704 [id=222]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.719 [id=234]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.729 [id=242]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.729 [id=235]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h12053016002729696298\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.912 [id=242]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.927 [id=234]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.927 [id=234]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   2.036 [id=245]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   2.052 [id=238]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   2.054 [id=242]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   2.054 [id=245]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   2.056 [id=243]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   2.092 [id=242]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   2.097 [id=160]	WARNING	o.j.p.w.f.FlowExecutionList$ResumeStepExecutionListener$1#onSuccess: Resuming p#1, which is missing from FlowExecutionList, so registering it now
   2.099 [id=160]	WARNING	o.j.p.w.f.FlowExecutionList$DefaultStorage#register: p#1 was already in the list: [p#1]
   2.099 [id=222]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-interoperabilityOnRestart/1 as success
   2.148 [id=247]	INFO	o.j.p.l.queue.LockRunListener#onStarted: f #1 acquired lock on [resource1]
   2.195 [id=160]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #1
   2.215 [id=222]	INFO	o.j.p.l.LockStepWithRestartTest#lambda$interoperabilityOnRestart$3: Waiting for freestyle #1 to start building
   2.215 [id=247]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: f #1
   2.337 [id=222]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   2.346 [id=222]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
   2.409 [id=1]	INFO	o.j.h.t.TemporaryDirectoryAllocator#dispose: deleting C:\src\lrp\target\tmp\j h12053016002729696298
=== Starting checkQueueAfterRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   0.921 [id=274]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49181/jenkins/
   1.468 [id=274]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.484 [id=287]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.486 [id=294]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.487 [id=290]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h9236166034356968514\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.670 [id=296]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.670 [id=294]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.670 [id=293]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   2.569 [id=292]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   2.585 [id=294]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   2.585 [id=287]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   2.585 [id=287]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   2.589 [id=289]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   2.624 [id=294]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   2.702 [id=274]	INFO	o.j.p.l.LockableResourcesManager#reserve: reserve() called user='test' resources=[resource1] reason='null'
   2.702 [id=274]	INFO	o.j.p.l.LockableResourcesManager#reserve: reserve() succeeded user='test' resources=[resource1]
   2.702 [id=274]	INFO	o.j.p.l.LockableResourcesManager#reserve: reserve() called user='test' resources=[resource2] reason='null'
   2.702 [id=274]	INFO	o.j.p.l.LockableResourcesManager#reserve: reserve() succeeded user='test' resources=[resource2]
   2.827 [id=274]	WARNING	o.j.h.t.RemainingActivityListener#onTearDown: p #1 still seems to be running, which could break deletion of log files or metadata
   2.840 [id=274]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   2.850 [id=274]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
=== Starting checkQueueAfterRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   0.875 [id=326]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49181/jenkins/
   1.344 [id=326]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.359 [id=338]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.374 [id=346]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.374 [id=349]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h9236166034356968514\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.578 [id=348]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.593 [id=342]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.593 [id=343]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   1.695 [id=349]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   1.711 [id=346]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   1.711 [id=347]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   1.711 [id=347]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   1.715 [id=341]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   1.733 [id=347]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
  10.280 [id=326]	INFO	o.j.p.l.TestHelpers#clickButton: unreserve on resource1
  10.440 [id=326]	WARNING	o.j.h.t.RemainingActivityListener#onTearDown: p #1 still seems to be running, which could break deletion of log files or metadata
  10.440 [id=160]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #1
  10.465 [id=326]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
  10.474 [id=326]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
  10.583 [id=1]	INFO	o.j.h.t.TemporaryDirectoryAllocator#dispose: deleting C:\src\lrp\target\tmp\j h9236166034356968514
=== Starting testReserveOverRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   0.953 [id=392]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49188/jenkins/
   1.515 [id=392]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.531 [id=405]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.542 [id=408]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.543 [id=406]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h8184156230465144897\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.784 [id=415]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.799 [id=414]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.799 [id=414]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   2.166 [id=414]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   2.197 [id=409]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   2.197 [id=408]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   2.197 [id=406]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   2.205 [id=404]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   2.237 [id=415]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   2.253 [id=392]	INFO	o.j.p.l.LockableResourcesManager#reserve: reserve() called user='user' resources=[resource1] reason='null'
   2.253 [id=392]	INFO	o.j.p.l.LockableResourcesManager#reserve: reserve() succeeded user='user' resources=[resource1]
   2.380 [id=392]	INFO	o.j.p.l.TestHelpers#waitForQueue: Waiting for job to be queued...
   2.380 [id=392]	WARNING	o.j.h.t.RemainingActivityListener#onTearDown: p #1 still seems to be running, which could break deletion of log files or metadata
   2.400 [id=392]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   2.420 [id=392]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
=== Starting testReserveOverRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   0.953 [id=443]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49188/jenkins/
   1.484 [id=443]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.484 [id=455]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.501 [id=460]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.501 [id=459]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h8184156230465144897\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.673 [id=456]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.682 [id=461]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.682 [id=461]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   1.806 [id=461]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   1.822 [id=461]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   1.826 [id=465]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   1.826 [id=463]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   1.828 [id=457]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   1.863 [id=464]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   1.954 [id=467]	INFO	o.j.p.l.queue.LockRunListener#onStarted: f #1 acquired lock on [resource1]
   1.980 [id=467]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: f #1
   2.011 [id=161]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #1
   2.135 [id=443]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   2.144 [id=443]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
   2.269 [id=1]	INFO	o.j.h.t.TemporaryDirectoryAllocator#dispose: deleting C:\src\lrp\target\tmp\j h8184156230465144897
=== Starting chaosOnRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   1.141 [id=495]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49193/jenkins/
   1.688 [id=495]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.703 [id=508]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.708 [id=508]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.709 [id=517]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h17230439526421249769\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.896 [id=510]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.896 [id=513]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.896 [id=512]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   3.631 [id=518]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   3.647 [id=510]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   3.647 [id=513]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   3.647 [id=513]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   3.653 [id=515]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   3.685 [id=513]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   3.732 [id=495]	INFO	o.j.p.w.t.s.SemaphoreStep$State#get: Initializing state in C:\src\lrp\target\tmp\j h17230439526421249769
   4.312 [id=161]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-1/1
   4.328 [id=161]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-2/1
   4.344 [id=161]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-3/1
   4.359 [id=161]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-4/1
   4.375 [id=161]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-5/1
   5.244 [id=495]	WARNING	o.j.h.t.RemainingActivityListener#onTearDown: p #1 still seems to be running, which could break deletion of log files or metadata
   5.260 [id=495]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   5.293 [id=495]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
=== Starting chaosOnRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   1.203 [id=569]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49193/jenkins/
   1.672 [id=569]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.672 [id=581]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.684 [id=583]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.684 [id=584]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h17230439526421249769\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.882 [id=588]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.882 [id=584]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.882 [id=582]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   2.016 [id=582]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   2.031 [id=590]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   2.031 [id=583]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   2.031 [id=584]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   2.038 [id=581]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   2.104 [id=89]	WARNING	o.j.p.w.f.FlowExecutionList$ResumeStepExecutionListener$1#onSuccess: Resuming p#1, which is missing from FlowExecutionList, so registering it now
   2.105 [id=89]	WARNING	o.j.p.w.f.FlowExecutionList$DefaultStorage#register: p#1 was already in the list: [p#1, p#2, p#3]
   2.176 [id=589]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   2.191 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-1/1 as success
   2.191 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-2/1 as success
   2.191 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-3/1 as success
   2.191 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-4/1 as success
   2.191 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-5/1 as success
   2.288 [id=160]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-1/2
   2.319 [id=160]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-2/2
   2.366 [id=89]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-3/2
   2.366 [id=160]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-4/2
   2.382 [id=160]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-5/2
   2.413 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-1/2 as success
   2.413 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-2/2 as success
   2.413 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-3/2 as success
   2.413 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-4/2 as success
   2.413 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-5/2 as success
   2.446 [id=161]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-1/3
   2.507 [id=160]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-2/3
   2.561 [id=161]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-3/3
   2.576 [id=161]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-4/3
   2.592 [id=89]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-5/3
   2.592 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-1/3 as success
   2.592 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-2/3 as success
   2.592 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-3/3 as success
   2.592 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-4/3 as success
   2.592 [id=569]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-5/3 as success
   2.781 [id=89]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #1
   2.955 [id=89]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #2
   3.065 [id=160]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #3
   3.091 [id=569]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   3.096 [id=569]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
   3.174 [id=1]	INFO	o.j.h.t.TemporaryDirectoryAllocator#dispose: deleting C:\src\lrp\target\tmp\j h17230439526421249769
[INFO] Tests run: 5, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 60.49 s -- in org.jenkins.plugins.lockableresources.LockStepWithRestartTest
[INFO] 
[INFO] Results:
[INFO] 
[INFO] Tests run: 5, Failures: 0, Errors: 0, Skipped: 0
[INFO] 
[INFO] ------------------------------------------------------------------------
[INFO] BUILD SUCCESS
[INFO] ------------------------------------------------------------------------
[INFO] Total time:  01:58 min
[INFO] Finished at: 2026-08-19T16:03:39+09:00
[INFO] ------------------------------------------------------------------------
Run 1/1 exit code: 0

=== Summary ===
rev      : bdca858ec712ad7304252bce1dc2a64c6adb2cd5 2026-08-14 19:28:21 +0900 [B7] Annotate the remote resources endpoint with GET
pattern  : LockStepWithRestartTest

run 1: PASS (exit 0)
```
</details>


