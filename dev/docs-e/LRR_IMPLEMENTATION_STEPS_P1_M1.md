# M1 Implementation Steps (Remote lock - Phase 1 / M1)

This file is a personal progress tracker.
It breaks the implementation into feature-scoped commits for later traceability.

## How to Use

- Check off each step when complete.
- Record "commit", "target files", and "verification result" for each step.
- One step = one commit as a baseline (multiple commits per step are fine if needed).

## M1 Goals

- Build the minimum viable implementation that handles remote lock via explicit `lock(..., serverId: 'X')`.
- Prioritize the smallest working peer mode first, structured for easy extension later.

## Step List

### 0. Preparation (branch / environment)

- [x] Working branch created from latest master
- [x] 3-controller local environment (8081/8082/8083) confirmed running
- [x] Baseline confirmed with all existing tests passing

Notes:
- Date: 2026-05-09
- Commit: 739d6da (※ after rebase, e4f70c3 is the base point. Final update planned after M1 completion.)
- Memo: Ran `$HOME/.local/apache-maven-3.9.9/bin/mvn test` and confirmed BUILD SUCCESS (Tests run: 238, Failures: 0, Errors: 0, Skipped: 1, Total time: 13:42).
  As of 2026-05-14, after cherry-picking PR #1028 (NodesMirror package fix) onto master and rebasing the feature branch, confirmed BUILD SUCCESS on a cold build (Tests run: 238, Failures: 0, Errors: 0, Skipped: 1).
  As of 2026-05-19, after implementing Step 6c, ran `$HOME/.local/apache-maven-3.9.9/bin/mvn test` again and confirmed BUILD SUCCESS (Tests run: 274, Failures: 0, Errors: 0, Skipped: 1, Total time: 13:37).
  - PR #1028 is not yet merged upstream, so it was cherry-picked onto local master (commit `e4f70c3`) as a workaround.
  - Skipped: 1 is `LockStepInversePrecedenceTest#lockInverseOrderWithLabel`. Skipped with `@Disabled` due to existing bug JENKINS-40787 / GitHub #861 (inversePrecedence not applied for label-based locks, causing hang). Unrelated to M1 implementation.

---

### 1. Add remote connection configuration model

Purpose:
- Add the foundation for holding `serverId -> (url, credentialsId)` configuration.

Implementation candidates:
- Add `remotes` configuration to `LockableResourcesManager`
- Add a dedicated model class if needed (e.g., `RemoteConnection`)
- Minimum implementation of save/load/validation

Completion criteria:
- Configuration is saved and readable after restart
- Minimum input validation for invalid values

- [x] Implementation complete
- [x] Unit verification complete

Notes:
- Date: 2026-05-09
- Commit: 5456a78
- Changed files:
  - src/main/java/.../RemoteConnection.java (new)
  - src/main/java/.../LockableResourcesManager.java (edited)
  - src/test/java/.../RemoteConnectionTest.java (new)
  - src/test/java/.../LockableResourcesManagerRemoteConnectionTest.java (new)
- Verification: Ran `$HOME/.local/apache-maven-3.9.9/bin/mvn test -Dtest=RemoteConnectionTest,LockableResourcesManagerRemoteConnectionTest` and succeeded (Tests run: 15, Failures: 0, Errors: 0, Skipped: 0).
- Notes: `LockableResourcesManager` holds remotes as a `List` and converts to `Map` dynamically via `getRemotesAsMap()`. `readResolve()` normalizes null to an empty list when loading old config. Added persistence test using reload.

---

### 2. Add remote API client skeleton

Purpose:
- Create a minimal, separated client layer for accessing the remote REST API.

Implementation policy:
- Client responsibility is limited to "HTTP call layer + DTO + error conversion". Connection to `LockStepExecution` is deferred to the next step.
- Authentication accepts an `Authorization` header, delegating credential resolution to the caller.
- Default values (internal constants):
  - pollIntervalSeconds = 3
  - heartbeatIntervalSeconds = 10
  - requestTimeoutSeconds = 5 (reduced from 10→5 in Step 5 to limit tick loop blocking time)
- Error policy: fail-closed (4xx/5xx/communication failures converted to `RemoteApiException`)
- URL policy: `/lockable-resources/remote/v1` is fixed; trailing slash difference in base URL is absorbed
- Logging policy: only output serverId/method/path/status; never output credentials

Completion criteria:
- A dummy call can be made (or verified with mocks)
- Return value / exception policy on failure is clear

- [x] Implementation complete
- [x] Unit verification complete

Notes:
- Date: 2026-05-10
- Commit: d40c5dc
- Changed files:
  - src/main/java/.../remote/RemoteClientDefaults.java (new)
  - src/main/java/.../remote/RemoteAcquireState.java (new)
  - src/main/java/.../remote/RemoteAcquireStatus.java (new)
  - src/main/java/.../remote/RemoteApiException.java (new)
  - src/main/java/.../remote/RemoteApiClient.java (new)
  - src/test/java/.../remote/RemoteAcquireStatusTest.java (new)
  - src/test/java/.../remote/RemoteApiClientTest.java (new)
- Verification: Ran `$HOME/.local/apache-maven-3.9.9/bin/mvn test -Dtest=RemoteApiClientTest,RemoteAcquireStatusTest` on the Step 2 commit and succeeded (Tests run: 6, Failures: 0, Errors: 0, Skipped: 0).
- Notes: Reflected review feedback: lockId missing propagates httpStatus, JSON parse failure logging, baseUrl defensive check, null state → UNKNOWN fallback. Aligned with decision to exclude cancel concept from Phase 1; Step 2 history also organized to not include cancel API implementation.

---

### 3. Implement acquire/release remote call flow

Purpose:
- Implement the minimum lifecycle: acquire → poll → acquired/rejected → release.

Implementation policy:
1. Client side does not enqueue into a local queue (remote acquire is tracked via async polling)
2. `start()` returns immediately after registering remote acquire (non-blocking)
3. Poll `GET /acquire/{lockId}` every 3 seconds
4. State transitions:
  - `QUEUED` → continue
  - `ACQUIRED` → start body execution
  - `SKIPPED` → complete successfully (body not executed)
  - `FAILED` / `EXPIRED` → fail
  - `CANCELLED` → treat as abort
