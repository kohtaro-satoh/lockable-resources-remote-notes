# M1G Result (Remote lock - Phase 1 / M1G)

> Design: `LRR_DESIGN_P1_M1G.md` / Steps: `LRR_IMPLEMENTATION_STEPS_P1_M1G.md`
> Branch: `feature/1025-remote-lr-p1-m1g` (base `feature/1025-remote-lr-p1` = `de54e90`)

## Summary

**Behaviour-preserving refactor.** The remote-specific logic that M1F had inlined into existing core files was
cohered into the `org.jenkins.plugins.lockableresources.remote` package, **shrinking the diff to existing core
files so it reads as a minimal feature addition**. Behaviour, timing, logging and serialize-crossing semantics
are unchanged.

## Extractions performed

### ① Client state machine (`LockStepExecution` → remote package)

- New `RemoteLockSession` (`Serializable`) holds the acquire→poll→heartbeat→release state machine; only the
  step-integration points (body invocation, onSuccess/onFailure) remain in `LockStepExecution` via a `Host`
  interface.
- New helpers: `RemoteLockRouting` (peer/delegated routing, connection lookup, display target) and
  `RemoteCredentials` (Basic auth header resolution).
- What remains in `LockStepExecution`: the `start()` branch, `runBody` (was `proceedRemote`, the body
  invocation), `RemoteCallback` (delegates release on body finish), and the `onResume`/`stop` delegation.

### ② Server resolution (`LockableResourcesManager` → remote package)

- New `RemoteResolver` (stateless collaborator) holds the admission + canonical resolution:
  `validateRemoteSelectors` / `toRemoteStructs` / `availableForRemote` / `remoteLockEnvVars`, etc.
- Uses **only the LRM's public accessors** (`getExposeLabels`/`fromName`/`getResources`/
  `getAvailableResources(Predicate)`); no new internals exposed. The `syncResources` contract stays with the
  callers (`RemoteLockManager.enqueue` / `getNextRemoteEntry`).
- Callers repointed to `RemoteResolver`.

### Core seams intentionally kept (design §2)

The `getAvailableResources(Predicate)` overload / the unified-queue `proceedNextContext` interleaving hook +
remote queue ops / `LockStep.serverId` / the `LockableResource` remote-lock state / global config (Q2: kept).

## Diff reduction (added lines in the 5 core files vs master)

| File | M1F | M1G | Moved to |
|---|---|---|---|
| `LockStepExecution.java` | +553 | **+167** | `RemoteLockSession` + `RemoteLockRouting` + `RemoteCredentials` |
| `LockableResourcesManager.java` | +575 | **+419** | `RemoteResolver` |
| `LockableResource.java` | +44 | +44 | (remote-lock state, kept) |
| `LockStep.java` | +14 | +14 | (serverId, kept) |
| `actions/LockableResourcesRootAction.java` | +61 | +61 | (admin force-release, kept) |
| **Total** | **+1208** | **+665** | cohered into 4 new `remote/` classes |

> The state machine and resolution logic that reviewers fear are gone from the core and appear as an
> independent addition in the new remote package.

## Verification

- **Full mvn: 382 tests / 0 failures / 1 skip / BUILD SUCCESS** (`dev/reports/20260615082746-mvn-test.log`,
  worktree, committed HEAD `57d2e6d`). Identical count to M1F — **evidence that tests and behaviour are
  unchanged** (no new unit tests added; the existing suite is the net).
- **E2E `--clean-start`: 20/20 PASS / 0 fail** (`dev/reports/20260615084634-e2e-test.md`). The scenarios that
  exercise the moved code in a live environment — S09 delegated-mode, S11 heartbeat-resilience, S13
  stale-admin-release, S16 remote-resource-properties, S17 remote-unknown-rejected — are all green.
- Server-side targeted tests (`RemoteLockManagerTest` 34 + `RemoteApiV1ActionTest`) were run in-place first
  (green).

## Commits

- plugin `57d2e6d` (m1g branch, single commit). No push.
- notes committed in this step (DESIGN/STEPS/RESULT j+e, README index/Status, reports trimmed to one each).

## Open items / next

- M1G is packaging only. **M1E-1 (promotion-path ephemeral re-creation) remains an intentionally deferred
  known item** (design P1_M1F §4).
- Client UI / read-only mirror (Phase 2) is a separate cycle.
- First-PR strategy (splitting off the no-op core seams, securing #1025 consensus) is tracked separately (see
  [[remote-lock-project-state]]).
