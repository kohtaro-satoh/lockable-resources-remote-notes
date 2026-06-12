# M1C Implementation Steps (Remote lock - Phase 1 / M1C)

This file is the M1C progress tracker. It resolves the new problems found by the
M1B-completion review (`LRR_REVIEW_P1_M1B.md`) by doubling down on transparent
equivalence (design: `LRR_DESIGN_P1_M1C.md`).

---

## Background: problems found in the M1B review

| Finding | Severity | Description |
|---|---|---|
| C-1 | Critical (fail-open) | label-based extra silently dropped server-side (only the main resource locked while the body runs). Same shape as M1A 3-1; contradicts design §4 |
| C-2 | concurrency | `release()` reads state outside `syncResources` → races queue promotion → orphan lock. Same shape as M1A 4-5 |
| M-2 | minor | extra-only request client/server asymmetry (client allows, server 400s) |
| M-3 | minor | `consecutivePollFailures` not reset on onResume |
| M-1 | minor (display only) | onResume QUEUED resume degrades displayTarget to the lockId → **deferred** |

### Decisions (2026-06-12, AskUserQuestion)

- **C-1: implement it fully (a)** (not 400-reject).
- minor: **bundle M-2 and M-3**, defer M-1.

---

## Architecture change overview (heart of Step 1)

### M1B shape (buggy)

```
immediate  : RemoteLockManager.tryAcquireRecord     ┐ collect extra by e.getResource() only
promotion  : LRM.checkRemoteResourcesAvailable       ┘ → label-extra silently dropped on both paths
                                                         empty-exposeLabel label interpretation also diverged
```

### M1C shape (unified selector resolver)

```
New in LockableResourcesManager (single source of truth):
  validateRemoteSelectors(req) -> errorCode | null   // structural validity (existence / exposed)
  resolveRemoteAvailable(req)  -> List<String> | null // availability (claimedSet de-dups, atomic)

immediate  : RemoteLockManager.tryAcquireRecord  → validate → resolve → lockForRemote / QUEUED / SKIPPED
promotion  : LRM.getNextRemoteEntry              → resolveRemoteAvailable (same method)
```

- the main target (resource/label) and each extra are resolved uniformly as "selectors".
- a label selector applies the exposeLabel filter + quantity; `claimedSet` de-dups across selectors.
- ACQUIRED only when main + all extra can be acquired together (no partial lock).

---

## Step list

### 0. Preliminaries (done)

- [x] M1B fully complete (plugin `02fcfae`, 360 tests)
- [x] m1c branch created (based on m1b)
- [x] `LRR_REVIEW_P1_M1B.md` (j+e) authored (notes `7f5d220`)

### Step 1: C-1 / C-2 — unified selector resolver + release serialization

**Implementation:**
- `LockableResourcesManager`: added `validateRemoteSelectors` / `validateSelector` /
  `hasExposedCandidate` / `resolveRemoteAvailable` / `claimSelector`. Removed
  `checkRemoteResourcesAvailable` and switched `getNextRemoteEntry` to
  `resolveRemoteAvailable`.
- `RemoteLockManager.tryAcquireRecord`: rewritten to delegate to the resolver
  (removed `tryAcquireAll` / `tryAcquireByLabel` / `isExposedResource`).
- `RemoteLockManager.release`: decide state under `syncResources`; for QUEUED,
  `markFailed("RELEASED")` then `unqueueRemote`. The freeing
  (`unlockRemoteResources` / `scheduleQueueMaintenance`) runs outside the lock.

**Tests (RemoteLockManagerTest +8):** label-extra atomic acquire / QUEUED when
busy (no partial lock) / main label + extra label de-dup / QUEUED on shortfall /
extra-label UNKNOWN_LABEL / queue promotion / extra-only /
`releasingQueuedRecordPreventsLaterPromotion` (C-2 regression).

#### Done criteria

- [x] Implemented
- [x] `mvn test` green (**370 / 0 failures**, `dev/reports/20260612192153-mvn-test.log`)
- [x] Committed (`3f1e78a`)

Note: completed 2026-06-12. Immediate/queue unified; empty-exposeLabel divergence also fixed.

### Step 2: M-2 / M-3 — accept extra-only + reset poll budget

**Implementation:**
- `RemoteApiV1Action` (POST /acquire): accept no-main when extra is non-empty
  (`MISSING_TARGET` only when `resource && label && !hasExtra`; message updated to
  `..., extra`).
- `LockStepExecution.onResume`: reset `consecutivePollFailures = 0` when resuming polling.

**Tests (RemoteApiV1ActionTest +2):** HTTP-layer label-extra acquire (also proves
C-1 through the API) / extra-only acquire (202).

#### Done criteria

- [x] Implemented
- [x] `mvn test` green (included in the 370, same log)
- [x] Committed (`5296b50`)

Note: completed 2026-06-12. extra-only is local-lock()-equivalent.

### Step 3: E2E S14 + full regression

**Implementation:**
- Added `dev/jenkins-env/scenarios/extra-label-resources.sh` (S14, P1M1C). CP02
  directly verifies a resource + a label-based extra are locked under a **single
  lease** (the heart of C-1).
- Registered S14 / `m1c-series` in `run-e2e.sh`; documented S14/P1M1C in the E2E
  spec (j+e).

#### Done criteria

- [x] scenario + registration + spec (j+e) (notes `109771f`)
- [x] **`run-e2e.sh --clean-start` all 17 PASS** (`dev/reports/20260612201703-e2e-test.md`, 2026-06-12)
- [x] saved the report under `dev/reports/` and recorded the result

Note: completed 2026-06-12. **All 17 scenarios 17/17 PASS (pass=17 fail=0 skip=0)**.
S14 CP02 proved that main(R1) and the label-extra(GPU) are locked under the **same
lease** (`8d4068ae…`) during the body and both released afterwards (the heart of
C-1). All pre-existing scenarios (S10–S13, D01–D03 included) also passed (no regressions).

---

## Test policy (M1C)

1. Full regression via `stabilize-build.sh` (worktree mode), `mvn test` whole
   suite (avoids the VS Code jdt.ls conflict).
2. E2E via the latest `run-e2e.sh` **whole suite** (not just a single series),
   `--clean-start`, saving the report (a cycle done-criterion).

---

## Revision History

- 2026-06-12: Initial version. Implementation steps and step records for M1C
  (resolving C-1/C-2/M-2/M-3).