5. Heartbeat is only sent during body execution; release on body completion
6. Also attempt release on abort (cancel concept excluded from Phase 1)
7. Fail-closed (no automatic release on communication failure)
8. Logging centers on `serverId / lockId / state`; credentials are never logged
9. `RemoteApiClient` API scope: acquire/status + heartbeat/release (internal identifier unified as lockId)
10. Restart resilience: field design for easy future extension; full recovery deferred to next step

Completion criteria:
- Remote lock acquire/release works end-to-end
- Failure logging and termination behavior is defined

- [x] Implementation complete
- [x] Unit verification complete

Notes:
- Date: 2026-05-10
- Commit: fb25b42
- Changed files:
  - src/main/java/.../remote/RemoteApiClient.java (edited: heartbeat/release + optional Authorization header)
  - src/main/java/.../LockStepExecution.java (edited: remote enqueue/poll/heartbeat/release flow)
  - src/main/java/.../LockStep.java (edited: added serverId DataBoundSetter)
- Verification: Ran `$HOME/.local/apache-maven-3.9.9/bin/mvn test -Dtest=LockStepTest,RemoteApiClientTest,RemoteAcquireStatusTest` and succeeded (Tests run: 37, Failures: 0, Errors: 0, Skipped: 0).
- Notes: Aligned with decision to exclude cancel concept from Phase 1; abort and completion both use release-based cleanup. credentialsId is treated as unimplemented in Phase 1 (not converted directly to Authorization header).

---

### 4. Add `serverId` to LockStep

Purpose:
- Accept `serverId` from the DSL and make it usable for local/remote branching.

Implementation candidates:
- Add `serverId` field to `LockStep`
- Descriptor validation/completion if needed
- Branch to remote path in `LockStepExecution`

Completion criteria:
- `lock(resource: 'X', serverId: 'A')` is interpreted correctly
- Existing behavior without `serverId` is not broken

- [x] Implementation complete
- [x] Unit verification complete

Notes:
- Date: 2026-05-10
- Commit: fb25b42
- Changed files:
  - src/main/java/.../LockStep.java (edited: added serverId DataBoundSetter)
  - src/main/java/.../LockStepExecution.java (edited: remote flow wired via serverId branch)
- Verification: Ran `$HOME/.local/apache-maven-3.9.9/bin/mvn test -Dtest=LockStepTest` and succeeded (Tests run: 31, Failures: 0, Errors: 0, Skipped: 0).
- Notes: Implementation was included in the same commit as Step 3 and is tracked under the same commit.

---

### 5. Server-side REST endpoints (required for M1)

Purpose:
- Implement the server-side endpoints required for M1.

#### Finalized design decisions

**1. Representation of remote locks (LockableResource side)**
- Add `transient String remoteLockedBy` (lockId or null) field to `LockableResource`.
- LRM considers a resource with `remoteLockedBy != null` as "in use". It has no knowledge of the `RemoteLockRecord` internals.

**2. Stapler routing**
- `LockableResourcesRootAction.getDynamic("remote")` → `getDynamic("v1")` → `RemoteApiV1Action`
- Each endpoint is implemented in `RemoteApiV1Action`.

**3. Storage location for RemoteLockRecord**
- Create a new `RemoteLockManager` (`@Extension`) that manages records in-memory using `ConcurrentHashMap<String, RemoteLockRecord>`.
- Not persisted (all records are lost on Jenkins restart).
- Operations: Admin confirms exposed resources are healthy before setting `remoteApiEnabled = true`.

**4. Master switch / expose configuration**
- Add `remoteApiEnabled` (boolean, default false) and `exposeLabel` (String) to `LockableResourcesManager`.
- All endpoints return 403 when `remoteApiEnabled = false`.

**5. Authentication / authorization**
- Jenkins standard auth (API token) + `Jenkins.READ` check only.
- Dedicated Permission deferred to M2+; not introduced in M1.

**6. Stale detection and release policy**
- `RemoteLockManager` scheduler thread periodically scans and marks records exceeding STALE_THRESHOLD as STALE.
- Stale locks are not released automatically (safe direction). Admin manually unstales via UI.
- Discovery / GET endpoints are read-only (no write coordination needed).
- Concurrency: `ConcurrentHashMap` + `volatile` fields.

**Concurrency design**
- `RemoteLockManager` has a `ScheduledThreadPool(1)` (single thread) with a 1-second tick loop.
- Tasks are executed inside the tick based on elapsed time:
  - (client) 3s since last poll → GET /acquire/{lockId} (per active lock)
  - (client) body executing and 10s since last heartbeat → POST /heartbeat (per active lock)
  - (client) Discovery: N seconds since last run → GET /resources
  - (server) STALE_THRESHOLD / 2 seconds since last stale scan → walk all RemoteLockRecords
- Each task holds a `lastRunAt` timestamp for execution decision within the tick.
- Only this single thread is a writer → Discovery / GET endpoints are read-only, no coordination needed.
- Tick loop is single-threaded, so HTTP call blocking time directly delays the entire tick.
  To account for this, `RemoteClientDefaults.DEFAULT_REQUEST_TIMEOUT_SECONDS` changes from 10 → 5 (included in Step 5 commit).

#### Endpoints to implement

| Method | Path | Summary |
|---|---|---|
| POST | `/lockable-resources/remote/v1/acquire` | Enqueue acquire, returns `{lockId}` |
| GET  | `/lockable-resources/remote/v1/acquire/{lockId}` | State query (QUEUED/ACQUIRED/SKIPPED/FAILED/EXPIRED) |
| POST | `/lockable-resources/remote/v1/lease/{lockId}/heartbeat` | Update heartbeat, returns 204 |
| POST | `/lockable-resources/remote/v1/lease/{lockId}/release` | Release lock, returns 204 |

#### Implementation order

1. Create `RemoteLockRecord` class (new)
2. Create `RemoteLockManager` class (new) (scheduler + record CRUD)
3. Add `remoteLockedBy` field to `LockableResource`
4. Add `remoteApiEnabled` + `exposeLabel` to `LockableResourcesManager`
5. Create `RemoteApiV1Action` (new) (endpoint implementation)
6. Add `getDynamic` to `LockableResourcesRootAction`

