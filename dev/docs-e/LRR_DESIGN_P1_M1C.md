# Remote Lockable Resources Specification (Phase 1 / M1C)

> **Source:** [jenkinsci/lockable-resources-plugin #1025](https://github.com/jenkinsci/lockable-resources-plugin/issues/1025)
> **Prerequisite:** `LRR_DESIGN_P1_M1B.md` (the M1B spec). This document defines the delta from M1B plus the current truth.
> **Background:** `LRR_REVIEW_P1_M1B.md` (the 2026-06-12 review at M1B completion) and the findings it surfaced
> **Scope:** Phase 1 M1C (resolving the remaining M1B inconsistencies)

---

## Table of Contents

1. [Where M1C fits](#1-where-m1c-fits)
2. [Decision record](#2-decision-record)
3. [Unified selector resolver (core)](#3-unified-selector-resolver-core)
4. [Serializing release (orphan-lock elimination)](#4-serializing-release-orphan-lock-elimination)
5. [Accepting extra-only requests](#5-accepting-extra-only-requests)
6. [Resetting the poll budget on onResume](#6-resetting-the-poll-budget-on-onresume)
7. [Scope (included / excluded)](#7-scope-included--excluded)

---

## 1. Where M1C fits

A full review after M1B completion (`LRR_REVIEW_P1_M1B.md`) found that M1B's own
headline goals — "fully implement extra" and "transparent equivalence" — were
broken by remaining inconsistencies. M1C resolves them with the same philosophy
as M1B — **not "fall back to safe" but "go all-in on transparent equivalence"**.

| Review finding | Severity | M1C resolution |
|---|---|---|
| C-1 label-based extra silently dropped | Critical (fail-open) | Fully implemented via a unified selector resolver (§3) |
| C-2 release() races queue promotion (orphan lock) | concurrency | terminal-mark under `syncResources` before unqueue (§4) |
| M-2 extra-only client/server asymmetry | minor | server accepts extra-only (§5) |
| M-3 `consecutivePollFailures` not reset on onResume | minor | reset to 0 on onResume (§6) |
| M-1 onResume displayTarget degradation | minor (display only) | **Deferred** (needs resource-name persistence; §7) |

---

## 2. Decision record

Confirmed after the 2026-06-12 review (`AskUserQuestion`):

| # | Topic | Decision |
|---|---|---|
| C-1 | label extra | **(a) implement it fully** (not 400-reject). M1B design §4 already declares it "supported", and it is consistent with transparent equivalence |
| C-2 | release race | put `release()` under `syncResources` and terminal-mark a QUEUED record (`errorCode: RELEASED`) before unqueueing; apply the same serialization the QUEUE_EXPIRED path (M1B §6) already uses |
| minor | bundling | **bundle M-2 and M-3**; defer M-1 (display-only, no functional impact) |

---

## 3. Unified selector resolver (core)

### The M1B problem shape

M1B's acquire logic was written **twice** — for the immediate acquire
(`RemoteLockManager.tryAcquireRecord`) and for the queue-promotion availability
check (`LockableResourcesManager.checkRemoteResourcesAvailable`) — and both
collected extra entries using only `e.getResource()`. As a result, **label-based
extra entries were silently dropped on both paths**, locking only the main
resource while the body ran (fail-open). Additionally, the empty-`exposeLabel`
interpretation diverged: the immediate path treated it as "nothing exposed →
UNKNOWN_LABEL" while the queue path treated it as "no filtering → allow all".

### The M1C shape: one selector model

Reframe the acquisition target as a **set of selectors**, each being either:

- **named** — one resource by `resource` name
- **label** — N resources by `label` + `quantity` from the exposed pool

Both the main target (`resource` or `label`) and every `extra` entry are one
selector. These are concentrated into two `LockableResourcesManager` methods so
that the immediate-acquire and queue-promotion paths **go through identical
logic** (single source of truth).

```text
validateRemoteSelectors(req) -> errorCode | null      // structural validity (existence / exposed)
    named : fromName(name) != null  (exposure enforced at the POST boundary)
    label : at least one candidate carrying both label and exposeLabel
            (empty exposeLabel is opt-in = nothing exposed)
    → on failure UNKNOWN_RESOURCE / UNKNOWN_LABEL (terminal FAILED)

resolveRemoteAvailable(req) -> List<String> | null    // availability right now
    assign each selector to "free AND unclaimed AND (exposed, if label)" resources
    a label selector greedily takes `quantity` (SEQUENTIAL)
    claimedSet prevents **double-counting across selectors**
        (main label x1 + extra label x1 → two distinct resources)
    all selectors satisfied → return all names (atomic). any shortfall → null (QUEUED/SKIPPED)
```

- Immediate acquire: `validateRemoteSelectors` (terminal decision) →
  `resolveRemoteAvailable` (non-null → `lockForRemote` all at once + ACQUIRED;
  null → QUEUED or SKIPPED).
- Queue promotion: `getNextRemoteEntry` applies `resolveRemoteAvailable` to each
  QUEUED entry and promotes the first satisfiable one (priority-descending).

### Equivalence / atomicity

- **label-extra is locked equivalently to local `lock()`** (the implementation
  finally matches M1B §4 as written).
- main + all extra are ACQUIRED **only when all can be acquired together** (no
  partial lock).
- the empty-`exposeLabel` label interpretation is **unified across the immediate
  and queue paths** (both: "nothing exposed = UNKNOWN_LABEL").
- with `quantity` and de-duplication, multiple selectors requesting the same
  label are assigned **distinct resources**.

---

## 4. Serializing release (orphan-lock elimination)

### The M1B race (C-2)

`RemoteLockManager.release()` read state **without holding the lock** after
`records.remove()`. A release of a QUEUED record interleaving with another
thread's promotion (`proceedRemoteEntry`, under `syncResources`, checking
`entry.isValid() == QUEUED`) produced an orphan lock — the resource stayed
remotely locked while the record was gone from the map (unrecoverable until
restart). Same shape as M1A 4-5 (release/tick race).

### The M1C fix

Wrap all of `release()` in `synchronized (LockableResourcesManager.syncResources)`
and, on the QUEUED branch, **terminal-mark first (`record.markFailed("RELEASED")`)
and then `unqueueRemote`**. Once terminal, `getNextRemoteEntry`'s
`entry.isValid()` returns false and promotion is structurally excluded.

- `syncResources` is reentrant, so a nested `unlockRemoteResources` call is fine.
- However `unlockRemoteResources` / `scheduleQueueMaintenance` (which touch the
  Jenkins Queue lock) are called **outside** `syncResources` (only the names to
  free are decided under the lock; the freeing happens after releasing it).
- The QUEUE_EXPIRED path (M1B §6) already had the same re-check; release now matches it.

---

## 5. Accepting extra-only requests

A local `lock(extra: [...])` with no main resource/label is valid
(`LockStepResource.validate` exempts `hasExtra` from the no-target rule). Under
M1B the client allowed it while the server's `POST /acquire` returned
`400 MISSING_TARGET` — an asymmetry. M1C makes the **server accept extra-only**
too (any of `resource` / `label` / `extra` being non-empty suffices). The
resolver treats an absent main selector as a no-op and resolves the extra
selectors.

---

## 6. Resetting the poll budget on onResume

`consecutivePollFailures` is persisted, so a counter accumulated before a restart
carried over after onResume and could shrink the post-restart poll retry budget
(~60s). M1C **resets `consecutivePollFailures = 0`** when polling resumes on
onResume (a restart is not a poll failure).

---

## 7. Scope (included / excluded)

### Included (M1C)

| Item | Content |
|---|---|
| Full label-extra implementation | unified selector resolver (§3): immediate/queue unified, atomic, de-duplicated, exposeLabel-filtered |
| Unified empty-exposeLabel behaviour | both immediate and queue: "nothing exposed = UNKNOWN_LABEL" |
| Serialized release | terminal-mark QUEUED under `syncResources` then unqueue (§4) |
| Accept extra-only | server accepts no-main + extra (§5) |
| Poll budget reset | `consecutivePollFailures = 0` on onResume (§6) |

### Excluded (out of M1C scope)

| Item | Note |
|---|---|
| M-1 onResume displayTarget degradation | display-only, no functional impact; deferred (needs resource-name persistence) |
| Resource-property env var propagation | unsupported, as in M1B |
| Strict `resourceSelectStrategy` | greedy SEQUENTIAL, as in M1B |

---

## Revision History

- 2026-06-12: Initial version. Defines M1C (doubling down on transparent
  equivalence) to resolve C-1/C-2/M-2/M-3 from the M1B-completion review
  (`LRR_REVIEW_P1_M1B.md`). M-1 deferred.
