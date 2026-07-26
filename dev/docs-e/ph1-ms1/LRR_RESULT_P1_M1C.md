# M1C Result (Remote lock - Phase 1 / M1C)

> **Plugin branch:** `feature/1025-remote-lockable-resources-p1-m1c` (HEAD `2d88834`)
> **Design:** `LRR_DESIGN_P1_M1C.md` / **Steps:** `LRR_IMPLEMENTATION_STEPS_P1_M1C.md` / **Origin review:** `LRR_REVIEW_P1_M1B.md`
> **Scope:** Result summary of the cycle resolving the M1B-completion review findings (C-1/C-2/M-2/M-3) plus an extra finding (F-1).

---

## 1. Findings resolved

| Finding | Type | Resolution | plugin |
|---|---|---|---|
| **C-1** label-based extra silently dropped | Critical (fail-open exclusivity) | unified selector resolver fully implements label-extra (atomic, exposeLabel, quantity, de-dup) | `3f1e78a` |
| **C-2** `release()` races queue promotion (orphan lock) | concurrency | serialize `release()` under `syncResources`; terminal-mark QUEUED before unqueue | `3f1e78a` |
| **M-2** extra-only client/server asymmetry | minor | server accepts extra-only (local-equivalent) | `5296b50` |
| **M-3** `consecutivePollFailures` not reset on onResume | minor | reset to 0 on onResume | `5296b50` |
| **F-1** label unspecified quantity = all ("0 = all") | transparent equivalence (found during M1C) | `claimSelector` locks the whole pool; POST default 1→0 | `2d88834` |
| M-1 onResume displayTarget degradation | minor (display only) | **deferred** (needs resource-name persistence) | — |

**F-1 origin (important):** surfaced by the user's "extra unsolved across M1A/M1B/M1C" remark.
`lock(label: X)` (no quantity) locks all matching locally ("0 = all") but the remote path defaulted
to 1 since M1A. **Root cause: every test pinned an explicit `quantity: 1/2`, so the most common case
(default = all) was never exercised** (same verification-layer hole as C-1/C-2). Lesson: equivalence
tests must exercise default/unspecified/0/empty inputs.

## 2. Verification

| Aspect | Result | Evidence |
|---|---|---|
| Unit (worktree full) | **mvn test 375 / 0 failures / 1 skip** (known JENKINS-40787) | `dev/reports/20260612232116-mvn-test.log` |
| E2E (`--clean-start`, full) | **18 scenarios 18/18 PASS** | `dev/reports/20260612233944-e2e-test.md` |
| New E2E | S14 `extra-label-resources` (C-1) / S15 `label-quantity-all` (F-1) | same |
| New unit | RemoteLockManagerTest 32 / RemoteApiV1ActionTest 11 (+15 total) | — |

S14 CP02: main + label-extra locked under the **same lease** (C-1 proven).
S15 CP02: `lock(label)` with no quantity locks **all three pool resources under one lease** (F-1 proven).

## 3. The "true non-equivalences" that remain after M1C — the entry to M1D

M1C fixed things **per feature**, and the residue is also per-feature. This stems from the architecture
where **the server re-implements lock() resolution and env-var generation** (each semantic dimension can
drift independently). The non-equivalences remaining at M1C:

| Residue | Description |
|---|---|
| Resource-property env vars | local injects `VAR0_<PROP>`; remote does not |
| Ephemeral auto-creation | local creates a missing named resource; remote returns `UNKNOWN_RESOURCE` |
| resourceSelectStrategy | local SEQUENTIAL/RANDOM; remote greedy SEQUENTIAL only |

→ **M1D (true bridging)** delegates resolution to the canonical `getAvailableResources` and shares env-var
generation with local, eliminating these **without per-feature implementation** (`LRR_DESIGN_P1_M1D.md`).

## 4. Status

- plugin `feature/...-m1c` HEAD `2d88834` (clean). **Not pushed** (after final polishing; awaiting instruction).
- Docs (DESIGN/IMPLEMENTATION_STEPS, j+e) in place; review resolution table (C-1/C-2/M-2/M-3/F-1) updated.

## Change Log

- 2026-06-13: Initial version. Result summary of M1C (C-1/C-2/M-2/M-3 + F-1); hands off to M1D.
