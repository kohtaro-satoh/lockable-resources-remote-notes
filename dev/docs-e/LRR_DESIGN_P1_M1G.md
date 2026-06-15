# Remote Lockable Resources Design (Phase 1 / M1G)

> **Source:** [jenkinsci/lockable-resources-plugin #1025](https://github.com/jenkinsci/lockable-resources-plugin/issues/1025)
> **Prerequisite docs:** `LRR_DESIGN_P1_M1F.md` (M1F spec) / `LRR_REVIEW_P1_M1F.md` (M1F completion review)
> **Scope:** Phase 1 M1G (**behaviour-preserving refactor** — cohere the remote feature into the `remote`
>   package so the diff to existing core files reads, to a reviewer, as a minimal feature addition)

---

## 1. What M1G is — packaging to make the core diff look minimal

M1G is neither a feature nor a behaviour change. Keeping every externally observable behaviour identical, it
moves the remote-specific logic that M1F had inlined into core classes (`LockStepExecution` /
`LockableResourcesManager`, etc.) into the `org.jenkins.plugins.lockableresources.remote` package.

> **Motivation (user-confirmed 2026-06-15):** when the first upstream PR lands, a reviewer should see
> "existing files barely change; the remote feature is added as a self-contained package." Of the master..M1F
> diff, **~1,208 lines are woven into 5 existing core files** (analysis after [[LRR_REVIEW_P1_M1F]]). Most of
> that is remote logic that merely *lives* in a core file without depending on core internals, and can move
> into the `remote` package.

### Invariants (most important)

- **Behaviour fully preserved.** Lock semantics, transparent equivalence, exposure policy, the HTTP API,
  timing, logging, and serialize-crossing onResume/stop behaviour are unchanged. Everything is "move a method"
  plus "repoint the caller"; no logic is rewritten.
- **The existing tests are the net.** mvn 382 + E2E 20/20 are the regression check. M1G adds **no new E2E
  scenario** (behaviour is unchanged). New classes may get placement-fixing **unit tests as needed**, but the
  pass/fail bar is the existing suite staying green.
- **Scope (user-confirmed 2026-06-15):** both extractions (① client state machine / ② server resolution) in
  **one M1G cycle**. The global configuration (`remoteApiEnabled`/`exposeLabel`/`clientId`/`forcedServerId`/
  `remotes`) **stays on the LRM** (only logic moves).

---

## 2. The unavoidable core seams (not moved) and why

The following are the minimal touch-points the remote feature must have in core; M1G **intentionally keeps
them in core**.

| Core touch-point | Size | Why it stays |
|---|---|---|
| `LRM.getAvailableResources(..., Predicate<LockableResource> candidateFilter)` overload (old signature delegates via `r -> true`) | ~5 lines | The heart of canonical delegation — the one seam that lets "remote ride local lock()". Local behaviour is unchanged |
| `LRM.proceedNextContext` local/remote interleaving hook + remote queue ops (`queueRemote`/`unqueueRemote`/`lockForRemote`/`unlockRemoteResources`/`getNextRemoteEntry`/`proceedRemoteEntry`/`remoteQueueEntries`) | ~120 lines | The legitimate core integration of the **unified priority queue** (remote competes fairly with local in the same drain). A separate queue would lose unified fairness. It mutates resource state (`resources`), so it belongs to the LRM |
| `LockStep.serverId` parameter | +14 | Public DSL surface. Unavoidable |
| `LockableResource.remoteLockedBy` / accessors | +44 | The resource's remote-lock state; needed for dashboard display and to exclude it from local locking |
| Global config fields + getters/setters/doCheck (LRM) | ~180 | The LRM is already a `GlobalConfiguration`; holding config there is idiomatic, and getters/setters are not the diff reviewers fear (Q2: keep on LRM) |

> Everything else (the client state machine, the server resolution) merely *co-locates* in a core file and is
> moved into the `remote` package in §3/§4.

---

## 3. Extraction ① client state machine → `remote.RemoteLockSession` (out of `LockStepExecution`)

### Before (M1F)

`LockStepExecution` (+553) inlines the whole remote acquire→poll→heartbeat→release state machine: fields
(`remotePollTask`/`remoteHeartbeatTask`/`remoteServerId`/`remoteLockId`/`remoteLastState`/`remoteBodyStarted`/
`consecutivePollFailures`/`remoteCompletionSignaled`/`MAX_CONSECUTIVE_POLL_FAILURES`) and methods
(`startRemoteFlow`/`startRemotePolling`/`pollRemoteStatus`/`startRemoteHeartbeat`/`releaseRemoteLockBestEffort`/
`cancel*`/`finishRemoteFailure`/`proceedRemote`/`buildRemoteFailureMessage`/`resolveRemoteDisplayTarget`/
`findRemoteConnectionOrFail`/`resolveAuthorizationHeader`/`resolveEffectiveServerId`/`isRemoteLockRequest`/
`RemoteCallback`).

### Destinations and split

| New class (remote package) | Contents |
|---|---|
| **`RemoteLockSession`** (`Serializable`) | The acquire/poll/heartbeat/release state machine. Persisted fields (serverId/lockId/lastState/bodyStarted/completionSignaled) + transient (pollTask/heartbeatTask/consecutivePollFailures). Calls back into a `Host` interface for the step-integration points |
| **`RemoteLockRouting`** (static helpers) | `isRemoteRequest(step, lrm)` / `effectiveServerId(step, lrm, logger)` / `findConnection(lrm, serverId)` / `displayTarget(step)` |
| **`RemoteCredentials`** (static helper) | `basicAuthHeader(remote, run)` (credentials → Authorization header; takes the `Run`) |

### The `Host` seam (implemented by `LockStepExecution`)

`RemoteLockSession` delegates only what depends on the step execution's internals (`StepContext` / body
invocation / serialization) to the host, which keeps **a thin integration shim**:

