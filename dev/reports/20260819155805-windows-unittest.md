# Windows container unit test report (20260819155805)

- Result: **PASS** (exit 0)
- Duration: 2m9s
- Revision requested: `148d8eb`
- Revision tested: `148d8ebc6d9453403cfbd810d45623352979071a 2026-08-12 08:25:47 +0000 Annotate remote acquire status endpoint with GET (#1076)`
- Test pattern: `LockStepWithRestartTest`  (repeat 1)
- Image: `lrr-win-test:ltsc2022-jdk21` (`3f7c2a589530`), hyperv isolation, memory 8g, cpus 6
- Harness (notes): `bd60a84 + local changes`
- Raw artifacts: `20260819155805-windows-unittest/`

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
[INFO] Copying 117 resources from src\main\resources to target\classes
[INFO] 
[INFO] --- flatten:1.7.3:flatten (flatten) @ lockable-resources ---
[INFO] Generating flattened POM of project org.6wind.jenkins:lockable-resources:hpi:999999-SNAPSHOT...
[INFO] 
[INFO] --- compiler:3.15.0:compile (default-compile) @ lockable-resources ---
[INFO] Recompiling the module because of changed source code.
[INFO] Compiling 45 source files with javac [debug parameters release 17] to target\classes
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
[INFO] org.jenkins.plugins.lockableresources.remote.RemoteLockManager indexed under hudson.Extension
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStep.java:[96,12] Generating org/jenkins/plugins/lockableresources/LockStep.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStepResource.java:[55,12] Generating org/jenkins/plugins/lockableresources/LockStepResource.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockableResource.java:[204,12] Generating org/jenkins/plugins/lockableresources/LockableResource.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockableResourceProperty.java:[21,12] Generating org/jenkins/plugins/lockableresources/LockableResourceProperty.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RemoteConnection.java:[36,12] Generating org/jenkins/plugins/lockableresources/RemoteConnection.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RequiredResourcesProperty.java:[55,12] Generating org/jenkins/plugins/lockableresources/RequiredResourcesProperty.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/UpdateLockStep.java:[66,12] Generating org/jenkins/plugins/lockableresources/UpdateLockStep.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockableResourceProperty.java:[14,8] Generating org/jenkins/plugins/lockableresources/LockableResourceProperty.javadoc
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockableResources.java:[15,8] Generating org/jenkins/plugins/lockableresources/LockableResources.javadoc
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/actions/LockableResourcesRootAction.java:[52,8] Generating org/jenkins/plugins/lockableresources/actions/LockableResourcesRootAction.javadoc
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockableResource.java:[58,8] Generating org/jenkins/plugins/lockableresources/LockableResource.javadoc
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStep.java:[255,38] Generating org/jenkins/plugins/lockableresources/LockStep/DescriptorImpl/doCheckResourceSelectStrategy.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockableResourcesManager.java:[267,27] Generating org/jenkins/plugins/lockableresources/LockableResourcesManager/doCheckForcedServerId.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RequiredResourcesProperty.java:[271,31] Generating org/jenkins/plugins/lockableresources/RequiredResourcesProperty/DescriptorImpl/doCheckResourceNumber.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/UpdateLockStep.java:[263,31] Generating org/jenkins/plugins/lockableresources/UpdateLockStep/DescriptorImpl/doCheckRemoveLabels.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/UpdateLockStep.java:[284,31] Generating org/jenkins/plugins/lockableresources/UpdateLockStep/DescriptorImpl/doCheckDeleteResource.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStep.java:[249,38] Generating org/jenkins/plugins/lockableresources/LockStep/DescriptorImpl/doCheckResource.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RequiredResourcesProperty.java:[337,48] Generating org/jenkins/plugins/lockableresources/RequiredResourcesProperty/DescriptorImpl/doAutoCompleteResourceNames.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStep.java:[223,41] Generating org/jenkins/plugins/lockableresources/LockStep/DescriptorImpl/doAutoCompleteResource.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RequiredResourcesProperty.java:[205,31] Generating org/jenkins/plugins/lockableresources/RequiredResourcesProperty/DescriptorImpl/doCheckResourceNames.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/UpdateLockStep.java:[249,31] Generating org/jenkins/plugins/lockableresources/UpdateLockStep/DescriptorImpl/doCheckAddLabels.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RemoteConnection.java:[127,31] Generating org/jenkins/plugins/lockableresources/RemoteConnection/DescriptorImpl/doCheckUrl.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStep.java:[243,38] Generating org/jenkins/plugins/lockableresources/LockStep/DescriptorImpl/doCheckLabel.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/UpdateLockStep.java:[232,31] Generating org/jenkins/plugins/lockableresources/UpdateLockStep/DescriptorImpl/doCheckResource.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RequiredResourcesProperty.java:[242,31] Generating org/jenkins/plugins/lockableresources/RequiredResourcesProperty/DescriptorImpl/doCheckLabelName.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStepResource.java:[217,38] Generating org/jenkins/plugins/lockableresources/LockStepResource/DescriptorImpl/doCheckResource.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RequiredResourcesProperty.java:[315,41] Generating org/jenkins/plugins/lockableresources/RequiredResourcesProperty/DescriptorImpl/doAutoCompleteLabelName.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RemoteConnection.java:[108,29] Generating org/jenkins/plugins/lockableresources/RemoteConnection/DescriptorImpl/doFillCredentialsIdItems.stapler
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
[INFO] Compiling 45 source files with javac [debug parameters release 17] to target\test-classes
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
   0.203 [id=31]	INFO	o.jvnet.hudson.test.WarExploder#explode: Exploding C:\m2\org\jenkins-ci\main\jenkins-war\2.541.3\jenkins-war-2.541.3.war into C:\src\lrp\target\jenkins-for-test
  11.517 [id=31]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49169/jenkins/
  12.392 [id=31]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
  12.533 [id=46]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
  16.528 [id=46]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
  16.543 [id=53]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h16665851978826152573\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
  18.864 [id=45]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
  18.885 [id=51]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
  18.885 [id=44]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
  19.905 [id=55]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
  19.992 [id=53]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
  19.992 [id=52]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
  19.992 [id=45]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
  20.003 [id=49]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
  20.019 [id=48]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
  20.144 [id=31]	INFO	o.j.p.w.t.s.SemaphoreStep$State#get: Initializing state in C:\src\lrp\target\tmp\j h16665851978826152573
  21.066 [id=90]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart/1
  21.320 [id=31]	WARNING	o.j.h.t.RemainingActivityListener#onTearDown: p #1 still seems to be running, which could break deletion of log files or metadata
  21.341 [id=31]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
  21.403 [id=31]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