Completion criteria:
- Callable from the local `RemoteApiClient` (verified in 3-controller environment)
- All endpoints return 403 when `remoteApiEnabled = false`
- STALE marking behavior is verifiable

- [x] Implementation complete
- [x] Unit verification complete

Notes:
- Date: 2026-05-14 (amended with code review fixes on 2026-05-16)
- Commit: 8a8d816
- Changed files:
  - src/main/java/.../remote/RemoteLockState.java (new)
  - src/main/java/.../remote/RemoteLockRecord.java (new)
  - src/main/java/.../remote/RemoteLockManager.java (new)
  - src/main/java/.../remote/RemoteClientDefaults.java (edited: DEFAULT_REQUEST_TIMEOUT_SECONDS 10→5)
  - src/main/java/.../actions/RemoteApiV1Action.java (new + review fix amendment)
  - src/main/java/.../LockableResource.java (edited: added remoteLockedBy field, updated isLocked())
  - src/main/java/.../LockableResourcesManager.java (edited: added remoteApiEnabled + exposeLabel)
  - src/main/java/.../actions/LockableResourcesRootAction.java (edited: added getDynamic routing)
  - src/test/resources/.../casc_expected_output.yml (edited: added remoteApiEnabled: false)
- Verification: `mvn test` resulted in BUILD SUCCESS (Tests run: 261, Failures: 0, Errors: 0, Skipped: 1). Same result confirmed after review fixes (2026-05-16).
- Notes:
  - Extension index (`META-INF/annotations/hudson.Extension.txt`) not being generated causes all tests to fail with `@Extension` classes not found at Jenkins startup. Fixed by deleting `target/classes` to force recompile.
  - `mvn compile && mvn test` triggers this issue — use `mvn test` only.
  - No automatic stale release (safe direction). STALE_THRESHOLD_MS=60000ms, TERMINAL_TTL_MS=120000ms.
  - No persistence (all records lost on Jenkins restart).
  - 2026-05-16 code review fixes applied as amendment:
    - Fixed bug where all resources were exposed when `exposeLabel` was not set (fixed to match opt-in design: no label = deny all)
    - Added server-side validation for `heartbeatIntervalSeconds` (≤0 or non-integer → 400 INVALID_HEARTBEAT_INTERVAL)
    - Changed POST /acquire response from 200 → 202 Accepted
    - Unified error code from RESOURCE_NOT_FOUND → UNKNOWN_RESOURCE (aligned with LRR-DESIGN)
  - Status when remoteApiEnabled=false is 403 (LRR-DESIGN-j.md also corrected on the same day)

---

### 6. Minimum UI/visualization (required for M1 only)

Scope confirmed (2026-05-16):
- **6a**: Add `clientId` to `POST /acquire` (client send + server receive/store + configuration UI)
- **6b**: B-side LR page display (show `clientId` in server-side LR list)
- **6c**: Extend System configuration UI (server side: exposeLabel / remoteApiEnabled, client side: remotes connection parameters)
- **6d**: Authentication implementation (resolve username/password from `credentialsId` and attach Authorization header)

---

#### Step 6a: Add `clientId`

Purpose:
- Include the caller Jenkins identifier `clientId` in `POST /acquire` so the server can track lock holders.
- Add an admin-configurable field to LRM that falls back to `Jenkins.getRootUrl()` when not set.

Implementation content:
- `RemoteLockRecord`: add `clientId` field (nullable)
- `RemoteLockManager.enqueue()`: add `clientId` to signature
- `RemoteApiV1Action` (`POST /acquire`): parse, normalize, and store optional `clientId` field
- `RemoteApiClient.enqueueAcquire()`: add `clientId` argument; include in request body only when non-null
- `LockableResourcesManager`: add `clientId` config field (`setClientId` / `getClientId` / `getEffectiveClientId`); add null normalization in `readResolve()`
- `LockStepExecution`: change to use `LockableResourcesManager.get().getEffectiveClientId()`
- `LockableResourcesManager/config.jelly`: add "Remote Lockable Resources (Client)" section with `clientId` textbox
- `LockableResourcesManager/config.properties`: add UI label keys
- `RemoteApiClientTest`: add `null` argument to `enqueueAcquire()` call sites
- `LRR-DESIGN-j.md`: update POST /acquire spec, flow diagram, and Section 6 configuration table

Completion criteria:
- `mvn test` passes
- `clientId` can be entered and saved in the configuration UI

- [x] Implementation complete
- [x] `mvn test` verification complete
- [x] Committed

Notes:
- Date: 2026-05-16
- Commit: f89330a
- Changed files:
  - src/main/java/.../remote/RemoteLockRecord.java (edited)
  - src/main/java/.../remote/RemoteLockManager.java (edited)
  - src/main/java/.../actions/RemoteApiV1Action.java (edited)
  - src/main/java/.../remote/RemoteApiClient.java (edited)
  - src/main/java/.../LockableResourcesManager.java (edited: added clientId field)
  - src/main/java/.../LockStepExecution.java (edited: switched to getEffectiveClientId() + removed Jenkins import)
  - src/main/resources/.../LockableResourcesManager/config.jelly (edited)
  - src/main/resources/.../LockableResourcesManager/config.properties (edited)
  - src/test/java/.../remote/RemoteApiClientTest.java (edited)
  - lrr-notes/dev/docs/LRR-DESIGN-j.md (edited)
- Verification: `mvn test` resulted in BUILD SUCCESS (Tests run: 261, Failures: 0, Errors: 0, Skipped: 1, Total time: 13:05). 2026-05-16
- Notes: `getEffectiveClientId()` returns `Jenkins.getRootUrl()` when `clientId` config is empty (`@CheckForNull`). UI adds "Remote Lockable Resources (Client)" section in config.jelly.

---

#### Step 6b: B-side LR page display

Purpose:
- Display the remote lock holder's `clientId` on the server-side Lockable Resources UI.
- Allow admins to see at a glance which remote Jenkins holds which resource.

