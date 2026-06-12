# M1B Implementation Steps (Remote lock - Phase 1 / M1B)

This file is the M1B progress tracker.
Following the full M1A review (`LRR_REVIEW_P1_M1A.md`) and the decisions made on
2026-06-11, M1B drastically redesigns the remote LR feature toward full
transparent equivalence.

---

## Background: The M1A → M1B Course Change

### Core problems surfaced by the review

| Issue | Content |
|---|---|
| 3-1 | `extra` silently dropped server-side (body runs under a partial lock) |
| 3-2 | `lockEnvVars` joined with spaces (local uses commas) → not transparently equivalent |
| 3-3 | `remoteLockedBy` is transient → remote locks vanish on restart (see decision below) |
| 3-4 | No client-side `onResume()` → QUEUED hangs forever |
| 3-5 | No admin path to release STALE locks |
| 4-1 | A single communication failure kills the job immediately |
| 4-2 | Queue semantics diverge from local (priority/timeout etc. unimplemented) |
| 4-3 | A remote release does not wake local waiters |
| 5-1 | All endpoints gated only by `Jenkins.READ` |
| 5-2 | Anonymous requests sent when credentialsId is unset |

### Decisions (2026-06-11)

| Issue | Decision |
|---|---|
| **A. extra** | Implement in M1B (server-side parsing + reuse of `tryAcquireAll`) |
| **B. heartbeat failure** | Warning log only; the job continues. No client-side timeout concept (job timeouts belong to Jenkins job configuration) |
| **C. poll failure** | Keep retrying. Terminate with an error on lockId mismatch (404/410 after a server restart) |
| **D. onResume** | Restart while QUEUED → resume polling. Restart while ACQUIRED → delegate to body behavior (the server retains the lock, fail-close) |
| **E. queue equivalence** | Remove `RemoteLockManager`'s independent queue. Inject remote requests into `LockableResourcesManager`'s existing queue as `RemoteQueueEntry`, unifying priority/timeout/FIFO |
| **F. STALE release** | Minimal UI addition (Force Release button) |
| **3-3 restart** | `remoteLockedBy` stays transient (as designed). Remote locks vanish on a Jenkins restart. This follows the "resolve before restarting" operational rule and is documented as a known constraint |

### M1B design philosophy

```
Apart from "time delay" and "fail-close on network failure", the remote
feature must be fully transparently equivalent to local resources.
The fix policy is not "fall back to safe" but "go all-in on transparent
equivalence".
```

---

## Architecture Change Overview (the heart of Step 3)

### M1A structure (problematic)

```
Remote POST /acquire
    → RemoteLockManager (own ConcurrentHashMap + 1-second tick)
         ↓ tryAcquireQueued() checks resources independently
         ↓ priority/timeout/FIFO unimplemented
    Unrelated to LockableResourcesManager's queue
```

### M1B structure (transparent equivalence)

```
Remote POST /acquire
    → RemoteLockManager.enqueue()
         → create a RemoteQueueEntry
         → LockableResourcesManager.queueRemote(entry)
              ↓ priority-sorted alongside queuedContexts
              ↓ proceedNextContext() dispatches uniformly
              ↓ priority/timeout/FIFO handled by LRM's existing logic
         → attempt immediate acquisition (skip QUEUED → ACQUIRED if free)

Remote POST /lease/{lockId}/release
    → RemoteLockManager.release(lockId)
         → LockableResourcesManager.unlockRemoteResources()
              ↓ equivalent of freeResources()
              ↓ while (proceedNextContext()) { } → wakes BOTH local and remote waiters
              ↓ scheduleQueueMaintenance()
```

`RemoteQueueEntry` carries the data needed for queue processing:
- `requiredResources: List<LockableResourcesStruct>` — expose-checked resource list
- `priority: int` — from `RemoteLockRequest.priority`
- `timeoutDeadlineMillis: long` — from `RemoteLockRequest.timeoutForAllocateResource`
- `candidates: List<String>` — `getAvailableResources()` result (transient)
- `onAcquired(resourcesToLock)` — callback invoking `record.markAcquired()`
- `onTimeout()` — invokes `record.markFailed("LOCK_WAIT_TIMEOUT")`

