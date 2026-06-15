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

## Verification (final, on the PR branch `feature/1025-remote-lr-p1-m1` `4f3577f`)

The reports below are from the **PR branch `feature/1025-remote-lr-p1-m1`** (a single squashed commit `4f3577f`
on current upstream master `87c4a7e`, with the comment cleanup). Its tree is identical to the pre-squash
`808da92`, and the rebased (`4b40a42`) and pre-rebase m1g (`57d2e6d`) were verified with the same numbers.

- **Full mvn: 382 tests / 0 failures / 1 skip / BUILD SUCCESS** (`dev/reports/20260615141539-mvn-test.log`,
  worktree, committed HEAD `4f3577f`). **Evidence that tests and behaviour are unchanged** (no new unit tests;
  the existing suite is the net; `LockStepWithRestartTest` passing also validates the rebase's Serializable
  resolution).
- **E2E `--clean-start`: 20/20 PASS / 0 fail** (`dev/reports/20260615143511-e2e-test.md`). The scenarios that
  exercise the moved code in a live environment — S09 delegated-mode, S11 heartbeat-resilience, S13
  stale-admin-release, S16 remote-resource-properties, S17 remote-unknown-rejected — are all green.

## Rebase onto upstream master (2026-06-15)

To prepare the PR, the latest upstream (`jenkinsci/lockable-resources-plugin`) master was pulled in.
- master updated to `upstream/master` (`87c4a7e`: #1050 row count / #1049 deprecated-API replacement / #1053
  allow empty reserve reason).
- **The pre-rebase m1g `feature/1025-remote-lr-p1-m1g` (`57d2e6d`, old-master base) is kept as-is.**
- `feature/1025-remote-lr-p1-m1g-rebased` was rebased onto the current master (squash `de54e90`→`10d3d48`,
  M1G `57d2e6d`→`4b40a42`).
- **Only `LockStepExecution.java` conflicted, in two places** (everything else auto-merged):
  1. import block (replaying the squash) — kept `Serializable`/`StandardCharsets`/`Base64`.
  2. class declaration (replaying M1G) — master #1049 had **removed the redundant `implements Serializable`**,
     so it was reconciled to `implements RemoteLockSession.Host` only, dropping the now-unused
     `import java.io.Serializable;`. Step persistence is retained via inheritance from `StepExecution`
     (`remoteSession` is still serialized). No behaviour change.

## PR branch finalization (squash + comment cleanup, 2026-06-15)

After the PR review, the submission branch was fixed to `feature/1025-remote-lr-p1-m1` and tidied.
- **Comment cleanup (comments only; no behaviour change):** restrict the remote-added comments to ASCII
  (em dash/arrow/multiply/ellipsis converted; upstream comments left as-is); drop milestone/decision-history
  markers (M1B..M1G, H-1, L-b/L-c/L-d, "extracted in ...", etc.) so comments describe only the current spec;
  keep the one phase-1 backlog note tagged `issue #1025 phase 1` (`heartbeatIntervalSeconds` accepted but
  ignored, in `RemoteApiV1Action`).
- **Squash:** `10d3d48` (squash M1A–M1F) + `4b40a42` (M1G) + `808da92` (comment cleanup) collapsed into a
  single commit **`4f3577f` "Remote Lockable Resources (issue #1025 phase 1)"** on master `87c4a7e`. Full
  feature diff: 47 files / +5594 -44.
- `4b40a42` (`-m1g-rebased`) and `57d2e6d` (`-m1g`) are kept as references (reversible).

## Commits

- plugin: **PR branch `feature/1025-remote-lr-p1-m1` = `4f3577f`** (single commit). No push (force-push at
  submission time).
- notes committed in this step (DESIGN/STEPS/RESULT j+e, README Status/branches, reports trimmed to one each).

## Open items / next

- M1G is packaging only. **M1E-1 (promotion-path ephemeral re-creation) remains an intentionally deferred
  known item** (design P1_M1F §4).
- Client UI / read-only mirror (Phase 2) is a separate cycle.
- First-PR strategy (splitting off the no-op core seams, securing #1025 consensus) is tracked separately (see
  [[remote-lock-project-state]]).