=== Starting lockOrderRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   1.001 [id=108]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49169/jenkins/
   1.532 [id=108]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.547 [id=120]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.549 [id=124]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.550 [id=125]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h16665851978826152573\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.756 [id=122]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.756 [id=120]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.756 [id=123]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   1.944 [id=121]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   1.960 [id=121]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   1.960 [id=125]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   1.972 [id=120]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   1.972 [id=127]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   2.096 [id=130]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   2.096 [id=101]	WARNING	o.j.p.w.f.FlowExecutionList$ResumeStepExecutionListener$1#onSuccess: Resuming p#1, which is missing from FlowExecutionList, so registering it now
   2.096 [id=101]	WARNING	o.j.p.w.f.FlowExecutionList$DefaultStorage#register: p#1 was already in the list: [p#1, p#2, p#3]
   2.176 [id=108]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart/1 as success
   2.223 [id=89]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart/2
   2.286 [id=108]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart/2 as success
   2.301 [id=89]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #1
   2.328 [id=101]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart/3
   2.328 [id=108]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart/3 as success
   2.375 [id=89]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #2
   2.421 [id=89]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #3
   2.453 [id=108]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   2.469 [id=108]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
   2.531 [id=1]	INFO	o.j.h.t.TemporaryDirectoryAllocator#dispose: deleting C:\src\lrp\target\tmp\j h16665851978826152573
=== Starting interoperabilityOnRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   0.984 [id=170]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49175/jenkins/
   1.546 [id=170]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.562 [id=183]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.571 [id=189]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.571 [id=182]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h5752980570294301865\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.769 [id=184]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.769 [id=193]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.769 [id=190]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   2.153 [id=189]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   2.168 [id=183]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   2.168 [id=183]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   2.168 [id=187]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   2.172 [id=183]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   2.205 [id=192]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   2.237 [id=170]	INFO	o.j.p.w.t.s.SemaphoreStep$State#get: Initializing state in C:\src\lrp\target\tmp\j h5752980570294301865
   2.346 [id=101]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-interoperabilityOnRestart/1
   2.362 [id=170]	INFO	o.j.p.l.TestHelpers#waitForQueue: Waiting for job to be queued...
   2.377 [id=170]	WARNING	o.j.h.t.RemainingActivityListener#onTearDown: p #1 still seems to be running, which could break deletion of log files or metadata
   2.390 [id=170]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   2.415 [id=170]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