```
interface Host extends Serializable {
    StepContext context();                       // get(Run/FlowNode/TaskListener), onFailure/onSuccess, newBodyInvoker
    LockStep step();
    void runBody(String displayTarget, Map<String,String> lockEnvVars, String lockId);  // body invocation
}
```

- On ACQUIRED the session calls `host.runBody(...)`; the body invocation (`newBodyInvoker` + the release
  `RemoteCallback`) stays in `LockStepExecution` because it needs the `StepContext`.
- SKIPPED → `onSuccess(null)`; FAILED/EXPIRED/CANCELLED/UNKNOWN → the session fails the context.
- `LockStepExecution.start()` is just `if (RemoteLockRouting.isRemoteRequest(step, lrm)) { remoteSession = new RemoteLockSession(); return remoteSession.start(this); }`.
- `onResume()` / `stop()` delegate to the session when present.

### After

What remains in `LockStepExecution`: the `start()` branch, `runBody` (the body invocation), `RemoteCallback`
(release on body finish — cleanup delegated to the session), and the `onResume`/`stop` delegation.
**+553 → target +80–100 lines.**

---

## 4. Extraction ② server resolution → `remote.RemoteResolver` (out of `LockableResourcesManager`)

### Methods moved (LRM → `RemoteResolver`)

The **pure** admission + canonical-resolution logic: `validateRemoteSelectors` / `validateSelector` /
`isExposed` / `hasExposedCandidate` / `toRemoteStructs` / `addRemoteStruct` / `availableForRemote` /
`remoteLockEnvVars` / `parseSelectStrategy` (~140 lines).

### Collaborator design

`RemoteResolver` holds a reference to the `LockableResourcesManager` and uses **only its public API**:
`getExposeLabels()` (config, stays) / `fromName(name)` / `getResources()` /
`getAvailableResources(structs, logger, strategy, predicate)` (the §2 seam). All already public — no new LRM
internals are exposed (encapsulation is not worsened). `remoteLockEnvVars` keeps using the local-shared static
`LockStepExecution.buildLockEnvVars`.

### Callers repointed

- `RemoteLockManager.enqueue`: `lrm.validateRemoteSelectors/toRemoteStructs/availableForRemote` → `resolver.…`,
  `LockableResourcesManager.remoteLockEnvVars` → `RemoteResolver.remoteLockEnvVars` (`new RemoteResolver(lrm)`).
- `LRM.getNextRemoteEntry` (queue promotion, stays in core): `availableForRemote(...)` →
  `new RemoteResolver(this).availableForRemote(...)`.
- `RemoteQueueEntry.onAcquired`: `LockableResourcesManager.remoteLockEnvVars` → `RemoteResolver.remoteLockEnvVars`.

### Preserving the `syncResources` contract

The moved methods keep the "call under `syncResources`" contract. The callers (`RemoteLockManager.enqueue` /
`LRM.getNextRemoteEntry`) already run inside `synchronized(syncResources)`, so **the locking responsibility
stays with the caller** — `RemoteResolver` never takes the lock itself.

### Remaining remote footprint in core (LRM)

The §2 seam + queue bridge + config. **+575 → ~+419** (the ~140 lines of resolution move out; what remains is
legitimate core integration: the unified queue, config, the Predicate seam).

## 5. Other

- **`LockableResourcesRootAction.doReleaseRemoteLock` (+61):** the dashboard admin force-release action.
  Belongs to the HTTP/permission/RootAction context, so it **stays in core**; it is outside M1G's focus.
- **`buildLockEnvVars` (static in `LockStepExecution`):** shared with local `proceed`, so it **stays** (local,
  not remote-specific).

## 6. Scope

### In (M1G)

| Item | Detail |
|---|---|
| Extraction ① | New `RemoteLockSession` + `RemoteLockRouting` + `RemoteCredentials`; move the state machine out of `LockStepExecution`, leaving only the Host shim |
| Extraction ② | New `RemoteResolver`; move LRM's admission/resolution logic and repoint callers |
| Tests | Existing 382 + E2E 20/20 stay green; placement-fixing unit tests as needed |
| Docs | This doc + STEPS (j+e), RESULT, README index/Status |

### Out (M1G)

| Item | Note |
|---|---|
| Behaviour change / new feature / new E2E | None — pure refactor |
| Moving config to a separate holder | Q2: keep on LRM |
| Unified queue (proceedNextContext hook, remote queue ops) | Kept in core as legitimate integration (§2) |
| Client UI / read-only mirror | Separate cycle (Phase 2; discussion after [[LRR_REVIEW_P1_M1F]]) |

## 7. Verification

- `dev/stabilize-build.sh` (worktree, builds the committed HEAD) → full mvn success (382 + any new unit tests,
  0 failures).
- `dev/jenkins-env/run-e2e.sh --clean-start` all 20 PASS (behaviour-unchanged regression; S09 delegated /
  S11 heartbeat-resilience / S13 stale-admin-release / S16 resource-properties / S17 unknown-rejected exercise
  the moved state machine, resolution, and queue in a live environment).

## Change log

- 2026-06-15: Initial version. Following the post-M1F "core diff is large" analysis (~1,208 lines across 5
  existing files), M1G is defined as a behaviour-preserving cycle that coheres the remote logic into the
  `remote` package. Extraction ① (`RemoteLockSession` + helpers, ~450 lines out of `LockStepExecution`) and ②
  (`RemoteResolver`, ~140 lines out of the LRM) in one cycle. Config stays on the LRM; the unified queue, the
  Predicate seam, and the public DSL/resource state are intentionally kept as unavoidable core seams (§2).