Design decisions (finalized):
- Display string: `Remote: <clientId>` (falls back to `Remote: (unknown)` when clientId is null)
- Data retrieval: Add `getRemoteLockClientId()` to `LockableResource`, internally calls `RemoteLockManager.get().find(remoteLockedBy)` to get `clientId`
- Falls back to normal "Locked by" display when `remoteLockedBy` is null (no remote lock)

Implementation content:
- `LockableResource`: add `getRemoteLockClientId()` method
- `LockableResource` display jelly (`index.jelly` or `index.groovy`): render `Remote: clientId` when `remoteLockedBy != null`
- `LRR-DESIGN-j.md`: B-side display design already added to Section 6 in Step 6a

Completion criteria:
- Remote lock holder appears as "Remote: clientId" in the LR list
- "Remote: (unknown)" is displayed when `clientId` is null

- [x] Implementation complete
- [x] `mvn test` verification complete
- [x] Committed

Notes:
- Date: 2026-05-17
- Commit: c2e9112
- Changed files:
  - src/main/java/.../LockableResource.java (edited: added getRemoteLockClientId())
  - src/main/resources/.../LockableResourcesRootAction/tableResources/table.jelly (edited: added remote lock case)
  - src/main/resources/.../LockableResourcesRootAction/tableResources/table.properties (edited: added resource.status.remoteLockedBy key)
- Verification: `mvn test` resulted in BUILD SUCCESS (Tests run: 261, Failures: 0, Errors: 0, Skipped: 1, Total time: 12:52). 2026-05-17
- Notes:
  - `getRemoteLockClientId()`: returns null immediately if `remoteLockedBy == null`; otherwise searches for the record via `RemoteLockManager.get().find(remoteLockedBy)` and returns `clientId`. Returns null if record not found (e.g., after restart).
  - `table.jelly`: the remote lock case is placed before the job-locked case in the `j:choose` for status content. Branches on `resource.remoteLockedBy != null` and falls back to `(unknown)` when `remoteLockClientId` is null.
  - The CSS class `j:choose` is unchanged (`resource.locked == true` already maps to `warning`).

---

#### Step 6c: System configuration UI extension (server/client settings)

Purpose:
- Allow core remote lock server/client settings to be completed via System configuration UI.
- Expose `remoteApiEnabled` / `exposeLabel` / `remotes[]` in UI to reduce reliance on manual Groovy setup.

In-scope settings for this step:
- Server-side (`LockableResourcesManager`)
  - `remoteApiEnabled` (master switch)
  - `exposeLabel` (label used for exposure)
- Client-side (`LockableResourcesManager`)
  - `remotes[]`
    - `serverId`
    - `url`
    - `credentialsId`

Implementation policy:
- Reorganize/add Remote sections in `LockableResourcesManager/config.jelly`
  - Server section: checkbox (`remoteApiEnabled`) + textbox (`exposeLabel`)
  - Client section: keep existing `clientId`, add repeatable `remotes`
- Add UI label keys to `LockableResourcesManager/config.properties`
- Add help files as needed
  - `help/remoteApiEnabled`
  - `help/exposeLabel`
  - `help/remotes`
  - `help/remotes/serverId`, `help/remotes/url`, `help/remotes/credentialsId`
- Validation policy
  - Respect existing `RemoteConnection.validate()` checks
  - Keep current duplicate `serverId` behavior: warning + last-entry-wins (strict mode is a separate future task)
  - Preserve opt-in behavior when `exposeLabel` is unset (expose none)

Completion criteria:
- System configuration UI can edit/save `remoteApiEnabled` / `exposeLabel`
- System configuration UI can add/save `remotes[]` (`serverId`/`url`/`credentialsId`)
- Settings persist after Jenkins restart
- `mvn test` passes (at least no regressions in existing tests related to UI/config)

- [x] Implementation complete
- [x] `mvn test` verification complete
- [x] Committed

Notes:
- Date: 2026-05-19
- Commit: 71de798
- Changed files:
  - src/main/resources/.../LockableResourcesManager/config.jelly (edited)
  - src/main/resources/.../LockableResourcesManager/config.properties (edited)
  - src/main/resources/.../LockableResourcesManager/help-remoteApiEnabled.html (new)
  - src/main/resources/.../LockableResourcesManager/help-exposeLabel.html (new)
  - src/main/resources/.../LockableResourcesManager/help-remotes.html (new)
  - src/main/resources/.../RemoteConnection/config.jelly (new)
  - src/main/resources/.../RemoteConnection/config.properties (new)
  - src/main/resources/.../RemoteConnection/help-serverId.html (new)
  - src/main/resources/.../RemoteConnection/help-url.html (new)
  - src/main/resources/.../RemoteConnection/help-credentialsId.html (new)
  - src/test/java/.../LockableResourcesManagerRemoteConnectionTest.java (edited: added Global Configure round-trip test)
- Verification: The added `LockableResourcesManagerRemoteConnectionTest` passed when run alone (Tests run: 10, Failures: 0, Errors: 0, Skipped: 0). After that, full `mvn test` also passed with BUILD SUCCESS (Tests run: 274, Failures: 0, Errors: 0, Skipped: 1, Total time: 13:37). 2026-05-19
- Notes:
  - Reorganized the System configuration UI into server/client areas: server side now exposes `remoteApiEnabled` / `exposeLabel`, and client side keeps `clientId` plus the `remotes[]` editor.
  - Added a dedicated `RemoteConnection` config fragment and help files so `serverId` / `url` / `credentialsId` can be edited from UI.
  - Added one Global Configure round-trip test to guard the UI submit path; combined with the existing persistence test, save/reload coverage is now in place.

---

#### Step 6d: Authentication implementation (credentialsId resolution + Authorization header)

Purpose:
- Resolve `remotes[].credentialsId` at runtime and send authenticated requests to remote APIs.
- Remove the current "credentialsId stored but unused" gap and complete the peer-mode authentication path for M1.

In-scope settings for this step:
- Client-side (`LockStepExecution` / remote API call path)
  - credentials resolution
  - Authorization header generation (Basic)
- Error handling
  - fail-closed behavior for missing credentials, unresolved IDs, wrong type, and auth failures

