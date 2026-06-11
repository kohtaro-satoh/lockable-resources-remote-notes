# M1A Implementation Steps (Remote lock - Phase 1 / M1A)

This file is a personal progress tracker.
It breaks the M1A implementation into feature-scoped commits for later traceability.

## How to Use

- Check off each step when complete.
- Record "commit", "target files", and "verification result" for each step.
- One step = one commit as a baseline (multiple commits per step are fine if needed).

## M1A Goals

Bring M1 (minimal peer mode) to full semantic equivalence with local `lock()` — making the remote layer
a transparent wrapper for all lock DSL semantics.

| Goal | M1 current state | M1A target |
|---|---|---|
| Transparent lockRequest | Sends flat `resource` / `skipIfLocked` fields | Sends a nested `lockRequest` object carrying all lock semantics |
| Multi-resource acquisition | Single resource name only | `label` + `quantity` / `extra` support |
| Equivalent env var expansion | Client manually builds vars from `step.variable` + single name | Server generates `lockEnvVars`; client applies them directly |
| Delegated mode | Peer mode with explicit `serverId` only | `forcedServerId` delegates all `lock()` calls to remote without DSL changes |

Starting branch: `feature/1025-remote-lockable-resources-p1-m1a`
(M1's 14 commits + 1 test-adaptation commit; all 326 tests confirmed passing)

Reference design: `dev/docs-e/LRR_DESIGN_P1_M1A.md`

---

## Step List

### 0. Preparation (complete)

- [x] Working branch `feature/1025-remote-lockable-resources-p1-m1a` ready
- [x] All M1 tests (326) confirmed passing (BUILD SUCCESS)
- [x] `LRR_DESIGN_P1_M1A.md` design doc reviewed
- [x] Build environment (stabilize-build.sh / worktree mode) confirmed stable

Notes:
- Date: 2026-06-10
- Branch HEAD: `e8b8431` (test-adaptation commit; starting point for M1A implementation)
- Build log: `dev/reports/20260610231428-mvn-test.log` (BUILD SUCCESS / 326 tests)

---

### 1. `RemoteLockRequest` DTO + lockRequest wire format change

Purpose:
- Migrate the wire format from M1's flat fields (`resource`, `skipIfLocked` at the top level) to the
  M1A `lockRequest` nested object.
- Allow all lock-semantics parameters from `LockStep` to be transparently forwarded from client to server.
- **Server-side acquisition logic is not changed in this step** (that is Step 2).
  Only the wire format is updated to match the M1A spec.

#### Design notes (see `LRR_DESIGN_P1_M1A.md` §4)

POST /acquire request body sent by the client:
```jsonc
{
  "lockRequest": {
    "resource": "board-a1",
    "label": "hw-board",
    "quantity": 2,
    "variable": "LOCKED_RESOURCE",
    "inversePrecedence": false,
    "resourceSelectStrategy": "SEQUENTIAL",
    "skipIfLocked": false,
    "extra": [],
    "priority": 10,
    "timeoutForAllocateResource": 5,
    "timeoutUnit": "MINUTES",
    "reason": "deploy"
  },
  "heartbeatIntervalSeconds": 10,
  "clientId": "https://jenkins-a.example.com/"
}
```

`serverId` and `forcedServerId` are routing concerns and must not appear inside `lockRequest`.

#### Implementation

**New class**
- `src/main/java/.../remote/RemoteLockRequest.java` (new)
  - Data class holding all lock-semantics fields: `resource` / `label` / `quantity` / `variable` /
    `inversePrecedence` / `resourceSelectStrategy` / `skipIfLocked` / `extra` / `priority` /
    `timeoutForAllocateResource` / `timeoutUnit` / `reason`
  - Factory method `static RemoteLockRequest from(LockStep step)` to build from DSL step
  - Annotate fields with `@NonNull` / `@CheckForNull` as appropriate
  - Both `resource` and `label` being null is invalid (validation at call site)

**Client-side changes**
- `RemoteApiClient.enqueueAcquire()`:
  - Signature change: replace individual `String resource, boolean skipIfLocked` parameters with
    a single `RemoteLockRequest lockRequest` parameter
  - Build request JSON as `{ "lockRequest": { ... }, "heartbeatIntervalSeconds": 10, "clientId": "..." }`
  - Serialize `lockRequest` fields; skip null values (also skip `extra` when empty)
- `LockStepExecution`:
  - Consolidate `enqueueAcquire()` call site to use `RemoteLockRequest.from(step)`
  - Relax `validateRemoteResource()` (currently requires non-empty `resource`): only throw
    if both `resource` and `label` are null (allows label-only locks)

**Server-side changes**
- `RemoteApiV1Action.AcquireRouter.doIndex()`:
  - Parse the nested `"lockRequest"` object (return 400 `MISSING_LOCK_REQUEST` if absent)
  - Read `resource`, `label`, `skipIfLocked`, etc. from `lockRequest`
  - Update `RemoteLockManager.enqueue()` call signature to accept `RemoteLockRequest`
    (acquisition logic extended in Step 2)
  - Validation: return 400 `MISSING_LOCK_TARGET` if both `resource` and `label` are null

**Test updates**
- `RemoteApiClientTest`: update `enqueueAcquire()` call sites to `RemoteLockRequest` type;
  add assertion that the nested `lockRequest` JSON is correctly generated
- `RemoteApiV1ActionTest`: test POST /acquire with nested `lockRequest` format
  (old flat format is not needed for backward compatibility; remove those cases)

Completion criteria:
- `mvn test -Dtest=RemoteApiClientTest,RemoteApiV1ActionTest` passes
- `RemoteApiClient` sends the new nested `lockRequest` JSON
- `RemoteApiV1Action` correctly parses the `lockRequest` object
- `LockStepExecution` passes all `LockStep` fields via `RemoteLockRequest`
- `mvn test` full run: BUILD SUCCESS (existing 326 + new tests)

- [x] Implementation complete
- [x] `mvn test` verification complete
- [x] Committed

Notes:
- Date: 2026-06-11
- Commit: `b383685`
- Changed files:
  - src/main/java/.../remote/RemoteLockRequest.java (new)
  - src/main/java/.../remote/RemoteLockRecord.java (edited: `@NonNull` → `@CheckForNull` on resourceName)
  - src/main/java/.../remote/RemoteApiClient.java (edited: enqueueAcquire signature + buildLockRequestJson)
  - src/main/java/.../remote/RemoteLockManager.java (edited: enqueue signature + label-only FAILED handling)
  - src/main/java/.../LockStepExecution.java (edited: resolveRemoteDisplayTarget + RemoteLockRequest.from)
  - src/main/java/.../actions/RemoteApiV1Action.java (edited: lockRequest nested parse)
  - src/test/java/.../remote/RemoteApiClientTest.java (edited: enqueueAcquire call sites updated)
  - src/test/java/.../actions/RemoteApiV1ActionTest.java (edited: lockRequest nested format tests)
  - src/test/java/.../remote/RemoteLockManagerTest.java (edited: enqueue call site updated)
  - src/test/java/.../actions/LockableResourcesRootActionTest.java (edited: enqueue call sites updated)
- Verification: Tests run: 326, Failures: 0, Errors: 0, Skipped: 1 — BUILD SUCCESS (19:57)

---

### 2. Server-side: label/quantity multi-resource acquisition

Purpose:
- Enable batch acquisition of multiple resources using `lockRequest.label` + `lockRequest.quantity`.
- M1 handled only a single resource by name; M1A achieves server-side parity with label-based and
  quantity-based local `lock()` behavior.
- Store the list of acquired resource names in the record so all of them are released together.

#### Design notes

Acquisition logic for `RemoteLockManager.enqueue()` / `tryAcquireQueued()`:

| lockRequest parameters | Server behavior |
|---|---|
| `resource` only | `lrm.fromName(resource)` → `isFree()` + `setRemoteLockedBy()` (same as M1) |
| `resource` + `extra[]` | Acquire `resource` and all `extra` resources atomically (all must be free; otherwise wait) |
| `label` + `quantity` | Find `quantity` free resources carrying the label from `lrm.getResourcesWithLabel()` |
| `label` only (quantity=0) | Treated as quantity=1 |
| `skipIfLocked=true` | If not immediately acquirable, transition to SKIPPED instead of remaining QUEUED |

`exposeLabel` check:
- Resource-based: the specified resource must carry the `exposeLabel` (same as M1)
- Label-based: each candidate resource must carry the `exposeLabel`

`RemoteLockRecord` resource storage:
- Replace M1's `String resourceName` with `List<String> acquiredResourceNames` (null until acquired)
- Retain retry-relevant fields from the lockRequest: `label`, `quantity`, `resource`, `skipIfLocked`

Release logic (`RemoteLockManager.release()`):
- Call `setRemoteLockedBy(null)` for every entry in `acquiredResourceNames`

#### Implementation

- `RemoteLockRecord`:
  - Redesign to hold retry info fields + `List<String> acquiredResourceNames`
  - Retry info constructor accepts `RemoteLockRequest`
  - Change `markAcquired(List<String> names)` signature (lockEnvVars added in Step 3)
  - Add `getAcquiredResourceNames()`. Keep `getResourceName()` returning the first entry
    for backward compatibility, or remove it if no callers remain
- `RemoteLockManager`:
  - Change `enqueue(RemoteLockRequest, String clientId)` signature
  - Implement label-based acquisition using `lrm.getResourcesWithLabel()`
  - Implement resource + extra simultaneous acquisition
  - Update `tryAcquireQueued()` for label/quantity/extra support
  - Update `release()` to free all entries in `acquiredResourceNames`
  - Extract `isExposedResource(LockableResource, LockableResourcesManager)` helper for exposeLabel check

Completion criteria:
- `mvn test -Dtest=RemoteLockManagerTest,RemoteApiV1ActionTest` passes
- label + quantity=2 acquisition transitions correctly through `QUEUED → ACQUIRED`
- `skipIfLocked=true` with a busy label-based resource results in `SKIPPED`
- `release` frees all entries in `acquiredResourceNames`
- resource + extra simultaneous acquisition works; if any extra resource is busy, stays `QUEUED`
- `mvn test` full run: BUILD SUCCESS

- [x] Implementation complete
- [x] `mvn test` verification complete
- [x] Committed

Notes:
- Date: 2026-06-11
- Commit: `e18f982`
- Changed files:
  - src/main/java/.../remote/RemoteLockRecord.java (edited: holds RemoteLockRequest + acquiredResourceNames)
  - src/main/java/.../remote/RemoteLockManager.java (edited: label/quantity/extra acquisition logic)
  - src/test/java/.../remote/RemoteLockManagerTest.java (edited: 10 new tests)
- Verification: Tests run: 336, Failures: 0, Errors: 0, Skipped: 1 — BUILD SUCCESS

---

### 3. lockEnvVars: generation, transmission, reception, and application

Purpose:
- Generate `lockEnvVars` on the server at acquisition time and include them in
  `GET /acquire/{lockId}` responses.
- Have the client receive `lockEnvVars` and apply them to the `{ body }` execution context,
  achieving local `lock()`-equivalent environment variable expansion.
- Delivers the equivalence goal stated in the design spec §2.

#### Design notes

`lockEnvVars` generation rules (mirrors local `lock()` variable expansion):
- When `lockRequest.variable` is set:
  - `{variable}`: space-separated list of all acquired resource names (e.g. `"r1 r2"`)
  - `{variable}0`, `{variable}1`, ...: individual resource names
- When `variable` is not set: return `lockEnvVars` as `null`
  (client runs body without injecting any environment variables)

Example `GET /acquire/{lockId}` response when state=ACQUIRED:
```jsonc
{
  "lockId": "...",
  "state": "ACQUIRED",
  "errorCode": null,
  "message": null,
  "lockEnvVars": {
    "LOCKED_RESOURCE": "r1 r2",
    "LOCKED_RESOURCE0": "r1",
    "LOCKED_RESOURCE1": "r2"
  }
}
```

#### Implementation

**Server-side**
- `RemoteLockRecord`:
  - Add `Map<String, String> lockEnvVars` field (nullable)
  - Change `markAcquired(List<String> names, Map<String, String> lockEnvVars)` signature
  - Add `getLockEnvVars()` getter
- `RemoteLockManager`:
  - Add private `generateLockEnvVars(String variable, List<String> resourceNames)` helper:
    returns null when `variable` is null/empty; otherwise builds the map per the rules above
  - Pass `lockEnvVars` to `markAcquired()` in both `enqueue()` and `tryAcquireQueued()`
- `RemoteApiV1Action.AcquireStatusResource.doIndex()`:
  - Include `"lockEnvVars"` in the response JSON when state=ACQUIRED and it is non-null
  - Also include `"message"` field (present in the design spec but missing from M1 response)

**Client-side**
- `RemoteAcquireStatus`:
  - Add `Map<String, String> lockEnvVars` field
  - Update constructor and getter
- `RemoteApiClient.getAcquireStatus()`:
  - Parse the `"lockEnvVars"` JSON object as `Map<String, String>`
  - Return null when the key is absent or its value is null (e.g. in QUEUED state)
- `LockStepExecution.proceedRemote()`:
  - When `status.getLockEnvVars()` is non-null: apply all entries to `EnvironmentAction`
  - Remove the M1 manual variable construction code (`step.variable` + single resource name)
    and replace it with the `lockEnvVars`-based approach
  - When `lockEnvVars` is null (variable not set): run body without injecting env vars

Completion criteria:
- `mvn test -Dtest=RemoteApiV1ActionTest,LockStepRemoteTest,RemoteApiClientTest` passes
- `GET /acquire/{lockId}` response contains `lockEnvVars` when `variable` is set
- `lockEnvVars` entries are reflected in `EnvironmentAction` on the client
- With multiple acquired resources, all entries (`variable0`, `variable1`, ...) are expanded
- When `variable` is not set, `lockEnvVars=null` still allows body execution
- `mvn test` full run: BUILD SUCCESS

- [x] Implementation complete
- [x] `mvn test` verification complete
- [x] Committed

Notes:
- Date: 2026-06-11
- Commit: `50857c1`
- Changed files:
  - src/main/java/.../remote/RemoteLockRecord.java (edited)
  - src/main/java/.../remote/RemoteLockManager.java (edited)
  - src/main/java/.../actions/RemoteApiV1Action.java (edited)
  - src/main/java/.../remote/RemoteAcquireStatus.java (edited)
  - src/main/java/.../remote/RemoteApiClient.java (edited)
  - src/main/java/.../LockStepExecution.java (edited)
  - src/test/java/.../remote/RemoteAcquireStatusTest.java (edited)
  - src/test/java/.../LockStepRemoteTest.java (edited)
- Verification: Tests run: 336, Failures: 0, Errors: 0, Skipped: 1 — BUILD SUCCESS (LockStepRemoteTest: 9/9 pass)

---

### 4. `forcedServerId` delegated mode

Purpose:
- Add the `forcedServerId` controller-level setting so that all `lock()` calls are transparently
  delegated to a remote without any DSL changes.
- Coexist with peer mode (explicit `step.serverId`), with `forcedServerId` taking precedence when set.

#### Design notes (see `LRR_DESIGN_P1_M1A.md` §2, 3, 6)

Routing resolution rules:
```
if forcedServerId is set:
    target = remote identified by forcedServerId
    NOTE: if step.serverId is also given, log an INFO message and ignore it

else if step.serverId is given:
    target = (step.serverId, lockRequest)   →  peer mode

else:
    target = LOCAL                           →  existing behavior, unaffected
```

Key constraints:
- `forcedServerId` is routing information and must not appear inside `lockRequest`
- If `forcedServerId` is set but its value does not match any `remotes` key:
  validation error at save time

#### Implementation

**Configuration model**
- `LockableResourcesManager`:
  - Add nullable `forcedServerId: String` field
  - Add `getForcedServerId()` / `setForcedServerId()`
  - Add null normalization in `readResolve()`
  - In `Descriptor.configure()` or a dedicated validator: when `forcedServerId` is set,
    confirm it matches a key in `remotes` (emit `FormValidation.warning()` or error if not)

**Routing**
- `LockStepExecution.isRemoteLock()`:
  - In addition to the existing `step.serverId != null` check, return true when
    `LockableResourcesManager.get().getForcedServerId() != null`
- `LockStepExecution` remote flow entry:
  - `String effectiveServerId = lrm.getForcedServerId() != null ? lrm.getForcedServerId() : step.serverId;`
  - When both `forcedServerId` and `step.serverId` are set and differ:
    emit an INFO log line ("forcedServerId takes precedence over the pipeline-supplied serverId: ...")
  - Pass `effectiveServerId` to `findRemoteConnectionOrFail()`

**Settings UI**
- `src/main/resources/.../LockableResourcesManager/config.jelly`:
  - Add `forcedServerId` textbox to the "Remote Lockable Resources (Client)" section
    (between `clientId` and the `remotes` repeatable list is a natural position)
- `src/main/resources/.../LockableResourcesManager/config.properties`:
  - Add label key for `forcedServerId`
- `src/main/resources/.../LockableResourcesManager/help-forcedServerId.html` (new):
  - Explain delegated mode, usage example, and the caveat that all `lock()` calls are
    delegated to the configured remote when this field is set

Completion criteria:
- `mvn test -Dtest=LockStepRemoteTest,LockableResourcesManagerRemoteConnectionTest` passes
- With `forcedServerId` set, a `lock('X')` DSL without `serverId` is delegated to the remote
- With `forcedServerId` set, an explicit `serverId` in the DSL is overridden by `forcedServerId`
  (INFO log emitted)
- Without `forcedServerId`, existing peer mode and local mode are unaffected
- `forcedServerId` can be saved and reloaded through the settings UI
- `mvn test` full run: BUILD SUCCESS

- [ ] Implementation complete
- [ ] `mvn test` verification complete
- [ ] Committed

Notes:
- Date:
- Commit:
- Changed files:
  - src/main/java/.../LockableResourcesManager.java (edited)
  - src/main/java/.../LockStepExecution.java (edited)
  - src/main/resources/.../LockableResourcesManager/config.jelly (edited)
  - src/main/resources/.../LockableResourcesManager/config.properties (edited)
  - src/main/resources/.../LockableResourcesManager/help-forcedServerId.html (new)
  - src/test/java/.../LockStepRemoteTest.java (edited)
  - src/test/java/.../LockableResourcesManagerRemoteConnectionTest.java (edited)
- Verification:

---

### 5. Test expansion and regression coverage

Purpose:
- Lock in regression coverage for the M1A core features: transparent lockRequest, label/quantity
  acquisition, lockEnvVars expansion, and forcedServerId.
- Finalize test updates that were done incrementally in Steps 1–4 and fill any gaps.

Target tests (additions / extensions):

**`RemoteApiV1ActionTest`**:
- POST /acquire with nested `lockRequest` format (resource-based and label-based)
- ACQUIRED response containing `lockEnvVars`
- `exposeLabel` filter is applied correctly for label-based acquisition
  (label="hw" acquires; label="other" returns UNKNOWN_RESOURCE)
- label + insufficient quantity stays 202 + QUEUED (waiting)
- Both `resource` and `label` null returns 400 MISSING_LOCK_TARGET

**`RemoteLockManagerTest`**:
- label + quantity=2 acquire / release cycle
- `skipIfLocked=true` + label-based (SKIPPED when resources are busy)
- resource + extra simultaneous acquisition (stays QUEUED if any extra resource is busy)
- `release` frees all entries in `acquiredResourceNames`
- `generateLockEnvVars` with variable unset (returns null)
- `generateLockEnvVars` with variable set (returns correct key/value set)

**`LockStepRemoteTest`**:
- With `variable` set, `lockEnvVars`-equivalent env vars are expanded inside the body
  (`LOCKED_RESOURCE`, `LOCKED_RESOURCE0` match expected values)
- Without `variable`, body executes normally with no env var injection
- With `forcedServerId` set, a `serverId`-less DSL delegates to the remote
- With `forcedServerId` set, an explicit DSL `serverId` is overridden by `forcedServerId` (INFO log)
- Minimal end-to-end case: label-based lockRequest sent to a mocked server

**`LockableResourcesManagerRemoteConnectionTest`**:
- `forcedServerId` save and reload (Global Configure round-trip)
- Validation behavior when `forcedServerId` does not match any `remotes` key

Completion criteria:
- All added tests pass
- `mvn test` full run: BUILD SUCCESS

- [ ] Implementation complete
- [ ] `mvn test` verification complete
- [ ] Committed

Notes:
- Date:
- Commit:
- Changed files:
  - src/test/java/.../actions/RemoteApiV1ActionTest.java (edited)
  - src/test/java/.../remote/RemoteLockManagerTest.java (edited)
  - src/test/java/.../LockStepRemoteTest.java (edited)
  - src/test/java/.../LockableResourcesManagerRemoteConnectionTest.java (edited)
- Verification:

---

### 6. E2E scenario expansion (lockable-resources-remote-notes side)

Purpose:
- Verify the M1A additions (label-based acquisition + lockEnvVars expansion,
  forcedServerId delegated mode) against real Jenkins instances.
- Add 2 new scenarios to the existing 10 M1 scenarios.

New scenarios:

**`label-env-vars`** (S08):
- Controller A acquires a label-tagged resource from Controller B using a label-based lockRequest.
- Specify `variable` in the lock step; capture env vars with `printenv` / `echo ${LOCKED_RESOURCE}`
  inside the body.
- Record in the report's Checkpoint section that the env vars match the expected `lockEnvVars` values.

**`delegated-mode`** (S09):
- Set `forcedServerId = B` on Controller A.
- Run a job on A with a `lock('resource-b1')` DSL (no `serverId` argument).
- Confirm that the job acquires Controller B's resource.
- While the job is running, confirm that Controller B's LR page shows `Remote: jenkins-a`.

Existing scenario updates:
- `peer-basic` and others: update environment init scripts if resource/label setup needs to change
  (likely no impact if existing resource names are preserved)

Implementation:
- `dev/jenkins-env/scenarios/label-env-vars.sh` (new)
- `dev/jenkins-env/scenarios/delegated-mode.sh` (new)
- `dev/jenkins-env/run-e2e.sh` (edited: register S08, S09)
- `dev/jenkins-env/lib/common.sh` (edited: add `forcedServerId` configuration helper)
- `dev/docs-e/E2E_TEST_SPECIFICATION.md` (edited: add S08 and S09 scenario definitions)

Completion criteria:
- `./run-e2e.sh --only label-env-vars` passes (lockEnvVars expansion verified)
- `./run-e2e.sh --only delegated-mode` passes (forcedServerId routing verified)
- `./run-e2e.sh --only all` passes (all 12 scenarios: existing 10 + new 2)

- [ ] Implementation complete
- [ ] E2E verification complete
- [ ] Committed

Notes:
- Date:
- Commit:
- Changed files:
  - dev/jenkins-env/scenarios/label-env-vars.sh (new)
  - dev/jenkins-env/scenarios/delegated-mode.sh (new)
  - dev/jenkins-env/run-e2e.sh (edited)
  - dev/jenkins-env/lib/common.sh (edited)
  - dev/docs-e/E2E_TEST_SPECIFICATION.md (edited)
- Verification:

---

## Test execution summary (M1A policy)

1. After each step (1–4), run `mvn test -Dtest=<target tests>` to confirm step-level BUILD SUCCESS.
2. Before committing each step, run `./stabilize-build.sh` (worktree mode) for a full `mvn test`
   pass (prevents jdt.ls / `target/` interference).
3. Step 5 is verified by running the full `mvn test` suite and confirming the test count has grown.
4. Step 6 is verified using the E2E harness in `lockable-resources-remote-notes` (`./run-e2e.sh`).

## Commit conventions (M1A)

- One step = one commit as a baseline.
- Commit message examples:
  - Step 1: `feat(remote-lock): transparent lockRequest payload (M1A wire format)`
  - Step 2: `feat(remote-lock): label/quantity multi-resource acquisition (M1A server)`
  - Step 3: `feat(remote-lock): lockEnvVars generation and client application (M1A)`
  - Step 4: `feat(remote-lock): forcedServerId delegated mode (M1A)`
  - Step 5: `test(remote-lock): M1A regression coverage`
  - Step 6: `chore(e2e): add M1A scenarios (label-env-vars, delegated-mode)`
- Avoid changes that span steps.
- Update step definitions in this file whenever the spec changes.

## Current status

- Plan created: 2026-06-11
- Starting branch HEAD: `e8b8431` (M1A implementation starting point; all 326 tests passing)
- **Step 0: Complete ✅**
- Steps 1–6: Not started
- Next action: Begin Step 1 (`RemoteLockRequest` DTO + lockRequest wire format change)