=== Starting interoperabilityOnRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   0.890 [id=220]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49175/jenkins/
   1.390 [id=220]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.406 [id=232]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.410 [id=234]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.411 [id=233]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h5752980570294301865\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.600 [id=237]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.615 [id=238]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.617 [id=236]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   1.745 [id=242]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   1.761 [id=241]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   1.761 [id=233]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   1.761 [id=233]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   1.765 [id=238]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   1.801 [id=232]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   1.806 [id=89]	WARNING	o.j.p.w.f.FlowExecutionList$ResumeStepExecutionListener$1#onSuccess: Resuming p#1, which is missing from FlowExecutionList, so registering it now
   1.806 [id=89]	WARNING	o.j.p.w.f.FlowExecutionList$DefaultStorage#register: p#1 was already in the list: [p#1]
   1.821 [id=220]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-interoperabilityOnRestart/1 as success
   1.852 [id=244]	INFO	o.j.p.l.queue.LockRunListener#onStarted: f #1 acquired lock on [resource1]
   1.899 [id=89]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #1
   1.899 [id=244]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: f #1
   1.931 [id=220]	INFO	o.j.p.l.LockStepWithRestartTest#lambda$interoperabilityOnRestart$3: Waiting for freestyle #1 to start building
   2.038 [id=220]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   2.043 [id=220]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
   2.121 [id=1]	INFO	o.j.h.t.TemporaryDirectoryAllocator#dispose: deleting C:\src\lrp\target\tmp\j h5752980570294301865
=== Starting checkQueueAfterRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   0.969 [id=273]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49180/jenkins/
   1.484 [id=273]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.500 [id=286]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.508 [id=290]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.509 [id=295]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h11186776770808613788\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.691 [id=291]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.692 [id=293]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.692 [id=295]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   2.634 [id=296]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   2.650 [id=289]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   2.650 [id=294]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   2.650 [id=294]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   2.651 [id=296]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   2.685 [id=294]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   2.763 [id=273]	INFO	o.j.p.l.LockableResourcesManager#reserve: reserve() called user='test' resources=[resource1] reason='null'
   2.763 [id=273]	INFO	o.j.p.l.LockableResourcesManager#reserve: reserve() succeeded user='test' resources=[resource1]
   2.763 [id=273]	INFO	o.j.p.l.LockableResourcesManager#reserve: reserve() called user='test' resources=[resource2] reason='null'
   2.763 [id=273]	INFO	o.j.p.l.LockableResourcesManager#reserve: reserve() succeeded user='test' resources=[resource2]
   2.888 [id=273]	WARNING	o.j.h.t.RemainingActivityListener#onTearDown: p #1 still seems to be running, which could break deletion of log files or metadata
   2.903 [id=273]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   2.921 [id=273]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
=== Starting checkQueueAfterRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   0.907 [id=325]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49180/jenkins/
   1.391 [id=325]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.407 [id=337]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.413 [id=345]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.414 [id=348]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h11186776770808613788\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.598 [id=343]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.614 [id=337]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.614 [id=344]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   1.728 [id=346]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   1.728 [id=341]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   1.744 [id=345]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   1.744 [id=345]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   1.746 [id=343]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   1.782 [id=348]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
  10.026 [id=325]	INFO	o.j.p.l.TestHelpers#clickButton: unreserve on resource1
  10.182 [id=325]	WARNING	o.j.h.t.RemainingActivityListener#onTearDown: p #1 still seems to be running, which could break deletion of log files or metadata
  10.182 [id=89]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #1
  10.209 [id=325]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
  10.225 [id=325]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
  10.350 [id=1]	INFO	o.j.h.t.TemporaryDirectoryAllocator#dispose: deleting C:\src\lrp\target\tmp\j h11186776770808613788
=== Starting testReserveOverRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   0.953 [id=391]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49188/jenkins/
   1.531 [id=391]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.547 [id=404]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.553 [id=403]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.553 [id=413]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h16181887582334790564\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.721 [id=412]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.737 [id=405]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.737 [id=409]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   2.997 [id=413]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   3.009 [id=407]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   3.009 [id=403]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   3.009 [id=414]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   3.014 [id=404]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   3.047 [id=414]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   3.063 [id=391]	INFO	o.j.p.l.LockableResourcesManager#reserve: reserve() called user='user' resources=[resource1] reason='null'
   3.063 [id=391]	INFO	o.j.p.l.LockableResourcesManager#reserve: reserve() succeeded user='user' resources=[resource1]
   3.203 [id=391]	INFO	o.j.p.l.TestHelpers#waitForQueue: Waiting for job to be queued...
   3.203 [id=391]	WARNING	o.j.h.t.RemainingActivityListener#onTearDown: p #1 still seems to be running, which could break deletion of log files or metadata
   3.229 [id=391]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   3.251 [id=391]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
=== Starting testReserveOverRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   0.890 [id=442]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49188/jenkins/
   1.390 [id=442]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.390 [id=454]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.400 [id=460]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.401 [id=465]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h16181887582334790564\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.583 [id=456]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.583 [id=458]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.583 [id=454]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   1.718 [id=463]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   1.718 [id=461]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   1.733 [id=461]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   1.733 [id=465]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   1.737 [id=460]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   1.757 [id=462]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   1.872 [id=466]	INFO	o.j.p.l.queue.LockRunListener#onStarted: f #1 acquired lock on [resource1]
   1.886 [id=466]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: f #1
   1.917 [id=89]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #1
   2.037 [id=442]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   2.060 [id=442]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
   2.170 [id=1]	INFO	o.j.h.t.TemporaryDirectoryAllocator#dispose: deleting C:\src\lrp\target\tmp\j h16181887582334790564