Implementation policy:
- Implement `LockStepExecution.resolveAuthorizationHeader()`
  - Resolve `StandardUsernamePasswordCredentials` from Jenkins-global credentials by `credentialsId`
  - Build `Authorization: Basic ...` from Base64(username:password)
- Limit Step 6d authentication support to Basic only
  - Treat username/password and username/API token uniformly as Basic Authorization
  - Keep secret text and bearer token support out of scope for this step
- When `credentialsId` is empty
  - Keep current no-auth call behavior (may fail with 403 depending on server configuration)
- When `credentialsId` is set but cannot be resolved
  - Fail early with explicit `AbortException` (surface misconfiguration clearly)
- When `credentialsId` is set but resolves to the wrong type
  - Fail early with explicit `AbortException` (`StandardUsernamePasswordCredentials` only)
- Logging policy
  - Never log credential values
  - Log only identifiers/categories (`serverId`, `credentialsId`, failure category)
  - Keep 401/403 handling as existing remote API failure behavior: fail-closed build failure

Completion criteria:
- Remote API is called with Authorization header when `credentialsId` is set
- Authentication failure (e.g. 403) fails build in fail-closed manner
- Credential resolution failure stops with intended error
- `mvn test` passes (with related tests added/updated)

- [x] Implementation complete
- [x] `mvn test` verification complete
- [x] Committed

Notes:
- Date: 2026-05-19
- Commit: plugin `28e1fc9`, docs-j `6b8ebda`
- Changed files:
  - src/main/java/.../LockStepExecution.java (edited: credentials resolution + Authorization generation)
  - src/main/java/.../remote/RemoteApiClient.java (edited if needed)
  - src/test/java/.../LockStepRemoteTest.java (add auth success/failure cases)
  - src/test/java/.../remote/RemoteApiClientTest.java (add Authorization header transmission checks)
- Verification:
  - Targeted runs for `LockStepRemoteTest` / `RemoteApiV1ActionTest` / `RemoteApiClientTest` passed (Failures: 0, Errors: 0).
  - Full `mvn test` log `dev/reports/20260519170441-mvn-test.log` shows BUILD SUCCESS (Tests run: 276, Failures: 0, Errors: 0, Skipped: 1).
- Notes:
  - Debug-time `missing descriptor` / `cannot find symbol` symptoms were isolated as parallel execution or transient build-state issues, not a Step 6d implementation defect.

---

#### Step 6e: errorCode unification fix (`UNKNOWN_RESOURCE`)

Purpose:
- Unify the missing-resource errorCode between remote API entry checks and internal state transitions, so operational diagnosis and log interpretation remain consistent.

Implementation:
- Replaced `RESOURCE_NOT_FOUND` with `UNKNOWN_RESOURCE` in `RemoteLockManager` for missing-resource failures
- Added a regression test (`RemoteLockManagerTest`) to lock down `FAILED + UNKNOWN_RESOURCE` when enqueueing a non-existent resource

Completion criteria:
- Plugin-side fix is committed
- Focused tests are green

- [x] Implementation complete
- [x] Focused test verification complete
- [x] Committed

Notes:
- Date: 2026-05-23
- Commit: plugin `3a111a0`
- Changed files:
  - src/main/java/.../remote/RemoteLockManager.java (edited)
  - src/test/java/.../remote/RemoteLockManagerTest.java (new)
- Verification:
  - `$HOME/.local/apache-maven-3.9.9/bin/mvn test -Dtest=RemoteLockManagerTest,RemoteApiV1ActionTest` succeeded (Tests run: 2, Failures: 0, Errors: 0, Skipped: 0).

---

### 7. Formal tests (plugin-side / M1 completeness verification)

Policy:
- Only what belongs in the plugin is handled in this step
- Targets are regression-prevention tests placed in `lockable-resources-plugin/src/test/...` and `src/test/resources/...`
- Completion criterion is the ability to re-run with `mvn test` or `mvn test -Dtest=...`

Purpose:
- Lock down the M1 core with automated tests to prevent regressions.

Priority tests:
- Branching with `serverId`
- Preservation of existing behavior without `serverId`
- Representative cases of remote acquire success/failure
- `RemoteApiV1Action` HTTP-level tests (directly locking down server-side endpoint contracts):
  - All endpoints return 403 when `remoteApiEnabled=false`
  - POST /acquire returns 404 UNKNOWN_RESOURCE when `exposeLabel` is not set
  - POST /acquire returns 404 UNKNOWN_RESOURCE for a resource without the configured `exposeLabel`
  - Invalid `heartbeatIntervalSeconds` values (0, negative, non-integer) return 400 INVALID_HEARTBEAT_INTERVAL
  - Valid acquire request returns 202 with lockId

Target repository:
- `lockable-resources-plugin`

Expected placement:
- `src/test/java/.../RemoteApiV1ActionTest.java` or a nearby HTTP-level test
- Remote branch cases added to `src/test/java/.../LockStep...Test.java`
- `src/test/resources/...` fixture additions as needed

Completion criteria:
- Added tests pass stably
- Key cases are reproducible
- State is ready to be added to CI with the plugin alone

- [x] Implementation complete
- [x] Verified with CI-equivalent local run

Notes:
- Date: 2026-05-17
- Commits: 0ea83df, ecb11f4, cf47eb2
- Changed files:
  - src/test/java/.../actions/RemoteApiV1ActionTest.java (new)
  - src/test/java/.../LockStepRemoteTest.java (new)
  - src/test/java/.../actions/LockableResourcesRootActionTest.java (edited: added Remote: clientId normal display test)
- Verification:
  - `$HOME/.local/apache-maven-3.9.9/bin/mvn test -Dtest=RemoteApiV1ActionTest` succeeded (Tests run: 1, Failures: 0, Errors: 0, Skipped: 0).
  - `$HOME/.local/apache-maven-3.9.9/bin/mvn test -Dtest=LockStepRemoteTest` succeeded (Tests run: 6, Failures: 0, Errors: 0, Skipped: 0).
  - `$HOME/.local/apache-maven-3.9.9/bin/mvn test -Dtest=LockableResourcesRootActionTest` succeeded (Tests run: 19, Failures: 0, Errors: 0, Skipped: 0).
  - `$HOME/.local/apache-maven-3.9.9/bin/mvn test` (full plugin) succeeded (Tests run: 268, Failures: 0, Errors: 0, Skipped: 1).
