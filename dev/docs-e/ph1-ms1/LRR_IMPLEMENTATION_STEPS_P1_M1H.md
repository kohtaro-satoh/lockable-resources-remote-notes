# M1H Implementation Steps (Remote lock - Phase 1 / M1H: PR #1055 CI follow-up)

> Design: `LRR_DESIGN_P1_M1H.md` / starting review: `LRR_REVIEW_P1_M1H.md`
> Branch: `feature/1025-remote-lr-p1-m1` (HEAD `5136daa` at M1H start)

### Step 1: security #49/#51 (doCheckUrl)

- [x] `RemoteConnection.java`: add `@org.kohsuke.stapler.verb.POST` to `doCheckUrl`
- [x] add `Jenkins.get().checkPermission(Jenkins.ADMINISTER)` at the start of the method
- [x] `RemoteConnection/config.jelly`: change `url` `<f:textbox/>` to `<f:textbox checkMethod="post"/>`
- [x] add imports (`jenkins.model.Jenkins`, `org.kohsuke.stapler.verb.POST`)

### Step 2: security #50 (doCheckForcedServerId)

- [x] `LockableResourcesManager.java`: add `@POST` to `doCheckForcedServerId` (ADMINISTER already present)
- [x] `LRM/config.jelly`: add `checkMethod="post"` to the `forcedServerId` `<f:textbox .../>`
- [x] add import (`org.kohsuke.stapler.verb.POST`)

### Step 3: security #52 = B2 (pure-read GET)

- [x] `RemoteApiV1Action.java`: remove `RemoteLockManager.get().touchPoll(lockId);` from `doIndex` (tidy comment, note pure read)
- [x] `RemoteLockManager.java`: remove `touchPoll(String)`
- [x] `RemoteLockManager.java`: remove `getQueuePollExpiryMs()` + `DEFAULT_QUEUE_POLL_EXPIRY_MS`
- [x] `RemoteLockManager.java`: remove the QUEUED branch (`QUEUE_EXPIRED`) of `maybeScanStale`. Keep ACQUIRED STALE / terminal TTL
- [x] `RemoteLockRecord.java`: remove `lastPolledAt` / `polled()` / `getLastPolledAt()`, tidy related comments
- [x] grep-confirm no remaining poll-keepalive refs in `src/main`

### Step 4: tests

- [x] `RemoteLockManagerTest`: remove the two poll-keepalive cases (using `queuePollExpiryMs`, expecting `QUEUE_EXPIRED`)
- [x] add `queuedRecordExpiresViaQueueTimeout` (driven by `checkTimeouts()`, `LOCK_WAIT_TIMEOUT`, no resource grab after expiry)
- [x] add `queuedRecordWithoutTimeoutSurvivesWithoutPolling` (QUEUED survives without polling; `find()` pure read; promotion on release)
- [x] `RemoteConnectionTest`: make `testDoCheckUrl` `@WithJenkins`, add `testDoCheckUrlRequiresAdmin` (non-admin → AccessDeniedException)

### Step 5: build, verify, sync, commit

- [x] `dev/run-mvn-verify.sh` (in-place, `mvn clean verify`) success → `dev/reports/20260620220250-mvn-verify.md` (383/0/1skip, all gates ok)
- [x] `dev/jenkins-env/run-e2e.sh` all pass → `dev/reports/20260620222354-e2e-test.md` (20/20)
- [x] plugin commit + rebase `feature/1025-remote-lr-p1-m1` onto `upstream/master` (`8f03dbf`) (no conflict, 4/4 replay)
- [ ] re-run `dev/run-mvn-verify.sh` after rebase (with the new BOM #1057) success → check `dev/reports/*-mvn-verify.md`
- [ ] sync docs-e (REVIEW/DESIGN/STEPS/RESULT), create `LRR_RESULT_P1_M1H.md`, update README index/Status
- [ ] notes commit (no Co-Authored-By). **Do not push**

## Changed files (plugin)

| File | Change | State |
|---|---|---|
| `RemoteConnection.java` | `@POST` + ADMINISTER on `doCheckUrl` | done |
| `RemoteConnection/config.jelly` | `checkMethod="post"` on `url` | done |
| `LockableResourcesManager.java` | `@POST` on `doCheckForcedServerId` | done |
| `LockableResourcesManager/config.jelly` | `checkMethod="post"` on `forcedServerId` | done |
| `actions/RemoteApiV1Action.java` | remove `touchPoll` from `doIndex` | done |
| `remote/RemoteLockManager.java` | remove poll-keepalive set + QUEUED-expiry branch | done |
| `remote/RemoteLockRecord.java` | remove `lastPolledAt`/`polled()`/`getLastPolledAt()` | done |
| `remote/RemoteLockManagerTest.java` | replace 2 poll-keepalive cases | done |
| `RemoteConnectionTest.java` | make `doCheckUrl` test `@WithJenkins`, add non-admin permission test | done |
| `pom.xml` | pull in the BOM bump (#1057) via rebase | pending (Step 5) |