=== Starting chaosOnRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   0.828 [id=494]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49193/jenkins/
   1.391 [id=494]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.391 [id=507]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.402 [id=513]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.402 [id=515]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h18078805067805581600\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.574 [id=508]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.587 [id=506]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.587 [id=516]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   2.017 [id=506]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   2.032 [id=513]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   2.032 [id=510]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   2.032 [id=517]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   2.034 [id=506]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   2.066 [id=511]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   2.113 [id=494]	INFO	o.j.p.w.t.s.SemaphoreStep$State#get: Initializing state in C:\src\lrp\target\tmp\j h18078805067805581600
   2.660 [id=89]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-1/1
   2.660 [id=89]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-2/1
   2.675 [id=89]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-3/1
   2.691 [id=89]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-4/1
   2.707 [id=89]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-5/1
   3.582 [id=494]	WARNING	o.j.h.t.RemainingActivityListener#onTearDown: p #1 still seems to be running, which could break deletion of log files or metadata
   3.595 [id=494]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   3.631 [id=494]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
=== Starting chaosOnRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   0.922 [id=567]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49193/jenkins/
   1.406 [id=567]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.422 [id=579]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.429 [id=584]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.429 [id=590]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h18078805067805581600\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.616 [id=583]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.632 [id=584]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.632 [id=579]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   1.769 [id=583]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   1.785 [id=583]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   1.785 [id=586]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   1.785 [id=588]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   1.792 [id=590]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   1.846 [id=101]	WARNING	o.j.p.w.f.FlowExecutionList$ResumeStepExecutionListener$1#onSuccess: Resuming p#1, which is missing from FlowExecutionList, so registering it now
   1.846 [id=101]	WARNING	o.j.p.w.f.FlowExecutionList$DefaultStorage#register: p#1 was already in the list: [p#1, p#2, p#3]
   1.909 [id=586]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   1.936 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-1/1 as success
   1.936 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-2/1 as success
   1.936 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-3/1 as success
   1.936 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-4/1 as success
   1.936 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-5/1 as success
   2.042 [id=90]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-1/2
   2.058 [id=90]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-2/2
   2.121 [id=101]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-3/2
   2.121 [id=101]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-4/2
   2.136 [id=101]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-5/2
   2.152 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-1/2 as success
   2.152 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-2/2 as success
   2.152 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-3/2 as success
   2.152 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-4/2 as success
   2.164 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-5/2 as success
   2.190 [id=89]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-1/3
   2.248 [id=89]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-2/3
   2.295 [id=101]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-3/3
   2.300 [id=101]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-4/3
   2.331 [id=160]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-5/3
   2.331 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-1/3 as success
   2.331 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-2/3 as success
   2.347 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-3/3 as success
   2.347 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-4/3 as success
   2.347 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-5/3 as success
   2.529 [id=89]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #1
   2.685 [id=89]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #2
   2.810 [id=90]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #3
   2.842 [id=567]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   2.852 [id=567]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
   2.962 [id=1]	INFO	o.j.h.t.TemporaryDirectoryAllocator#dispose: deleting C:\src\lrp\target\tmp\j h18078805067805581600
[INFO] Tests run: 5, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 54.85 s -- in org.jenkins.plugins.lockableresources.LockStepWithRestartTest
[INFO] 
[INFO] Results:
[INFO] 
[INFO] Tests run: 5, Failures: 0, Errors: 0, Skipped: 0
[INFO] 
[INFO] ------------------------------------------------------------------------
[INFO] BUILD SUCCESS
[INFO] ------------------------------------------------------------------------
[INFO] Total time:  01:52 min
[INFO] Finished at: 2026-08-19T16:00:11+09:00
[INFO] ------------------------------------------------------------------------
```
</details>

<details><summary>docker run console output</summary>


```

