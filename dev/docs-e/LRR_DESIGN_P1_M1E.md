# Remote Lockable Resources Spec (Phase 1 / M1E)

> **Source:** [jenkinsci/lockable-resources-plugin #1025](https://github.com/jenkinsci/lockable-resources-plugin/issues/1025)
> **Prerequisite docs:** `LRR_DESIGN_P1_M1D.md` (M1D = true bridging) / `LRR_RESULT_P1_M1D.md` (M1D result) / `LRR_REVIEW_P1_M1D.md` (M1D review)
> **Scope:** Phase 1 M1E (**M1D review fixes + intentional simplification** — unknown/unexposed rejected with an API-natural 404; the exposure filter is simplified to exposeLabel (multiple labels allowed))

---

## Table of contents

1. [Where M1E sits](#1-where-m1e-sits)
2. [Design decision: redraw the transparent-equivalence boundary](#2-design-decision-redraw-the-transparent-equivalence-boundary)
3. [H-1 fix: stop ephemeral proliferation + 404 admission](#3-h-1-fix-stop-ephemeral-proliferation--404-admission)
4. [M-2 fix: simplify to an exposeLabel (multi-label) filter](#4-m-2-fix-simplify-to-an-exposelabel-multi-label-filter)
5. [Minor (L-3 / L-4 / L-5)](#5-minor-l-3--l-4--l-5)
6. [True non-equivalence + intentional non-equivalence (anti-re-litigation)](#6-true-non-equivalence--intentional-non-equivalence)
7. [Remove / change / keep](#7-remove--change--keep)
8. [Scope](#8-scope)

---

## 1. Where M1E sits

M1D (true bridging) succeeded on its **main line**: the server stops re-implementing lock() semantics and delegates to the canonical path. But the completion review (`LRR_REVIEW_P1_M1D.md`) raised two items:

- **H-1 [new regression]**: removing the POST-boundary existence/exposure checks (to make "unknown → QUEUED") let a RemoteUse client **proliferate persistent ephemerals just by requesting non-existent names** (`createResource` runs before the exposure filter; the created resource is neither exposed, locked, nor reclaimed).
- **M-2 [over-engineering]**: generalising exposure into a `RemoteResourceExposurePolicy` (`ExtensionPoint`) was, with AND + always-on default, unable to "replace" and **excessive** for the small-scale target.

M1E reaffirms the **target user = small-scale CI/CD** and resolves both with two design shifts:

1. **Reject unknown/unexposed up front with an API-natural 404** (`UNKNOWN_RESOURCE` / `UNKNOWN_LABEL`, uniform 404 status).
   → This **intentionally reverts** M1D's "unknown → QUEUED (transparent like local)" (rationale in §2/§6).
2. **Commit to a single exposeLabel filter.** Remove the `ExtensionPoint` SPI; reduce the concept to one.

> **Important:** M1E is not a feature cycle but a "redraw the boundary and simplify" cycle. Canonical delegation (M1D's win) is kept; M1C's re-implementation (`claimSelector` etc.) is **not** brought back. Effectively "M1C's admission check (404) + M1D's canonical resolution".

## 2. Design decision: redraw the transparent-equivalence boundary

M1D held that "transparent equivalence need only hold **inside the visible surface**" (M1D §2). M1E takes this one step further and makes explicit that **"a resource this client cannot lock (unknown / unexposed)" is outside the scope of transparent equivalence**:

- "unknown / unexposed" is **a concept local lock() does not have** (local has no exposure filter). So "what would local do" is not a meaningful baseline, and it should be treated as a **remote-specific admission** question, API-style.
- Mirroring local's "unknown resources QUEUE (resources may appear later)" onto remote produces the **H-1 ephemeral proliferation** and **indefinite QUEUED + poll occupancy**. For a small-scale environment this adds only cost.
- As an API, "no lockable target" is naturally a 404 (REST convention). A uniform 404 also provides **existence hiding (enumeration prevention)**.

By contrast, "**exposed but currently busy**" is different — that **is** in scope for transparent equivalence → QUEUED (waiting for a peer to release). This is the essential value of remote locking and is kept. The boundary:

| Input (acquire request) | M1D behaviour | **M1E behaviour** |
|---|---|---|
| non-existent resource name | ephemeral created→hidden→QUEUED (H-1) | **404 `UNKNOWN_RESOURCE`** (nothing created) |
| existing but unexposed resource name | hidden→QUEUED | **404 `UNKNOWN_RESOURCE`** (uniform 404, existence hidden) |
| label with no exposed candidate | hidden→QUEUED | **404 `UNKNOWN_LABEL`** |
| exposed, currently busy | QUEUED | **QUEUED (202)** ← kept (peer-release wait) |
| exposed, free | ACQUIRED | ACQUIRED ← kept |

> Status is **uniformly 404** (non-existent vs unexposed not distinguished = hidden). The errorCode (`UNKNOWN_RESOURCE` / `UNKNOWN_LABEL`) is retained to distinguish the selector kind the client itself sent (no new information leak).

## 3. H-1 fix: stop ephemeral proliferation + 404 admission

### 3-1. Remove `createResource` from the remote resolution path

Delete the `createResource(resource)` call in `addRemoteStruct` (`LockableResourcesManager`). A remote request then **never materialises a new ephemeral on the server**. Only validated (= existing) names enter `LockableResourcesStruct`'s `fromName` resolution, and the canonical `fromNames(create=true)` is a no-op for existing names, so **no creation is triggered**.

### 3-2. Add an exposeLabel-based admission check inside `enqueue`

At the **top** of `enqueue`'s `synchronized (syncResources)` block, validate the main + each extra selector:

```text
errorCode = validateRemoteSelectors(req):   // exposeLabel-set based, no ExtensionPoint
  resource selector → does fromName(resource) exist and carry any exposeLabel?
                       if not → "UNKNOWN_RESOURCE"
  label selector    → is there ≥1 candidate carrying the label AND any exposeLabel?
                       if not → "UNKNOWN_LABEL"
  absent selector   → null (e.g. main when extra-only; nothing to validate)
errorCode != null → record.markFailed(errorCode); return   // terminal; does not reach toRemoteStructs
```

`validateRemoteSelectors` (and helpers `validateSelector` / `hasExposedCandidate`) **revive M1C's implementation on an exposeLabel basis** (removed by M1D; here it reads exposeLabel directly rather than via an `ExtensionPoint`). Called under `syncResources`, so reads of `resources` / exposeLabel are consistent.

### 3-3. Map to 404 (POST handler)

In M1D, POST `/acquire` always returns 202 after enqueue. Add one branch:

```text
record = enqueue(...)
if record.state == FAILED && errorCode ∈ { UNKNOWN_RESOURCE, UNKNOWN_LABEL }:
    sendJsonError(rsp, 404, errorCode, message)    // uniform 404
else:
    202 (return lockId + state as before)          // ACQUIRED / QUEUED / SKIPPED
```

Validation runs inside `enqueue` (single source, correctly locked); the handler only maps the HTTP status. (No separate `fromName` check at the boundary à la M1C → no duplicated validation logic.)

### 3-4. Resolution stays canonical (invariant)

ACQUIRED / QUEUED decisions still delegate to `toRemoteStructs` → `availableForRemote` (`getAvailableResources(..., candidateFilter)`), exactly as M1D. **`claimSelector` / `resolveRemoteAvailable` are not revived.** An admitted request is guaranteed "existing & exposed", so it cleanly falls to QUEUED if busy and ACQUIRED if free. If an admin deletes/unexposes the target while QUEUED, the promotion-time candidateFilter keeps rejecting it and it eventually degrades to `QUEUE_EXPIRED` (existing behaviour; the 404 at acquire is the main path, this is a rare fallback).

## 4. M-2 fix: simplify to an exposeLabel (multi-label) filter

### 4-1. Remove the ExtensionPoint, commit to exposeLabel

- **Delete `RemoteResourceExposurePolicy.java` and `ExposeLabelPolicy.java`** (remove the `ExtensionPoint` SPI). The AND folding, always-on default, and the dead "all exposed when no policy" branch all go away.
- Exposure is decided by a **single exposeLabel filter**. allowlist / authz / exposure restriction are **P1+ candidates**, unneeded for the small-scale target now; revive an SPI later **when actually needed** (YAGNI).

### 4-2. exposeLabel allows multiple labels (OR exposure)

Pinning exposeLabel to one label is too rigid (the AND with the requested label always assumes "exactly that label"). So **interpret exposeLabel as a whitespace-separated set of labels** (same convention as `LockableResource.labels` = `split("\\s+")`). `getExposeLabel()` (String) is unchanged; add `getExposeLabels()` that returns the set:

- A resource R is exposed iff **R's label set ∩ exposeLabel set ≠ ∅** (carries any one = **OR**).
- Empty = exposes nothing (opt-in, unchanged).
- Both workflows are expressible:
  - **Expose existing labels:** `exposeLabel = "gpu license"` (exposed if it carries gpu or license).
  - **Add a marker label:** `exposeLabel = "remote-ok"` (tag the resources you want exposed).
- **Backward compatible:** a single value (e.g. `"remote-ok"`) is a one-element set. The config UI stays a textbox (only the help text changes). exposeLabel is visible to the client at lock time (labels are not secret), so exposing existing labels leaks no new information.

### 4-3. "requested-label AND exposeLabel(set)" is absorbed without touching local (confirmed concern)

Local lock()'s label matching is **single-label**. Remote's "requested label X AND (any exposeLabel)" must hold, but **no multi-label AND/OR is embedded into local's matching logic**. Split into two stages:

```text
① label match  = the existing single-label match (getResourcesWithLabel("X"), untouched)
② visibility filter = a generic Predicate the remote layer builds, applied before count selection
     candidates.removeIf(r -> !visible.test(r))
   visible = r -> !Collections.disjoint(r.getLabelsAsList(), exposeLabels)   // empty exposeLabels → r -> false
```

- ① matching logic is **untouched** (still single-label; no "two-label AND" change).
- The canonical methods (`getAvailableResources` / `getFreeResourcesWithLabel`) only hold a **generic `Predicate<LockableResource>` parameter** and know nothing about exposeLabel. Local callers pass `r -> true`, so **behaviour is entirely unchanged** (375 green pass through unmodified).
- exposeLabel (set / OR) knowledge lives **100% in the remote layer** (`availableForRemote`'s predicate construction) and never enters local's semantics.
- The filter runs **before** count selection, so `amount<=0` ("all") correctly means "all *visible* matching". A post-filter approach (breaks count semantics) and a remote re-implementation (revives M1D-removed `claimSelector` = drift) are both unviable. **The generic seam is the only realistic answer.**

> **Confirmed (2026-06-13, with the user):** exposure is the single concept of an exposeLabel set (OR). The canonical path has only a generic Predicate seam (local untouched, behaviour unchanged). The exposeLabel AND/OR logic is confined to the remote layer. **This split is not to be re-litigated.**

## 5. Minor (L-3 / L-4 / L-5)

- **L-3 (unify env-var generation):** Stop `RemoteQueueEntry.onAcquired` from building the `name→properties` map inline and calling `buildLockEnvVars`; route it through the same `LockableResourcesManager.remoteLockEnvVars(variable, resources)` the immediate path uses.
- **L-4 (invalid resourceSelectStrategy):** Reject an unrecognised strategy at the POST boundary with **400 `INVALID_SELECT_STRATEGY`** (in line with the other 400 validations and local's "reject invalid"). `parseSelectStrategy`'s lenient fallback remains as a safety net.
- **L-5 (tests):** reflected in §6's test plan (unknown name → 404 **and no resource created**, unexposed → 404, exposeLabel filter directly, selectStrategy, property env vars on the QUEUED→promotion path).

## 6. True non-equivalence + intentional non-equivalence

**True non-equivalence** that remains even for a pure bridge (M1B §1 / M1D §7, kept by design):

- time delay (round-trip latency) / fail-close on network failure / restart transient.

**Intentional non-equivalence** newly introduced by M1E (differs from local but settled as a design decision; **do not re-open "make it local-equivalent" later**):

- **unknown/unexposed resource → immediate 404** (local QUEUEs and waits). Rationale: ① a remote-specific admission concept where the local baseline is meaningless, ② in a small-scale environment only the cost of QUEUED occupancy / ephemeral proliferation (H-1) accrues, ③ 404 is API-natural and hides existence.
  → This **intentionally replaces** M1D's "unknown → QUEUED", per the user-confirmed H-1 direction (a) in `LRR_REVIEW_P1_M1D.md` (2026-06-13).

"exposed but busy → QUEUED" stays **transparent equivalence** (the essence of remote locking, kept).

## 7. Remove / change / keep

| Category | Items |
|---|---|
| **Remove** | `RemoteResourceExposurePolicy.java` / `ExposeLabelPolicy.java` (SPI); the `createResource` call in `addRemoteStruct` |
| **Add** | `getExposeLabels()` (split `exposeLabel` by `\s+` into a set); `getExposeLabel()` unchanged / backward compatible |
| **Revive (exposeLabel-set based)** | `validateRemoteSelectors` / `validateSelector` / `hasExposedCandidate` (admission only — not re-implementing resolution) |
| **Change** | `availableForRemote` builds the exposeLabel-set OR predicate directly instead of `RemoteResourceExposurePolicy.visibilityFor` / POST maps FAILED+`UNKNOWN_*` to 404 / POST rejects invalid strategy with 400 / `RemoteQueueEntry.onAcquired` → `remoteLockEnvVars` / config UI help + `config.properties` title |
| **Keep (M1D's win)** | canonical delegation (`toRemoteStructs` / `availableForRemote` / the `getAvailableResources(..., Predicate)` seam) / shared `buildLockEnvVars` / transport, resilience, STALE, QUEUE_EXPIRED, Force Release |

## 8. Scope

### In scope (M1E)

| Item | Content |
|---|---|
| H-1 fix | drop `createResource` + exposeLabel-set admission (unknown/unexposed → uniform 404). Stops ephemeral proliferation |
| M-2 fix | remove the `ExtensionPoint` SPI; simplify to an exposeLabel filter (the `Predicate` seam is kept) |
| exposeLabel multi-label | interpret `exposeLabel` as a whitespace-separated set (OR exposure). Backward compatible, UI nearly unchanged |
| L-3/L-4/L-5 | unify env vars / 400 on invalid strategy / test expansion |

### Out of scope (M1E)

| Item | Note |
|---|---|
| per-client allowlist / authz / exposure restriction | P1+ candidate. Revive an SPI when needed (YAGNI) |
| M-1 onResume displayTarget degradation | display only, deferred (since M1B) |
| true non-equivalence (latency / fail-close / restart transient) | kept by design |

## Change log

- 2026-06-13: Initial version. Defines the fixes for M1D review H-1 (ephemeral proliferation) and M-2 (ExtensionPoint over-engineering). Unknown/unexposed → uniform 404 (user-confirmed); exposure simplified to exposeLabel. Canonical delegation kept; M1C's re-implementation not revived. "unknown → 404" stated as intentional non-equivalence (anti-re-litigation).
- 2026-06-13: Reflected the user's concern (would a single exposeLabel inject AND logic into local's single-label matching?). Rewrote §4: exposeLabel becomes a multi-label set (whitespace-separated, OR exposure); "requested-label AND exposeLabel(set)" is absorbed via the generic Predicate seam with **local matching untouched / behaviour unchanged** (§4-3, anti-re-litigation).