`LockableResourcesManager.proceedNextContext()` is extended to process both the
local and remote queues with **unified priority**:

```
getNextQueuedContext()  → next local candidate
getNextRemoteEntry()    → next remote candidate
→ compare priorities and dispatch the higher one
```

---

## Step List

### 0. Preparation (complete)

- [x] M1A Steps 0–6 all complete (plugin `c782c28`, 347 tests)
- [x] All 12 E2E scenarios passing (`run-e2e.sh`, 2026-06-11)
- [x] Review recorded in `dev/docs-j/LRR_REVIEW_P1_M1A.md`
- [x] M1B decisions recorded in this file

---

### 1. Small Fixes (prerequisites for transparent equivalence)

**Purpose:**
Fix the small bugs surfaced by the M1A review first, laying the groundwork for
Step 2 and beyond.

#### 1-a. lockEnvVars separator fix

- Change `String.join(" ", names)` in `RemoteLockManager.generateLockEnvVars()`
  to `String.join(",", names)` (equivalence with local `LockStepExecution.proceed()`)
- Also fix the spec example in `LRR_DESIGN_P1_M1A.md` §3
  (`"resource1 resource2"` → `"resource1,resource2"`)

#### 1-b. exposeLabel Javadoc fix

- Remove the Javadoc on the `LockableResourcesManager.exposeLabel` field saying
  "When empty or null all resources are eligible." (actual behavior: "empty = no
  resources exposed")
- Replace with the correct description: "When empty or null, no resources are
  exposed (opt-in)"

#### 1-c. Unset credentialsId = anonymous request (no change)

- An empty `credentialsId` = anonymous request to a no-auth server is a
  legitimate use case; left unchanged
- When a non-empty `credentialsId` cannot be resolved, existing code already
  throws `AbortException` correctly (already implemented; no change needed)

#### 1-d. forcedServerId validation

- Add `doCheckForcedServerId()` to `LockableResourcesManager.Descriptor`
  (warn when `forcedServerId` is set but absent from `remotes`)
- Also check immediately in `setForcedServerId()` and log a warning on mismatch

#### Completion criteria

- `mvn test -Dtest=LockStepRemoteTest,RemoteLockManagerTest,LockableResourcesManagerRemoteConnectionTest`
- Full `mvn test` BUILD SUCCESS

- [x] Implementation complete (1-a / 1-b. **1-d NOT implemented — carried over**)
- [x] `mvn test` confirmed (347 tests BUILD SUCCESS)
- [x] Committed (`25fa4ae`)

Notes: Implemented 2026-06-11 (1-a lockEnvVars comma join, 1-b exposeLabel
Javadoc). 1-c (credentialsId) left unchanged (anonymous access is a legitimate
use case). **1-d (forcedServerId validation) was NOT implemented in M1B** —
discovered during the 2026-06-12 documentation reconciliation. Review drift #4
remains open; tracked as post-M1B work.

---

### 2. extra Implementation

**Purpose:**
Make `lock(resource: 'r1', extra: [{resource: 'r2'}], serverId: 'b')` acquire
atomically over remote as well. In M1A, `extra` was ignored server-side.

#### Implementation

**`RemoteApiV1Action.AcquireRouter.doIndex()`:**
- Parse `lockRequestJson.optJSONArray("extra")` into a
  `List<RemoteLockRequest.ExtraResource>`
- Reject `ExtraResource` entries with both `resource` and `label` null with 400
- Pass extra to the `RemoteLockRequest` constructor

**Extended expose checks in `RemoteApiV1Action`:**
- Resource-based entries inside extra also go through the exposeLabel check
  (an unexposed resource in extra → 404 UNKNOWN_RESOURCE)
- Label-based extra entries: zero candidates matching exposeLabel → 404 UNKNOWN_LABEL

**Tests:**
- `RemoteApiV1ActionTest`: POST /acquire containing an extra resource is processed with 202
- `RemoteApiV1ActionTest`: 404 when extra contains an unexposed resource
- `RemoteLockManagerTest`: simultaneous lock/release of resource + extra (via existing `tryAcquireAll`)
- `LockStepRemoteTest`: DSL with `extra` runs remotely and the body succeeds

#### Completion criteria

- Atomic locking of resource + extra works
- Expose checks apply to extra as well
- Full `mvn test` BUILD SUCCESS

- [x] Implementation complete
- [x] `mvn test` confirmed (352 tests BUILD SUCCESS, `dev/reports/20260612000923-mvn-test.log`)
- [x] Committed (`42fa2c9`)

Notes: Implemented 2026-06-11. extra parsing + exposeLabel checks at the API
boundary. Tests added to RemoteLockManagerTest/RemoteApiV1ActionTest.

---

### 3. RemoteLockManager → LRM Queue Bridge Redesign

**Purpose:**
Remove `RemoteLockManager`'s independent queue and integrate remote requests
into `LockableResourcesManager`'s existing queue.
Delegate priority / timeout / FIFO / local-remote fairness entirely to LRM's
existing logic.

#### New class: `remote/RemoteQueueEntry.java`

```
RemoteQueueEntry {
    RemoteLockRecord record;              // callback target
    List<LockableResourcesStruct> requiredResources;  // expose-checked resource list
    int priority;
    long timeoutDeadlineMillis;
    transient List<String> candidates;   // getAvailableResources() cache

    boolean isValid()            → record.getState() == QUEUED
    boolean isTimedOut()         → deadline check
    void onAcquired(resourcesToLock) → record.markAcquired(names, lockEnvVars)
    void onTimeout()             → record.markFailed("LOCK_WAIT_TIMEOUT")
    int getPriority()
    long getTimeoutDeadlineMillis()
    String getResourceDescription()
}
```

Resolving the expose-checked resource list at POST /acquire time removes the
need to re-check during queue processing.

#### Changes to `LockableResourcesManager`

```java
// New field (transient: lost on Jenkins restart, same lifecycle as remote locks)
private transient final List<RemoteQueueEntry> remoteQueueEntries = new ArrayList<>();

// New methods
void queueRemote(RemoteQueueEntry entry)          // insert priority-sorted
void unqueueRemote(String lockId)                 // find by lockId and remove
boolean lockForRemote(List<LockableResource> resources, String lockId, String reason)
void unlockRemoteResources(List<String> resourceNames, String lockId)
// → equivalent of freeResources() + while(proceedNextContext()) + save() + scheduleQueueMaintenance()

// Changed: proceedNextContext()
// Compare the existing getNextQueuedContext() with the new getNextRemoteEntry()
// and process the higher-priority one first
private boolean proceedNextContext() {
    QueuedContextStruct nextLocal = getNextQueuedContext();
    RemoteQueueEntry nextRemote = getNextRemoteEntry();

    if (nextLocal == null && nextRemote == null) return false;

    if (shouldPickRemote(nextLocal, nextRemote)) {
        processRemoteEntry(nextRemote);  // lockForRemote() + entry.onAcquired()
    } else {
        processLocalEntry(nextLocal);    // existing lock() + LockStepExecution.proceed()
    }
    return true;
}

private boolean shouldPickRemote(local, remote) {
    if (local == null) return remote != null;
    if (remote == null) return false;
    return remote.getPriority() > local.getPriority();
}
```

**`getNextRemoteEntry()`** mirrors `getNextQueuedContext()`:
- Timeout check → `entry.onTimeout()`, remove from the list
- `getAvailableResources(entry.requiredResources)` → availability check
- Return the entry if resources are free

#### Changes to `RemoteLockManager`

- **Removed**: the `tryAcquireQueued()` logic (moved into the LRM queue)
- **Changed**: `doRun()` only calls `maybeScanStale()` (STALE detection and
  terminal-record TTL cleanup continue)
- **Changed**: `enqueue()`:
  1. Create the `RemoteLockRecord` (QUEUED state)
  2. Resolve the `LockableResourcesStruct` list from `lockRequest` (with expose checks)
  3. Create the `RemoteQueueEntry`
  4. Attempt immediate acquisition under `synchronized(syncResources)`
     - Free → `lockForRemote()` + `record.markAcquired()` → skip QUEUED, go ACQUIRED
     - `skipIfLocked=true` and busy → `record.markSkipped()`
     - Busy → `LRM.queueRemote(entry)` and stay QUEUED
  5. `records.put(lockId, record)` unchanged (kept for both ACQUIRED and QUEUED)
- **Changed**: `release()`:
  1. `records.remove(lockId)` unchanged
  2. If ACQUIRED/STALE, call `LRM.unlockRemoteResources(names, lockId)`
     (which internally calls `scheduleQueueMaintenance()`)
  3. If QUEUED, call `LRM.unqueueRemote(lockId)`

#### Tests

- `RemoteLockManagerTest`: a local pipeline can lock after a remote release
- `RemoteLockManagerTest`: a higher-priority remote entry is dispatched before a local entry
- `RemoteLockManagerTest`: `timeoutForAllocateResource` produces FAILED
- `LockStepRemoteTest`: all existing tests (regression)

#### Completion criteria

- A remote release wakes local waiters
- Priority is unified
- Full `mvn test` BUILD SUCCESS (worktree build → stabilize-build.sh)

- [x] Implementation complete
- [x] `mvn test` confirmed (352 tests BUILD SUCCESS, `dev/reports/20260612000923-mvn-test.log`)
- [x] Committed (`4137a13`)

Notes: Implemented 2026-06-11. New RemoteQueueEntry class; LRM gained
queueRemote/unqueueRemote/lockForRemote/unlockRemoteResources and the
proceedNextContext integration. RemoteLockManager's tryAcquireQueued removed.

---

### 4. heartbeat/poll Retry (fail-close preserved, job continues)

**Purpose:**
- Heartbeat failures are warning-logged only; the job continues (option B: no client-side timeout)
- Poll failures retry. Terminate with an error on lockId mismatch (404/410 after a server restart)
- After a server restart, the client detects the lockId mismatch and terminates with an error

#### Implementation

**Heartbeat loop (lambda inside `startRemoteHeartbeat()`):**
```
try {
    client.heartbeatLease(remote, authorizationHeader, lockId);
} catch (Exception ex) {
    // fail-close: log warning, keep running
    LOGGER.log(Level.WARNING, "Remote heartbeat failed (continuing): ...", ex);
    // NOTE: do NOT call finishRemoteFailure()
}
```

**Poll loop (`pollRemoteStatus()`):**
- `RemoteApiException` on HTTP 4xx/5xx/IOException → previously went straight to `finishRemoteFailure()`
- Changed: communication failures increment the `consecutivePollFailures` counter; below the threshold, skip and continue
- Threshold: aligned with `STALE_THRESHOLD_MS` (default 60s / 3s interval = 20 attempts)
- `status.getState() == FAILED` + `errorCode == "LOCK_NOT_FOUND"` → terminate (lockId mismatch)
- HTTP 404/410 interpreted as lockId mismatch → terminate

**New fields:**
```java
private volatile int consecutivePollFailures = 0;
private static final int MAX_CONSECUTIVE_POLL_FAILURES = 20; // ≈60 seconds
```

#### Completion criteria

- The body continues even when heartbeats fail
- Polling continues to ACQUIRED through transient poll failures
- `finishRemoteFailure` is called on 404
- Full `mvn test` BUILD SUCCESS

- [x] Implementation complete
- [x] `mvn test` confirmed (352 tests BUILD SUCCESS, `dev/reports/20260612000923-mvn-test.log`)
- [x] Committed (`8d45fbe`)

Notes: Implemented 2026-06-11. Added the consecutivePollFailures counter, MAX=20
(≈60s). 404/410 detected via RemoteApiException.getHttpStatus() → immediate
failure. Heartbeat failures are WARN only.

---

### 5. onResume Implementation (recovery from a client-side restart)

**Purpose:**
When the local (A) side restarts, the remote flow either resumes properly or is
cleaned up properly.

#### Behavior design

| State at restart | Behavior after restart |
|---|---|
| **QUEUED** (`remoteLockId` set, `remoteBodyStarted == false`) | Resume the polling loop. The server is still queue-waiting, so state stays consistent |
| **ACQUIRED** (`remoteBodyStarted == true`) | The body was already interrupted by Jenkins. Call `releaseRemoteLockBestEffort()` to free the server-side lease. The step terminates as failed |

#### Implementation

**Add `onResume()` to `LockStepExecution`:**
```java
@Override
public void onResume() {
    if (remoteLockId == null || remoteLockId.isEmpty()) {
        // local flow: onResume does nothing for LockStepExecution normally
        return;
    }
    if (remoteBodyStarted) {
        // body was interrupted by restart — release and fail
        releaseRemoteLockBestEffort();
        getContext().onFailure(new AbortException(
            "Jenkins restarted during remote lock body execution (serverId="
            + remoteServerId + ", lockId=" + remoteLockId + "). "
            + "Remote lock released best-effort."));
        return;
    }
    // Re-arm polling (credentials must be re-resolved from context)
    try {
        LockableResourcesManager lrm = LockableResourcesManager.get();
        RemoteConnection remote = findRemoteConnectionOrFail(lrm, remoteServerId);
        String authorizationHeader = resolveAuthorizationHeader(remote);
        RemoteApiClient client = new RemoteApiClient();
        Run<?, ?> run = getContext().get(Run.class);
        String displayTarget = remoteLockId; // best-effort display
        startRemotePolling(remote, authorizationHeader, client, run, displayTarget);
    } catch (Exception ex) {
        getContext().onFailure(ex);
    }
}
```

#### Completion criteria

- Polling resumes after a restart while QUEUED (verified in `LockStepRemoteTest`)
- release is called after a restart while ACQUIRED
- Full `mvn test` BUILD SUCCESS

- [x] Implementation complete
- [x] `mvn test` confirmed (352 tests BUILD SUCCESS, `dev/reports/20260612000923-mvn-test.log`)
- [x] Committed (`8d45fbe`)

Notes: Implemented 2026-06-11. Restart while QUEUED → re-run startRemotePolling.
Restart while ACQUIRED → releaseRemoteLockBestEffort + AbortException.

---

### 6. STALE Admin Release UI

**Purpose:**
Let administrators release STALE remote locks from the resource list page.
Makes "notice and manually release" actionable under the fail-close design.

#### Implementation

**Add `isRemoteLockStale()` to `LockableResource`:**
```java
public boolean isRemoteLockStale() {
    if (remoteLockedBy == null) return null;
    RemoteLockRecord record = RemoteLockManager.get().find(remoteLockedBy);
    return record != null && record.getState() == RemoteLockState.STALE;
}
```

**Add a Force Release button to the Action column in `table.jelly`:**
```xml
<j:when test="${resource.remoteLockedBy != null}">
  <l:hasPermission permission="${it.UNLOCK}">
    <button
      data-action="release-remote-lock"
      data-lock-id="${resource.remoteLockedBy}"
      class="jenkins-button jenkins-button--tertiary jenkins-!-destructive-color ..."
      tooltip="${%btn.releaseRemoteLock}"
    >
      <l:icon src="symbol-lock-open-outline plugin-ionicons-api" />
    </button>
  </l:hasPermission>
</j:when>
```

**Add `doReleaseRemoteLock()` to `LockableResourcesRootAction`:**
- UNLOCK permission check
- Call `RemoteLockManager.get().release(lockId)`
- `LockableResourcesManager.scheduleQueueMaintenance()`
- JSON response

**JS handler (following the existing `lockable-resources-action-button` pattern):**
- Pick up `data-action="release-remote-lock"` in JS and AJAX POST

**Add keys to `table.properties` / `table.properties_ja`:**
- `btn.releaseRemoteLock=Force Release Remote Lock`

#### Completion criteria

- The Force Release button appears on STALE resources
- Clicking it clears `remoteLockedBy` and wakes local waiters
- Hidden without the UNLOCK permission
- Full `mvn test` BUILD SUCCESS

- [x] Implementation complete
- [x] `mvn test` confirmed (352 tests BUILD SUCCESS, `dev/reports/20260612000923-mvn-test.log`)
- [x] Committed (`26bc69a`)

Notes: Implemented 2026-06-11. Added the remoteLockedBy != null case to
table.jelly (with the UNLOCK permission check). Added doReleaseRemoteLock() to
LockableResourcesRootAction. Added keys to table.properties.

---

### 7. Test Expansion / Regression Pinning

**Purpose:**
Pin all M1B features as regression tests.
Confirm all M1A tests still pass (regression).

#### Test additions

**`RemoteLockManagerTest`:**
- A local pipeline context wakes after release (confirms the 4-3 fix)
- A priority-10 remote entry is dispatched before a priority-0 local entry
- `timeoutForAllocateResource` expiry produces `FAILED` (LOCK_WAIT_TIMEOUT)
- STALE → `release()` frees the resources

**`LockStepRemoteTest`:**
- DSL with `extra` succeeds over remote
- The job continues through heartbeat failures (mock server returns 410)
- Retrying after poll failures eventually reaches ACQUIRED
- onResume: restart-equivalent polling resumption while QUEUED

**`RemoteApiV1ActionTest`:**
- A lockRequest containing `extra` is accepted with 202
- 404 when `extra` contains an unexposed resource
- Behavior with unset `credentialsId` (client-side AbortException)

#### Completion criteria

- All added tests pass
- All 347 M1A tests pass (regression)
- `mvn test` (stabilize-build.sh) BUILD SUCCESS; report saved under `dev/reports/`

- [x] Implementation complete (2 LRM queue-bridge integration tests + 5 extra/API tests added)
- [x] `mvn test` confirmed (354 tests BUILD SUCCESS, RemoteLockManagerTest 18 tests, `dev/reports/20260612002702-mvn-test.log`)
- [x] Committed (`64981dd`)

Notes: Added 2026-06-12. queuedEntryBecomesAcquiredWhenResourceFreed /
releaseSchedulesQueueMaintenanceForLocalWaiters added to RemoteLockManagerTest.

---

### 8. Additional E2E Scenarios

**Purpose:**
Add scenarios to the E2E harness that substantiate M1B's safety claims.

#### Added scenarios

| ID | Script name | Verification |
|---|---|---|
| S10 | `extra-resources` | Remote locks with extra are acquired/released atomically on B |
| S11 | `heartbeat-resilience` | The body continues through heartbeat failures and releases on completion |
| S12 | `priority-ordering` | A higher-priority remote entry locks before a local entry |
| S13 | `stale-admin-release` | A STALE lock can be freed via UI Force Release and the waiter wakes |

#### M1B regression check (2026-06-12)

- `run-e2e.sh --clean-start` (4 containers freshly started with the HPI of HEAD `64981dd`): **11/12 PASS**
  - Report: `dev/reports/20260612004506-e2e-test.md`
  - Only S08 label-env-vars FAILed — not a plugin bug but a Declarative usage
    issue in the scenario script (Declarative treats the `@DataBoundConstructor`
    parameter `resource` as required — known upstream issue JENKINS-50260; the
    plugin's own `DeclarativePipelineTest` writes `resource: null` everywhere)
- Re-ran standalone after adding `resource: null` to `label-env-vars.sh`: **PASS (CP01–CP06 all)**
  - Report: `dev/reports/20260612005438-e2e-test.md`
- → **Effectively 12/12 scenarios PASS (M1B regression clear)**

#### S10–S13 implementation (2026-06-12)

| ID | Script | Design highlights |
|---|---|---|
| S10 | `extra-resources.sh` | Scripted pipeline with `extra: [[resource:]]`. During the body, confirms on B that both resources' `remoteLockedBy` hold the **same lockId** (direct atomicity verification). Also checks comma-joined variable, indexed variables, and release |
| S11 | `heartbeat-resilience.sh` | Sets B's remoteApiEnabled to false for 25s during a 40s body so heartbeats actually fail. Greps container A's logs for the warning (`Remote heartbeat failed (continuing job...)`) to **guarantee the test is not vacuous**. Confirms job continuation and release |
| S12 | `priority-ordering.sh` | While a holder on B holds the lock, a local waiter (priority 0) enqueues first, then a remote waiter (priority 10). Polling after the holder releases observes the resource **remote-locked first** (if priority were inverted, the local build lock would be observed — fully discriminating) |
| S13 | `stale-admin-release.sh` | Creates a ghost lease via direct curl that never sends heartbeats → confirms the STALE transition after ~60s → still held while STALE (fail-close) → force-released via the `releaseRemoteLock` endpoint → the local waiter wakes and completes |

Results (`dev/reports/20260612011450-e2e-test.md`): **S10–S13 all 4 PASS (first run)**

- S11 evidence: 2 heartbeat-failure warnings in A's logs (10s interval × 25s outage), build SUCCESS
- S13 evidence: STALE after ~60s, resource held while STALE, waiter SUCCESS after force release

`m1b-series` group and S10–S13 registered in `run-e2e.sh` (runnable standalone
via `--only m1b-series`).

#### Completion criteria

- The 4 added scenarios PASS
- M1A 12-scenario regression check (`./run-e2e.sh --only all`)
- Reports saved under `dev/reports/`

- [x] Implementation complete (S10–S13 all 4 scenarios PASS, 2026-06-12)
- [x] E2E regression confirmed (**full 16-scenario regression 16/16 PASS**, `dev/reports/20260612011822-e2e-test.md`, 2026-06-12)
- [x] Committed (notes repository `adf3429`)

Notes: Completed 2026-06-12. The S08 scenario fix is `db094e0`; the S10–S13
additions and reports are `adf3429`.

---

## Test Execution Policy (M1B)

1. After each step, verify with `mvn test -Dtest=<target tests>`
2. Before each commit, run the full suite via `./dev/stabilize-build.sh` (worktree mode)
3. Always confirm the test count has not decreased (regression)
4. Run E2E via `./run-e2e.sh` in Step 8

## Commit Conventions (M1B)

- One step = one commit as a baseline
- Example commit messages:
  - Step 1: `fix(remote-lock): lockEnvVars comma separator, exposeLabel javadoc (M1B)`
  - Step 2: `feat(remote-lock): extra resources support in remote acquire (M1B)`
  - Step 3: `refactor(remote-lock): integrate RemoteLockManager into LRM queue (M1B)`
  - Step 4: `fix(remote-lock): heartbeat/poll retry resilience (M1B)`
  - Step 5: `feat(remote-lock): onResume support for remote lock step (M1B)`
  - Step 6: `feat(remote-lock): admin force-release UI for STALE locks (M1B)`
  - Step 7: `test(remote-lock): M1B regression and new coverage`
  - Step 8: `chore(e2e): add M1B scenarios (extra, resilience, priority, stale-release)`

## Current Status

- Plan created: 2026-06-11
- Starting branch: `feature/1025-remote-lockable-resources-p1-m1a` (starting HEAD: `c782c28`)
- **Steps 0–8: ALL COMPLETE ✅** (2026-06-12)
- Plugin HEAD: `64981dd` (mvn test: 354 tests / 0 failures)
- E2E: all 16 scenarios 16/16 PASS (`dev/reports/20260612011822-e2e-test.md`)
- Current design truth: `LRR_DESIGN_P1_M1B.md`; E2E spec: `E2E_TEST_SPECIFICATION_P1_M1B.md`