- Notes:
  - Step 7 started. First added regression tests to lock down representative contracts of `RemoteApiV1Action`.
  - Contracts locked down so far: 403 when `remoteApiEnabled=false`, 404 `UNKNOWN_RESOURCE` via `exposeLabel` constraint, 400 `INVALID_HEARTBEAT_INTERVAL` for invalid values, 202 + `lockId` for a valid acquire.
  - `LockStepRemoteTest` locks down that `serverId` routes to the remote branch, and that the existing local lock flow is preserved when `serverId` is absent even if remote configuration exists.
  - Failure cases added: `serverId` with no matching remote config, remote acquire status returning `FAILED`, returning `EXPIRED`, and communication failure on `POST /acquire` — all result in build failure without executing body.
  - UI: `LockableResourcesRootActionTest` locks down both `Remote: (unknown)` and the normal `Remote: clientId` display branch.
  - Originally built with JenkinsRule + HTTP, but Jetty port binding was unstable in the local environment. Switched to direct action invocation + mocked Stapler for stability.
  - Minimum regression tests for the `serverId` branch, preservation of existing local behavior, and representative failure cases are added. Remaining for Step 7 as a whole: optional extension cases such as heartbeat interruption or communication failure during status polling.
  - 2026-05-23 addendum: After Step 6e errorCode unification, focused run `RemoteLockManagerTest,RemoteApiV1ActionTest` succeeded (Tests run: 2, Failures: 0, Errors: 0, Skipped: 0).
  - 2026-05-23 addendum: Re-ran `./stabilize-build.sh`; full `mvn test` succeeded (Tests run: 278, Failures: 0, Errors: 0, Skipped: 1, BUILD SUCCESS, Total time: 14:45). Log: `dev/reports/20260523075036-mvn-test.log`.

---

### 8. Automated E2E (3 controllers / personal environment)

Policy:
- 3-controller verification is needed to confirm M1 completeness, but is environment-specific and does not belong in the plugin itself
- Place re-runnable E2E assets in `lockable-resources-remote-notes` for the running 8081/8082/8083 environment
- Prefer Java / shell / curl / Jenkins CLI and other tools available in the existing environment; do not use Playwright

Purpose:
- Automate reproduction of minimum peer mode completeness in a 3-controller configuration
- Make the same verification re-runnable with a single command after implementation

Target repository:
- `lockable-resources-remote-notes`

Implementation candidates:
- Add execution scripts and README under `dev/jenkins-env/`
- Automate job submission, wait, result verification, and cleanup for each controller
- Optionally add raw curl-based remote API call verification as supplemental

Pre-decided policy (2026-05-18):
- Authentication: Initially used "allow anonymous READ temporarily" for speed.
- 2026-05-23 update: migrated to authenticated mode + API token credentials (aligned with Step 6d and avoids CSRF 403 on POST).
- Execution responsibility: `run-e2e.sh` includes `start.sh` to launch controllers (`--skip-start` option available for already-running environments).
- Pass/fail determination: Combined build result + wait time threshold + log keywords to reduce false positives.

Completion criteria:
- 3-controller E2E can be run end-to-end automatically
- Pass/fail criteria are scripted for both success and failure cases
- Local environment prerequisites are documented in `lockable-resources-remote-notes`

- [x] Implementation complete
- [x] Verified with local automated run

Notes:
- Date: 2026-05-18 (last updated: 2026-05-23)
- Commit: reflected in this commit
- Changed files:
  - `dev/jenkins-env/run-e2e.sh`
  - `dev/jenkins-env/lib/common.sh`
  - `dev/jenkins-env/scenarios/peer-basic.sh`
  - `dev/jenkins-env/scenarios/fail-closed.sh`
  - `dev/jenkins-env/start.sh`
  - `dev/jenkins-env/stop.sh`
  - `dev/jenkins-env/docker-compose.yml`
  - `dev/jenkins-env/docker/init.groovy.d/00-init.groovy`
  - `dev/jenkins-env/README.md`
- Verification:
  - `./run-e2e.sh --skip-start --only peer-basic` PASS (`dev/reports/20260518112121-e2e-test.md`)
  - `./run-e2e.sh --skip-start --only fail-closed` PASS (`dev/reports/20260518112207-e2e-test.md`)
  - `PLUGIN_DIR=... ./run-e2e.sh --clean-start --only peer-basic` PASS (`dev/reports/20260523100012-e2e-test.md`)
  - `PLUGIN_DIR=... ./run-e2e.sh --clean-start` PASS (`dev/reports/20260523100138-e2e-test.md`, pass=2 fail=0)