=== Checking out 148d8eb ===
HEAD is now at 148d8eb Annotate remote acquire status endpoint with GET (#1076)
148d8ebc6d9453403cfbd810d45623352979071a 2026-08-12 08:25:47 +0000 Annotate remote acquire status endpoint with GET (#1076)

=== Environment ===
rev.requested   : 148d8eb
rev.head        : 148d8ebc6d9453403cfbd810d45623352979071a 2026-08-12 08:25:47 +0000 Annotate remote acquire status endpoint with GET (#1076)
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
[INFO] Copying 117 resources from src\main\resources to target\classes
[INFO] 
[INFO] --- flatten:1.7.3:flatten (flatten) @ lockable-resources ---
[INFO] Generating flattened POM of project org.6wind.jenkins:lockable-resources:hpi:999999-SNAPSHOT...
[INFO] 
[INFO] --- compiler:3.15.0:compile (default-compile) @ lockable-resources ---
[INFO] Recompiling the module because of changed source code.
[INFO] Compiling 45 source files with javac [debug parameters release 17] to target\classes
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
[INFO] org.jenkins.plugins.lockableresources.remote.RemoteLockManager indexed under hudson.Extension
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStep.java:[96,12] Generating org/jenkins/plugins/lockableresources/LockStep.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStepResource.java:[55,12] Generating org/jenkins/plugins/lockableresources/LockStepResource.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockableResource.java:[204,12] Generating org/jenkins/plugins/lockableresources/LockableResource.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockableResourceProperty.java:[21,12] Generating org/jenkins/plugins/lockableresources/LockableResourceProperty.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RemoteConnection.java:[36,12] Generating org/jenkins/plugins/lockableresources/RemoteConnection.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RequiredResourcesProperty.java:[55,12] Generating org/jenkins/plugins/lockableresources/RequiredResourcesProperty.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/UpdateLockStep.java:[66,12] Generating org/jenkins/plugins/lockableresources/UpdateLockStep.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockableResourceProperty.java:[14,8] Generating org/jenkins/plugins/lockableresources/LockableResourceProperty.javadoc
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockableResources.java:[15,8] Generating org/jenkins/plugins/lockableresources/LockableResources.javadoc
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/actions/LockableResourcesRootAction.java:[52,8] Generating org/jenkins/plugins/lockableresources/actions/LockableResourcesRootAction.javadoc
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockableResource.java:[58,8] Generating org/jenkins/plugins/lockableresources/LockableResource.javadoc
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStep.java:[255,38] Generating org/jenkins/plugins/lockableresources/LockStep/DescriptorImpl/doCheckResourceSelectStrategy.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockableResourcesManager.java:[267,27] Generating org/jenkins/plugins/lockableresources/LockableResourcesManager/doCheckForcedServerId.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RequiredResourcesProperty.java:[271,31] Generating org/jenkins/plugins/lockableresources/RequiredResourcesProperty/DescriptorImpl/doCheckResourceNumber.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/UpdateLockStep.java:[263,31] Generating org/jenkins/plugins/lockableresources/UpdateLockStep/DescriptorImpl/doCheckRemoveLabels.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/UpdateLockStep.java:[284,31] Generating org/jenkins/plugins/lockableresources/UpdateLockStep/DescriptorImpl/doCheckDeleteResource.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStep.java:[249,38] Generating org/jenkins/plugins/lockableresources/LockStep/DescriptorImpl/doCheckResource.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RequiredResourcesProperty.java:[337,48] Generating org/jenkins/plugins/lockableresources/RequiredResourcesProperty/DescriptorImpl/doAutoCompleteResourceNames.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStep.java:[223,41] Generating org/jenkins/plugins/lockableresources/LockStep/DescriptorImpl/doAutoCompleteResource.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RequiredResourcesProperty.java:[205,31] Generating org/jenkins/plugins/lockableresources/RequiredResourcesProperty/DescriptorImpl/doCheckResourceNames.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/UpdateLockStep.java:[249,31] Generating org/jenkins/plugins/lockableresources/UpdateLockStep/DescriptorImpl/doCheckAddLabels.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RemoteConnection.java:[127,31] Generating org/jenkins/plugins/lockableresources/RemoteConnection/DescriptorImpl/doCheckUrl.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStep.java:[243,38] Generating org/jenkins/plugins/lockableresources/LockStep/DescriptorImpl/doCheckLabel.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/UpdateLockStep.java:[232,31] Generating org/jenkins/plugins/lockableresources/UpdateLockStep/DescriptorImpl/doCheckResource.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RequiredResourcesProperty.java:[242,31] Generating org/jenkins/plugins/lockableresources/RequiredResourcesProperty/DescriptorImpl/doCheckLabelName.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/LockStepResource.java:[217,38] Generating org/jenkins/plugins/lockableresources/LockStepResource/DescriptorImpl/doCheckResource.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RequiredResourcesProperty.java:[315,41] Generating org/jenkins/plugins/lockableresources/RequiredResourcesProperty/DescriptorImpl/doAutoCompleteLabelName.stapler
[INFO] /C:/src/lrp/src/main/java/org/jenkins/plugins/lockableresources/RemoteConnection.java:[108,29] Generating org/jenkins/plugins/lockableresources/RemoteConnection/DescriptorImpl/doFillCredentialsIdItems.stapler
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
[INFO] Compiling 45 source files with javac [debug parameters release 17] to target\test-classes
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
   0.203 [id=31]	INFO	o.jvnet.hudson.test.WarExploder#explode: Exploding C:\m2\org\jenkins-ci\main\jenkins-war\2.541.3\jenkins-war-2.541.3.war into C:\src\lrp\target\jenkins-for-test
  11.517 [id=31]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49169/jenkins/
  12.392 [id=31]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
  12.533 [id=46]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
  16.528 [id=46]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
  16.543 [id=53]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h16665851978826152573\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
  18.864 [id=45]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
  18.885 [id=51]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
  18.885 [id=44]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
  19.905 [id=55]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
  19.992 [id=53]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
  19.992 [id=52]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
  19.992 [id=45]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
  20.003 [id=49]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
  20.019 [id=48]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
  20.144 [id=31]	INFO	o.j.p.w.t.s.SemaphoreStep$State#get: Initializing state in C:\src\lrp\target\tmp\j h16665851978826152573
  21.066 [id=90]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart/1
  21.320 [id=31]	WARNING	o.j.h.t.RemainingActivityListener#onTearDown: p #1 still seems to be running, which could break deletion of log files or metadata
  21.341 [id=31]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
  21.403 [id=31]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
=== Starting lockOrderRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   1.001 [id=108]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49169/jenkins/
   1.532 [id=108]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.547 [id=120]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.549 [id=124]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.550 [id=125]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h16665851978826152573\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.756 [id=122]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.756 [id=120]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.756 [id=123]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   1.944 [id=121]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   1.960 [id=121]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   1.960 [id=125]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   1.972 [id=120]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   1.972 [id=127]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   2.096 [id=130]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   2.096 [id=101]	WARNING	o.j.p.w.f.FlowExecutionList$ResumeStepExecutionListener$1#onSuccess: Resuming p#1, which is missing from FlowExecutionList, so registering it now
   2.096 [id=101]	WARNING	o.j.p.w.f.FlowExecutionList$DefaultStorage#register: p#1 was already in the list: [p#1, p#2, p#3]
   2.176 [id=108]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart/1 as success
   2.223 [id=89]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart/2
   2.286 [id=108]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart/2 as success
   2.301 [id=89]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #1
   2.328 [id=101]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart/3
   2.328 [id=108]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart/3 as success
   2.375 [id=89]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #2
   2.421 [id=89]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #3
   2.453 [id=108]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   2.469 [id=108]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
   2.531 [id=1]	INFO	o.j.h.t.TemporaryDirectoryAllocator#dispose: deleting C:\src\lrp\target\tmp\j h16665851978826152573
=== Starting interoperabilityOnRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   0.984 [id=170]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49175/jenkins/
   1.546 [id=170]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.562 [id=183]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.571 [id=189]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.571 [id=182]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h5752980570294301865\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.769 [id=184]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.769 [id=193]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.769 [id=190]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   2.153 [id=189]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   2.168 [id=183]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   2.168 [id=183]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   2.168 [id=187]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   2.172 [id=183]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   2.205 [id=192]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   2.237 [id=170]	INFO	o.j.p.w.t.s.SemaphoreStep$State#get: Initializing state in C:\src\lrp\target\tmp\j h5752980570294301865
   2.346 [id=101]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-interoperabilityOnRestart/1
   2.362 [id=170]	INFO	o.j.p.l.TestHelpers#waitForQueue: Waiting for job to be queued...
   2.377 [id=170]	WARNING	o.j.h.t.RemainingActivityListener#onTearDown: p #1 still seems to be running, which could break deletion of log files or metadata
   2.390 [id=170]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   2.415 [id=170]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
=== Starting interoperabilityOnRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   0.890 [id=220]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49175/jenkins/
   1.390 [id=220]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.406 [id=232]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.410 [id=234]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.411 [id=233]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h5752980570294301865\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.600 [id=237]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.615 [id=238]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.617 [id=236]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   1.745 [id=242]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   1.761 [id=241]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   1.761 [id=233]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   1.761 [id=233]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   1.765 [id=238]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   1.801 [id=232]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   1.806 [id=89]	WARNING	o.j.p.w.f.FlowExecutionList$ResumeStepExecutionListener$1#onSuccess: Resuming p#1, which is missing from FlowExecutionList, so registering it now
   1.806 [id=89]	WARNING	o.j.p.w.f.FlowExecutionList$DefaultStorage#register: p#1 was already in the list: [p#1]
   1.821 [id=220]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-interoperabilityOnRestart/1 as success
   1.852 [id=244]	INFO	o.j.p.l.queue.LockRunListener#onStarted: f #1 acquired lock on [resource1]
   1.899 [id=89]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #1
   1.899 [id=244]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: f #1
   1.931 [id=220]	INFO	o.j.p.l.LockStepWithRestartTest#lambda$interoperabilityOnRestart$3: Waiting for freestyle #1 to start building
   2.038 [id=220]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   2.043 [id=220]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
   2.121 [id=1]	INFO	o.j.h.t.TemporaryDirectoryAllocator#dispose: deleting C:\src\lrp\target\tmp\j h5752980570294301865
=== Starting checkQueueAfterRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   0.969 [id=273]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49180/jenkins/
   1.484 [id=273]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.500 [id=286]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.508 [id=290]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.509 [id=295]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h11186776770808613788\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.691 [id=291]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.692 [id=293]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.692 [id=295]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   2.634 [id=296]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   2.650 [id=289]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   2.650 [id=294]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   2.650 [id=294]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   2.651 [id=296]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   2.685 [id=294]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   2.763 [id=273]	INFO	o.j.p.l.LockableResourcesManager#reserve: reserve() called user='test' resources=[resource1] reason='null'
   2.763 [id=273]	INFO	o.j.p.l.LockableResourcesManager#reserve: reserve() succeeded user='test' resources=[resource1]
   2.763 [id=273]	INFO	o.j.p.l.LockableResourcesManager#reserve: reserve() called user='test' resources=[resource2] reason='null'
   2.763 [id=273]	INFO	o.j.p.l.LockableResourcesManager#reserve: reserve() succeeded user='test' resources=[resource2]
   2.888 [id=273]	WARNING	o.j.h.t.RemainingActivityListener#onTearDown: p #1 still seems to be running, which could break deletion of log files or metadata
   2.903 [id=273]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   2.921 [id=273]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
=== Starting checkQueueAfterRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   0.907 [id=325]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49180/jenkins/
   1.391 [id=325]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.407 [id=337]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.413 [id=345]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.414 [id=348]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h11186776770808613788\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.598 [id=343]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.614 [id=337]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.614 [id=344]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   1.728 [id=346]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   1.728 [id=341]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   1.744 [id=345]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   1.744 [id=345]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   1.746 [id=343]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   1.782 [id=348]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
  10.026 [id=325]	INFO	o.j.p.l.TestHelpers#clickButton: unreserve on resource1
  10.182 [id=325]	WARNING	o.j.h.t.RemainingActivityListener#onTearDown: p #1 still seems to be running, which could break deletion of log files or metadata
  10.182 [id=89]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #1
  10.209 [id=325]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
  10.225 [id=325]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
  10.350 [id=1]	INFO	o.j.h.t.TemporaryDirectoryAllocator#dispose: deleting C:\src\lrp\target\tmp\j h11186776770808613788
=== Starting testReserveOverRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   0.953 [id=391]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49188/jenkins/
   1.531 [id=391]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.547 [id=404]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.553 [id=403]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.553 [id=413]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h16181887582334790564\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.721 [id=412]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.737 [id=405]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.737 [id=409]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   2.997 [id=413]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   3.009 [id=407]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   3.009 [id=403]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   3.009 [id=414]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   3.014 [id=404]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   3.047 [id=414]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   3.063 [id=391]	INFO	o.j.p.l.LockableResourcesManager#reserve: reserve() called user='user' resources=[resource1] reason='null'
   3.063 [id=391]	INFO	o.j.p.l.LockableResourcesManager#reserve: reserve() succeeded user='user' resources=[resource1]
   3.203 [id=391]	INFO	o.j.p.l.TestHelpers#waitForQueue: Waiting for job to be queued...
   3.203 [id=391]	WARNING	o.j.h.t.RemainingActivityListener#onTearDown: p #1 still seems to be running, which could break deletion of log files or metadata
   3.229 [id=391]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   3.251 [id=391]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
=== Starting testReserveOverRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   0.890 [id=442]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49188/jenkins/
   1.390 [id=442]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.390 [id=454]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.400 [id=460]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.401 [id=465]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h16181887582334790564\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.583 [id=456]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.583 [id=458]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.583 [id=454]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   1.718 [id=463]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   1.718 [id=461]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   1.733 [id=461]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   1.733 [id=465]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   1.737 [id=460]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   1.757 [id=462]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   1.872 [id=466]	INFO	o.j.p.l.queue.LockRunListener#onStarted: f #1 acquired lock on [resource1]
   1.886 [id=466]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: f #1
   1.917 [id=89]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #1
   2.037 [id=442]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   2.060 [id=442]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
   2.170 [id=1]	INFO	o.j.h.t.TemporaryDirectoryAllocator#dispose: deleting C:\src\lrp\target\tmp\j h16181887582334790564
=== Starting chaosOnRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   0.828 [id=494]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49193/jenkins/
   1.391 [id=494]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.391 [id=507]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.402 [id=513]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.402 [id=515]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h18078805067805581600\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.574 [id=508]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.587 [id=506]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.587 [id=516]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   2.017 [id=506]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   2.032 [id=513]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   2.032 [id=510]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   2.032 [id=517]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   2.034 [id=506]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   2.066 [id=511]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   2.113 [id=494]	INFO	o.j.p.w.t.s.SemaphoreStep$State#get: Initializing state in C:\src\lrp\target\tmp\j h18078805067805581600
   2.660 [id=89]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-1/1
   2.660 [id=89]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-2/1
   2.675 [id=89]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-3/1
   2.691 [id=89]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-4/1
   2.707 [id=89]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-5/1
   3.582 [id=494]	WARNING	o.j.h.t.RemainingActivityListener#onTearDown: p #1 still seems to be running, which could break deletion of log files or metadata
   3.595 [id=494]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   3.631 [id=494]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
=== Starting chaosOnRestart(org.jenkins.plugins.lockableresources.LockStepWithRestartTest)
   0.922 [id=567]	INFO	o.jvnet.hudson.test.JenkinsRule#createWebServer2: Running on http://localhost:49193/jenkins/
   1.406 [id=567]	INFO	jenkins.model.Jenkins#<init>: Starting version 2.541.3
   1.422 [id=579]	INFO	jenkins.InitReactorRunner$1#onAttained: Started initialization
   1.429 [id=584]	INFO	jenkins.InitReactorRunner$1#onAttained: Listed all plugins
   1.429 [id=590]	INFO	j.b.api.BouncyCastlePlugin#start: C:\src\lrp\target\tmp\j h18078805067805581600\plugins\bouncycastle-api\WEB-INF\optional-lib not found; for non RealJenkinsRule this is fine and can be ignored.
   1.616 [id=583]	INFO	jenkins.InitReactorRunner$1#onAttained: Prepared all plugins
   1.632 [id=584]	INFO	jenkins.InitReactorRunner$1#onAttained: Started all plugins
   1.632 [id=579]	INFO	jenkins.InitReactorRunner$1#onAttained: Augmented all extensions
   1.769 [id=583]	INFO	jenkins.InitReactorRunner$1#onAttained: System config loaded
   1.785 [id=583]	INFO	jenkins.InitReactorRunner$1#onAttained: System config adapted
   1.785 [id=586]	INFO	jenkins.InitReactorRunner$1#onAttained: Loaded all jobs
   1.785 [id=588]	INFO	o.j.p.l.nodes.NodesMirror#createNodeResources: lockable-resources-plugin: configure node resources
   1.792 [id=590]	INFO	jenkins.InitReactorRunner$1#onAttained: Configuration for all jobs updated
   1.846 [id=101]	WARNING	o.j.p.w.f.FlowExecutionList$ResumeStepExecutionListener$1#onSuccess: Resuming p#1, which is missing from FlowExecutionList, so registering it now
   1.846 [id=101]	WARNING	o.j.p.w.f.FlowExecutionList$DefaultStorage#register: p#1 was already in the list: [p#1, p#2, p#3]
   1.909 [id=586]	INFO	jenkins.InitReactorRunner$1#onAttained: Completed initialization
   1.936 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-1/1 as success
   1.936 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-2/1 as success
   1.936 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-3/1 as success
   1.936 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-4/1 as success
   1.936 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-5/1 as success
   2.042 [id=90]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-1/2
   2.058 [id=90]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-2/2
   2.121 [id=101]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-3/2
   2.121 [id=101]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-4/2
   2.136 [id=101]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-5/2
   2.152 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-1/2 as success
   2.152 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-2/2 as success
   2.152 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-3/2 as success
   2.152 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-4/2 as success
   2.164 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-5/2 as success
   2.190 [id=89]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-1/3
   2.248 [id=89]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-2/3
   2.295 [id=101]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-3/3
   2.300 [id=101]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-4/3
   2.331 [id=160]	INFO	o.j.p.w.t.s.SemaphoreStep$Execution#start: Blocking wait-inside-lockOrderRestart-5/3
   2.331 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-1/3 as success
   2.331 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-2/3 as success
   2.347 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-3/3 as success
   2.347 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-4/3 as success
   2.347 [id=567]	INFO	o.j.p.w.test.steps.SemaphoreStep#success: Unblocking wait-inside-lockOrderRestart-5/3 as success
   2.529 [id=89]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #1
   2.685 [id=89]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #2
   2.810 [id=90]	INFO	o.j.p.l.queue.LockRunListener#onCompleted: p #3
   2.842 [id=567]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Stopping Jenkins
   2.852 [id=567]	INFO	hudson.lifecycle.Lifecycle#onStatusUpdate: Jenkins stopped
   2.962 [id=1]	INFO	o.j.h.t.TemporaryDirectoryAllocator#dispose: deleting C:\src\lrp\target\tmp\j h18078805067805581600
[INFO] Tests run: 5, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 54.85 s -- in org.jenkins.plugins.lockableresources.LockStepWithRestartTest
[INFO] 
[INFO] Results:
[INFO] 
[INFO] Tests run: 5, Failures: 0, Errors: 0, Skipped: 0
[INFO] 
[INFO] ------------------------------------------------------------------------
[INFO] BUILD SUCCESS
[INFO] ------------------------------------------------------------------------
[INFO] Total time:  01:52 min
[INFO] Finished at: 2026-08-19T16:00:11+09:00
[INFO] ------------------------------------------------------------------------
Run 1/1 exit code: 0

=== Summary ===
rev      : 148d8ebc6d9453403cfbd810d45623352979071a 2026-08-12 08:25:47 +0000 Annotate remote acquire status endpoint with GET (#1076)
pattern  : LockStepWithRestartTest

run 1: PASS (exit 0)
```
</details>


