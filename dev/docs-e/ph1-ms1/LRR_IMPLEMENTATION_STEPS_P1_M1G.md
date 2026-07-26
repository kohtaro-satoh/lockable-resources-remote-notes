# M1G Implementation Steps (Remote lock - Phase 1 / M1G)

Progress tracker for M1G (design in `LRR_DESIGN_P1_M1G.md`).
**Behaviour-preserving refactor** — cohere the remote logic into the `remote` package, minimizing the diff to
existing core files. Regression net = existing mvn 382 + E2E 20/20 staying green (no new E2E added).

---

## Steps

### 0. Preparation

- [x] Create the m1g branch (squash base `de54e90` = `feature/1025-remote-lr-p1`) = `feature/1025-remote-lr-p1-m1g`
- [x] Read the code to move (`LockStepExecution` state machine / LRM resolution + queue / `RemoteLockManager.enqueue` / `RemoteQueueEntry`)
- [x] `LRR_DESIGN_P1_M1G` / this doc (j+e)

### Step 1: Extraction ② server resolution → `remote.RemoteResolver` (first, lower risk)

- [x] New `RemoteResolver` (remote package); holds an LRM reference, uses only public accessors.
  - [x] Move: `validateRemoteSelectors` / `validateSelector` / `isExposed` / `hasExposedCandidate` / `toRemoteStructs` / `addRemoteStruct` / `availableForRemote` / `remoteLockEnvVars` / `parseSelectStrategy`
- [x] Repoint callers: `RemoteLockManager.enqueue` / `LRM.getNextRemoteEntry` / `RemoteQueueEntry.onAcquired`
- [x] Remove the moved methods from the LRM (the `getAvailableResources(Predicate)` seam, the queue bridge, and config stay)
- [x] Compile (test-compile) green
- [ ] Regression covered by existing `RemoteLockManagerTest` + `RemoteApiV1ActionTest` (targeted run green; no dedicated test added)

### Step 2: Extraction ① client state machine → `remote.RemoteLockSession` + helpers

- [x] `RemoteLockRouting` (static): `isRemoteRequest` / `effectiveServerId` / `findConnection` / `displayTarget`
- [x] `RemoteCredentials` (static): `basicAuthHeader(remote, run)`
- [x] `RemoteLockSession` (Serializable) + `Host` interface: move the acquire/poll/heartbeat/release machine
- [x] Reduce `LockStepExecution` to a thin shim: `start()` branch / `runBody` (was proceedRemote) / `RemoteCallback` / `onResume`+`stop` delegation
- [x] Shared static `buildLockEnvVars` stays in `LockStepExecution`
- [x] Compile (test-compile) green

### Step 3: Cleanup

- [x] Prune unused imports in core files (checkstyle clean)
- [x] Confirm `LockableResourcesRootAction.doReleaseRemoteLock` stays (outside scope)
- [x] Record before/after core diff: 5 core files **+1208 → +665** insertions; the state machine + resolution now in 4 new `remote/` files

### Step 4: Build, E2E, commit

- [ ] `dev/stabilize-build.sh` (worktree, committed HEAD): full mvn success (382 / 0 failures)
- [ ] `dev/jenkins-env/run-e2e.sh --clean-start`: all 20 PASS (esp. S09/S11/S13/S16/S17)
- [ ] Sync docs-e (DESIGN/STEPS/RESULT), update README index/Status
- [ ] plugin commit (no Co-Authored-By), notes commit. No push

---

## Changed files (plugin)

| File | Change |
|---|---|
| `remote/RemoteResolver.java` | new (resolution logic from the LRM) |
| `remote/RemoteLockSession.java` | new (state machine from LockStepExecution) |
| `remote/RemoteLockRouting.java` | new (routing helper) |
| `remote/RemoteCredentials.java` | new (auth header helper) |
| `LockStepExecution.java` | state machine removed → Host shim (+553 → +167) |
| `LockableResourcesManager.java` | resolution removed (+575 → +419); seam/queue/config kept |
| `remote/RemoteLockManager.java` / `remote/RemoteQueueEntry.java` | callers repointed to RemoteResolver |

## E2E policy

Behaviour unchanged → **no new E2E**. Existing 20/20 regression is sufficient (the moved state machine,
resolution, and queue are exercised by existing scenarios in a live environment).