- Notes:
  - 2026-05-18: Step 8 started. Added `run-e2e.sh` (harness), `lib/common.sh` (common functions), `scenarios/*.sh` (initial stubs for normal/error cases) under `dev/jenkins-env/`. Stub scenario bodies return `SKIP`.
  - 2026-05-18: Implemented scenario bodies. `peer-basic` verifies 8081 holder / 8083 waiter wait behavior (SUCCESS + wait time threshold + log check). `fail-closed` runs 3 cases (remote down / timeout / auth error) automatically and verifies body is not executed.
  - 2026-05-18: Unified test result output location to `dev/reports/`. Each `run-e2e.sh` run generates `yyyymmddhhmmss-e2e-test.md` (summary) and `yyyymmddhhmmss-e2e-test/` (console log / case summary / manual capture location).
  - 2026-05-18: Fixed `/acquire` routing in `RemoteApiV1Action` (resolved conflict between `POST /acquire` and `GET /acquire/{lockId}`).
  - 2026-05-18: Fixed lockId parsing broken by Stapler 302 normalization (trailing `/`) by changing acquire-related paths in `RemoteApiClient` to canonical paths.
  - 2026-05-18: Changed scenarios to use a unique resource name per run to suppress stale state interference.
  - 2026-05-18: Added Scenario Details (Sequence + Checkpoints) to reports. Each checkpoint outputs API/Action, Expected, Actual, and Result.
  - 2026-05-18: Fixed markdown table corruption in Scenario Details (separated Sequence and Checkpoints generation, then combined at end).
  - 2026-05-18: Translated report body to English (Summary / Scenario details / checkpoint descriptions).
  - 2026-05-18: Plugin-side fix committed (`ade9bb7`): `RemoteApiV1Action` acquire routing fix, `RemoteApiClient` acquire path canonicalization, corresponding test updates.
  - 2026-05-23: Renamed compose service/container names from `jenkins-8081/2/3` to `jenkins-a/b/c` and updated references in `common.sh`, `start.sh`, `fail-closed.sh`, and `README.md`.
  - 2026-05-23: Root-caused peer-basic 403 by checking Controller B logs: `No valid crumb was included ... /remote/v1/acquire/ ... Returning 403`.
  - 2026-05-23: Updated E2E harness to API-token-backed Basic auth. Scenario now issues a Controller-B `admin` API token and stores it as the password field in Controller A/C username-password credentials.
  - 2026-05-23: Added/updated `dev/docs-j/E2E_TEST_SPECIFICATION.md` to reflect authenticated mode (API token), 5 fail-closed cases, and `jenkins-a/b/c` naming.

E2E verification checklist (3 controllers):
- [x] Remote lock from 8081 → 8082 is acquired
- [x] Same resource from 8083 results in expected wait/reject behavior
- [x] Waiting side proceeds after release
- [x] Abnormal cases (remote down, timeout, auth error) result in fail-closed behavior

Final Step 8 status (2026-05-23):
- Authenticated mode with API-token-backed Basic credentials is stable in E2E.
- Expanded to 10 scenarios (S01-S07, D01-D03), replacing `peer-basic` with the S-series topology set.
- Full run result: pass=10 fail=0 skip=0 (`dev/reports/20260523133947-e2e-test.md`).

#### 2026-05-23 update (M1: S/D-series E2E expansion)

- Replaced `peer-basic` with the full 10-scenario topology set defined in `E2E_TEST_SPECIFICATION.md`.
  - S-series: `mutual-peer`, `fan-in-contention`, `server-self-use`, `mixed-local-remote`, `skip-if-locked`, `three-way-mesh`, `fail-closed`
  - D-series: `fan-in-4`, `chain-4`, `diamond`
- Extended `run-e2e.sh --only` to accept individual scenario names plus `s-series`, `d-series`, and `all`.
- Generalized `lib/common.sh` to support arbitrary remote `serverId` entries and 4-controller readiness checks.
- Added `jenkins-d` (8084) to `docker-compose.yml` and updated `start.sh` / `stop.sh` for a 4-controller environment.
- Added report improvements: scenario IDs (`Sxx` / `Dxx`), command-line recording, artifact links, and scenario-details headings with IDs.

Changed files for the expansion:
- `dev/jenkins-env/run-e2e.sh`
- `dev/jenkins-env/lib/common.sh`
- `dev/jenkins-env/docker-compose.yml`
- `dev/jenkins-env/README.md`
- `dev/jenkins-env/start.sh`
- `dev/jenkins-env/stop.sh`
- `dev/jenkins-env/scenarios/fail-closed.sh`
- `dev/jenkins-env/scenarios/mutual-peer.sh`
- `dev/jenkins-env/scenarios/fan-in-contention.sh`
- `dev/jenkins-env/scenarios/server-self-use.sh`
- `dev/jenkins-env/scenarios/mixed-local-remote.sh`
- `dev/jenkins-env/scenarios/skip-if-locked.sh`
- `dev/jenkins-env/scenarios/three-way-mesh.sh`
- `dev/jenkins-env/scenarios/fan-in-4.sh`
- `dev/jenkins-env/scenarios/chain-4.sh`
- `dev/jenkins-env/scenarios/diamond.sh`
- `dev/jenkins-env/scenarios/peer-basic.sh` (deleted)

Verification status for the expansion:
- [x] shell syntax checks (`bash -n`)
- [x] `run-e2e.sh --help`
- [x] `--only s-series`
- [x] `--only d-series`
- [x] `--only all`

Debug notes from the expansion:
- Initial S04 `mixed-local-remote` failure was caused by harness-side unlock verification that assumed the local resource always remained addressable. Fixed by checking `EXISTS` and `LOCKED` separately.
- Re-running S04 exposed a second harness issue: credentials replacement used `removeAll` against a `CopyOnWriteArrayList`. Fixed by switching to `SystemCredentialsProvider#getStore()` with `Domain.global()` add/remove APIs.
- Initial D-series execution skipped because `jenkins-d` entered a restart loop. Root cause was `jhd/` ownership (`root:root`). Fixed by extending `start.sh`/`stop.sh` for 4 controllers and forcing Docker-based `chown -R 1000:1000` on Jenkins home directories.

Verification results:
- `PLUGIN_DIR=../../../lockable-resources-plugin ./run-e2e.sh --clean-start --only s-series`
  - first run: pass=6 fail=1 skip=0 (S04 failure)
- `./run-e2e.sh --skip-start --only s-series`
  - after fixes: pass=7 fail=0 skip=0
- `./run-e2e.sh --skip-start --only d-series`
  - after fixes: pass=3 fail=0 skip=0
- `./run-e2e.sh`
  - final: pass=10 fail=0 skip=0 (`dev/reports/20260523133947-e2e-test.md`)

No plugin-side defect was found during this expansion. All fixes were in the notes-side E2E harness and environment startup scripts.

---

### 9. Test operational assets (notes side)

Policy:
- Personal operational assets supplementing plugin-side tests are placed in `lockable-resources-remote-notes`
- Document execution order, commands, and prerequisites so assets remain reusable after M1 completion

Purpose:
- Leave Step 7 and Step 8 execution paths in an unambiguous state
- Leave minimal operational assets reusable for M2+

Target repository:
- `lockable-resources-remote-notes`

Implementation candidates:
- Add test execution procedure notes to `dev/docs/`
- Organize `dev/jenkins-env/` README or run scripts
- Consolidate recommended plugin-side commands in notes

