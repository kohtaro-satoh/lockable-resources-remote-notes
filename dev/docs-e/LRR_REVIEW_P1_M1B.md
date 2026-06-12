# Remote LR Development — Full Review (as of Phase 1 / M1B)

> **Review date:** 2026-06-12
> **Plugin branch under review:** `feature/1025-remote-lockable-resources-p1-m1b` (HEAD: `02fcfae`, M1B Steps 1-8 + follow-ups F-1–F-3, 360 tests passing, E2E 16/16)
> **Documents under review:** `dev/docs-e/` (LRR_DESIGN_P1_M1B / LRR_IMPLEMENTATION_STEPS_P1_M1B / E2E_TEST_SPECIFICATION), `LRR_REVIEW_P1_M1A.md`
> **Perspective:** original vision ([#1025](https://github.com/jenkinsci/lockable-resources-plugin/issues/1025)), resolution status of the M1A review findings, and the soundness of the new M1B implementation
> **Caveat:** The full build (~17 min) was not re-run; the code was reviewed statically. Test counts (360) and E2E (16/16) are trusted from the recorded reports — but, as noted below, that test layer has a blind spot.

---

## Resolution Status in M1C (placeholder for later)

M1C (the M1B problem-solving cycle) is executed in response to this review.
The status of each finding will be filled in here when M1C completes.

| Finding | Status in M1C |
|---|---|
| C-1 label-based extra silently dropped | (not started) |
| C-2 release() races queue promotion (orphan lock) | (not started) |
| M-1 onResume QUEUED resume degrades displayTarget | (not started) |
| M-2 extra-only request client/server asymmetry | (not started) |
| M-3 consecutivePollFailures not reset on onResume | (not started) |

---

## Table of Contents

1. [Overall Assessment](#1-overall-assessment)
2. [What M1B Improved](#2-what-m1b-improved)
3. [Critical Issues (must fix before push/PR)](#3-critical-issues-must-fix-before-pushpr)
4. [Minor / Observations](#4-minor--observations)
5. [Test / Verification Layer](#5-test--verification-layer)
6. [Recommended Actions (in priority order)](#6-recommended-actions-in-priority-order)

---

## 1. Overall Assessment

The 16 M1A review findings have been carefully resolved in both code and docs.
The rework into the unified queue bridge (design option E) is sound in
particular: `proceedNextContext()` dispatches local and remote waiters by a
single priority comparison, a remote release immediately wakes local waiters
(structural resolution of M1A 4-3), and the QUEUE_EXPIRED path re-checks state
under `syncResources` (resolution of M1A 4-5). The documentation system and
process tracking remain high quality.

That said, **"all M1A review findings are closed" is premature.** M1B's own
headline goals — "fully implement `extra`" and "transparent equivalence" — are
broken **for label-based extra entries** (C-1). This is the same class of
fail-open bug as M1A's top Critical (3-1, silent partial lock), and it
contradicts `LRR_DESIGN_P1_M1B.md` §4. In addition, the client-initiated
release path still carries a concurrency hole of the same shape as M1A 4-5
(C-2).

The root problem the M1A review named — "*what to build* is high quality, but
*the verification layer that checks whether what was built matches what was
declared* has holes" — recurs in M1B in the same form. C-1 slipped through
because there are zero tests for label-based extra.

---

## 2. What M1B Improved

- **The unified queue bridge (option E) works as designed.** `proceedNextContext()`
  dispatches local/remote by priority comparison, and a remote release
  immediately wakes local waiters (structural resolution of M1A 4-3).
- **QUEUE_EXPIRED race avoidance is correct.** `maybeScanStale()` re-checks
  `record.getState() == QUEUED` under `synchronized (syncResources)` before
  `markFailed` + `unqueueRemote` (`RemoteLockManager.java`). On this path the
  "promotion vs. expiry at the same time" race of M1A 4-5 is correctly
  eliminated. **— But the same guard is absent on the client release path (C-2).**
- **lockEnvVars comma-join unification** (M1A 3-2), **onResume QUEUED resume /
  ACQUIRED cleanup** (3-4), and **Force Release UI + dedicated RemoteUse
  permission** (3-5 / 5-1) are all consistent across code and docs.
- **Poll retry budget + heartbeat warn-and-continue** (4-1) is implemented per
  decisions B/C and verified by E2E S11.

---

## 3. Critical Issues (must fix before push/PR)

### 🔴 C-1. Label-based `extra` entries are silently dropped server-side [Critical / exclusivity violation]

`lock(resource: 'board-1', extra: [[label: 'gpu', quantity: 2]], serverId: 'b')`
**locks only `board-1`, returns ACQUIRED, and runs the body while no `gpu`
resource is locked at all.**

Path:

- The client sends label-based extra correctly — `remote/RemoteApiClient.java:115`
  writes `r.getLabel()` into the JSON.
- The server's POST handler accepts label-based extra (does not 400) —
  `actions/RemoteApiV1Action.java:144-164`.
- But the acquisition logic only collects **`e.getResource()`** and ignores
  label entries:
  - Immediate acquire: `remote/RemoteLockManager.java:227-231` — only resources
    are added to `allNames`.
  - Queue-promotion availability check: `LockableResourcesManager.java:1199-1205`
    (`checkRemoteResourcesAvailable`) — same, resources only.

**Why it matters:**

- This is the worst-case silent partial lock, directly hitting the original
  vision's UC-1 (avoid destroying HW boards) and UC-2 (licenses) — the exact
  accident M1A 3-1 identified as the feature's core safety requirement.
- `LRR_DESIGN_P1_M1B.md` §4 **explicitly lists** `{ "label": "probe", "quantity": 1 }`
  as a supported example and even specifies "a label entry with zero matching
  exposed candidates → 404 UNKNOWN_LABEL". The implementation has no such code
  path → **spec ⇔ implementation drift.**
- local `lock()` does correctly lock label-based extra, so this **violates
  transparent equivalence head-on** (the premise of `LRR_DESIGN_P1_M1B.md` §1).

**Test blind spot:** `extra` tests in `RemoteLockManagerTest`
(`extraResourcesAreLockedAtomically` / `extraResourceNotAcquiredWhenOneIsBusy`)
and `RemoteApiV1ActionTest` are **all resource-based only**. Zero tests for
label-based extra. The "verification layer hole" of M1A review §6 #5 recurs.

**Fix options (two; decide before M1C starts):**

- **(a) Implement it (all-in on transparent equivalence):** extend `tryAcquireAll`
  and the queue check (`checkRemoteResourcesAvailable`) to handle label-based
  extra — apply the same exposeLabel filter and quantity as main label, and
  acquire main + all extra atomically. Matches `LRR_DESIGN_P1_M1B.md` §4 as
  written; no doc change needed.
- **(b) Declare unsupported in M1B (seal the accident first):** reject
  `extra[i].label != null` with **400** in POST, and amend §4 / §10 to "extra
  supports resource entries only". Consistent with M1A's "seal the accident
  path before implementing" stance.

Either is acceptable, but **silently dropping is not.** Add label-based extra
unit/E2E tests either way.

### 🟠 C-2. `release()` reads state outside `syncResources` → races queue promotion → orphan lock [concurrency]

`remote/RemoteLockManager.java:176-195` `release()` reads
`state = record.getState()` **without holding the lock** after `records.remove()`.

A release of a QUEUED record (client cancellation, onResume best-effort release)
interleaving with `proceedRemoteEntry` (`LockableResourcesManager.java:1031-1048`,
under `syncResources`) on another thread produces an orphan lock:

1. release: `records.remove(lockId)` → obtains record, reads `state == QUEUED`
2. other thread: a resource frees up; `proceedRemoteEntry` sees `entry.isValid()`
   (== QUEUED, still true), sets `remoteLockedBy = lockId` via `lockForRemote`,
   calls `markAcquired`
3. release: the `state == QUEUED` branch calls `unqueueRemote(lockId)` → no-op
   (already removed)

Result: **the resource stays remotely locked by `lockId` while the record is
gone from the `records` map.** `heartbeat` / `release` / `maybeScanStale` (which
iterates `records.values()`) can never reach this lockId; it never even goes
STALE, and is **unrecoverable until a Jenkins restart.**

This is the same shape as M1A 4-5 (release/tick race). The QUEUE_EXPIRED path
(`RemoteLockManager.java:354-362`) correctly re-checks under `syncResources`,
but **the client-initiated release path lacks the same guard.**

**Fix:** wrap all of `release()` in `synchronized (syncResources)`, and on the
QUEUED branch mark the record terminal (`record.markFailed(...)`) *before*
`unqueueRemote`. Once terminal, `getNextRemoteEntry`'s `entry.isValid()` returns
false and promotion is excluded (`syncResources` is reentrant, so the nested
lock inside `unlockRemoteResources` is fine).

---

## 4. Minor / Observations

| # | Description | Severity | Location |
|---|---|---|---|
| M-1 | onResume QUEUED resume sets `displayTarget = remoteLockId`. The resource name is not persisted, so post-restart logs degrade to the lockId (no functional impact, display only) | low | `LockStepExecution.java:769` |
| M-2 | extra-only request asymmetry: client `resolveRemoteDisplayTarget` allows extra-only, but server POST requires a main resource/label and returns 400 (MISSING_TARGET). Align or document | low | `LockStepExecution.java:420` / `RemoteApiV1Action.java:102` |
| M-3 | `consecutivePollFailures` is not reset on `onResume`. The pre-restart counter is persisted and carried over, shrinking the budget after a long QUEUED period followed by a restart | low | `LockStepExecution.java:64, 762-773` |

---

## 5. Test / Verification Layer

- **Counts are adequate (360 unit + 16 E2E), but negative/equivalence paths have
  gaps.** C-1 slipped through because there are zero tests for label-based extra
  — the same structural weakness as M1A review §6 #5.
- **Missing tests to add in M1C:**
  - **Unit (plugin side):** label-based extra immediate acquire / QUEUED
    promotion / exposeLabel filter / atomicity (one busy → whole request QUEUED).
    Regression test for the C-2 release-vs-promotion race (verifying terminal
    marking excludes promotion).
  - **E2E (notes side):** label-based extra atomic-acquire scenario (extend S10
    or add new). If feasible, a release-while-QUEUED orphan-lock non-occurrence
    check.
- Add matching test items (tagged P1M1C) to `E2E_TEST_SPECIFICATION.md`.

---

## 6. Recommended Actions (in priority order)

1. **Seal C-1** (implement (a) or 400-reject (b); decide before M1C starts) plus
   label-based extra unit/E2E tests. Until this is done, do not claim "extra
   fully implemented" or "all findings closed".
2. **C-2: put `release()` under `syncResources` and mark QUEUED terminal** before
   unqueue. Add a regression test.
3. Correct the "all findings closed" notes in memory/notes and register C-1 / C-2
   as M1C items.
4. Minor M-1–M-3 are optional (decide whether to bundle into M1C or defer).

---

## Change Log

- 2026-06-12: Initial version. Full review as of M1B completion (plugin
  `02fcfae`). Detected C-1 (label-based extra silently dropped) and C-2
  (release vs. queue-promotion race) as Critical / concurrency findings.