Completion criteria:
- Entry points for Step 7 / Step 8 are organized on the notes side
- Prerequisites and known constraints are documented for easy onboarding in a new environment

- [ ] Implementation complete
- [ ] Content review complete

Notes:
- Date:
- Commit:
- Changed files:
- Verification:
- Notes:

---

## Test execution summary (finalized policy as of M1)

1. Step 7 is the formal test in `lockable-resources-plugin`
2. Step 8 is personal-environment automated E2E in `lockable-resources-remote-notes`
3. Step 9 is operational asset preparation for running Step 7/8
4. If the only reason for not including something in the plugin is "environment dependency", send it to Step 8/9
5. Any verification worth keeping in upstream should first be considered for Step 7

## `mvn test` recovery procedure (for reference)

### Background (lessons learned)

- Many `LockableResourcesManager is missing its descriptor` messages do not necessarily mean a code regression.
- Even on the same commit, if the state of generated artifacts (e.g., `target/`) is corrupted, JenkinsRule-based tests can fail in a cascade.
- Comparative verification must be run in a clean worktree to avoid false-positive bisect results.

### First steps (quickest recovery)

1. Check the working tree state.
2. Delete `target/` and regenerate.
3. Run representative JenkinsRule tests first.
4. If the problem is gone, run the full `mvn test`.

Example:

```bash
cd /home/ksato/projects/jenkins/remote-lr/lockable-resources-plugin
git status --short
rm -rf target
$HOME/.local/apache-maven-3.9.9/bin/mvn test -Dtest=org.jenkins.plugins.lockableresources.actions.LockableResourcesRootActionTest
$HOME/.local/apache-maven-3.9.9/bin/mvn test
```

### Isolation (regression vs. environment)

1. Check out the same commit into a clean worktree.
2. Run `mvn test` there.
3. If it succeeds in the clean worktree, treat it as an environment/artifact problem first.
4. If it also fails in the clean worktree, proceed with diff analysis as a code regression.

Example:

```bash
git worktree add -f /tmp/lr-check <commit-hash>
cd /tmp/lr-check
$HOME/.local/apache-maven-3.9.9/bin/mvn test
```

### Fixed rules going forward (to prevent recurrence)

1. Run each bisect step in a clean worktree.
2. On `mvn test` failure, first retry after `target/` regeneration before declaring a regression.
3. Avoid interrupting long test runs (if interrupted, regenerate `target/` before re-running).
4. First-pass failure diagnosis uses surefire reports (`target/surefire-reports/*.txt`).
5. "Many simultaneous failures + startup initialization errors" → suspect environment inconsistency before individual test issues.

## Final stabilization procedure (confirmed for M1)

### Prerequisites
- bash in WSL or Linux environment
- Maven 3.9.9 at `$HOME/.local/apache-maven-3.9.9/bin/mvn`

### Procedure

#### 1. Stop any concurrent Maven processes
```bash
pkill -f "mvn" || true
```

#### 2. Reset working directory
```bash
cd /home/ksato/projects/jenkins/remote-lr/lockable-resources-plugin
rm -rf target
```

#### 3. Verify Extension index generation
```bash
$HOME/.local/apache-maven-3.9.9/bin/mvn -DskipTests test-compile
ls target/classes/META-INF/annotations
```

**Check**: Confirm that `hudson.Extension` and `hudson.Extension.txt` are visible.

#### 4. Run the full test suite
```bash
$HOME/.local/apache-maven-3.9.9/bin/mvn test
```

**Expected result**: `Tests run: 278, Failures: 0, Errors: 0, Skipped: 1, BUILD SUCCESS`

### Troubleshooting

**Symptom 1**: `hudson.Extension` file not visible in Step 3
- **Cause**: Possibly corrupted Maven cache
- **Fix**:
  ```bash
  rm -rf ~/.m2/repository/org/jenkins-ci/tools/maven-hpi-plugin/3.1814.v77d15159f9b_d
  $HOME/.local/apache-maven-3.9.9/bin/mvn -U -DskipTests test-compile
  ls target/classes/META-INF/annotations
  ```

**Symptom 2**: `cannot find symbol` for main classes during test execution
- **Cause**: Build artifact state inconsistency (usually transient)
- **Fix**: Restart WSL, then resume from Step 2

**Symptom 3**: Many `LockableResourcesManager is missing its descriptor` errors
- **Cause**: Missing Extension index (descriptor registration failure)
- **Fix**: Return to Step 3 Extension index check. Confirm no concurrent Maven processes in Step 1.

### Notes
- maven-hpi-plugin POM cache warnings may appear but do not prevent tests from succeeding in some cases
- First run takes approximately 14 minutes (subsequent runs are faster with incremental caching)
- Skipped: 1 is the known bug `LockStepInversePrecedenceTest#lockInverseOrderWithLabel` (JENKINS-40787 / GitHub #861)

## Commit conventions (for this work)

- One step = one commit as a baseline
- Commit messages use imperative mood, kept concise
- Avoid changes spanning multiple steps in one commit
- Update the step definition in this file whenever a spec change is introduced

## Current Status

- Start date: 2026-05-09
- **Plugin-side M1 implementation: Steps 0–8 complete ✅** (Last verified: 2026-05-23, BUILD SUCCESS via `./stabilize-build.sh` (`mvn test`) / 278 tests / Failures: 0 / Errors: 0 / Skipped: 1)
- **Test stabilization: Final procedure confirmed ✅** (2026-05-23, BUILD SUCCESS confirmed on re-run)
- Next action: Step 9 (notes-side test operational asset preparation / operational documentation completion)
- Blockers: None
- Latest build: Total time 14:28, all tests passed (log: `dev/reports/20260523135413-mvn-test.log`)

### Branch maintenance notes

- PR #1028 (NodesMirror package fix) cherry-picked onto current master (commit `e4f70c3`)
- Feature branch rebased on this cherry-pick-applied master (2026-05-16)
- Once #1028 is merged into upstream master, drop the cherry-pick commit and rebase again
- **Update the hashes below to actual commit hashes after final verification when Steps 7–9 are complete**
