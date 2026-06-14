# Remote LR Development Review (Phase 1 / at M1E completion — full diff vs master)

> **Review date:** 2026-06-14
> **Plugin diff under review:** the **full diff** `master` (`863ea4d`)..`feature/1025-remote-lockable-resources-p1-m1e` (HEAD: `5d956de`)
>   (43 files / +5256, -43; mvn 378 pass, E2E 20/20)
> **Documents under review:** `dev/docs-j/` (LRR_DESIGN_P1_M1E / LRR_IMPLEMENTATION_STEPS_P1_M1E / LRR_RESULT_P1_M1E / E2E_TEST_SPECIFICATION),
>   `LRR_REVIEW_P1_M1D.md` (previous-cycle review), `memo.txt` (user's open questions)
> **Lens:** original intent ([#1025](https://github.com/jenkinsci/lockable-resources-plugin/issues/1025)); how well M1E meets its core goal ("resolve the M1D-review H-1 / M-2 + deliberate simplification");
>   soundness of exposeLabel-set (OR) exposure and canonical delegation; **whether the H-1 class (ephemeral proliferation) is fully closed**; any new regressions.
> **Method:** Same methodology as M1A/M1B/M1D. The full build (~17 min) was not re-run; the `5d956de` full diff and code were read statically.
>   The test count (378) / E2E (20/20) are trusted from the recorded reports, whose existence was verified
>   (`dev/reports/20260614002216-mvn-test.log` = `Tests run: 378, Failures: 0, Errors: 0, Skipped: 1`; `dev/reports/20260614004015-e2e-test.md`; working tree clean at `5d956de`).

---

## M1F resolution (updated 2026-06-14)

These findings were triaged by the user-settled lens "**lean on lock()'s existing logic; do not add remote-specific judgement
that is not network-bridge-derived**" and the M1F cycle was run (`LRR_DESIGN_P1_M1F.md` / `LRR_IMPLEMENTATION_STEPS_P1_M1F.md`,
plugin branch `feature/1025-remote-lockable-resources-p1-m1f`, on top of m1e).

| Finding | Class | M1F action |
|---|---|---|
| **M1E-1** (promotion-path `fromNames(create=true)` ephemeral re-creation) | lock()-logic-derived | **Intentionally retained**. `create=true` is canonical name resolution itself; making remote alone `create=false` is "adding non-bridge remote-specific judgement," against the lens. Narrow, not fail-open, converges to one orphan → accepted. Documented in design §4 (prevent re-litigation) |
| **M1E-2** (resource+label selector mismatch) | local-derived, not fail-open | **Retained** (candidateFilter enforces exposure so no bypass; no remote-specific judgement added) |
| **M1E-3** (lease ops no ownership check) | by design | **Retained** (P1+ when multi-tenant) |
| **L-b** (url scheme unvalidated) | bridge hardening | **Implemented**: `RemoteConnection.validate()` rejects non-http(s) + `doCheckUrl` |
| **L-c** (POST body unbounded) | bridge hardening | **Implemented**: 1 MiB cap → 413 `PAYLOAD_TOO_LARGE` |
| **L-d** (FAILED→202 fall-through) | bridge hardening | **Implemented**: `FAILED` (non-`UNKNOWN_*`) → 400 `ACQUIRE_FAILED` |
| **L-a** (setRemotes eager save) | harmless (atomic via BulkChange) | **Retained** |
| **L-e** (getExposeLabels re-splits) | perf only | **Retained** |

> admission (unknown→404) is **kept** as the remote terminal policy (not removed). All three implemented items are confined to the
> HTTP boundary / transport and do not touch lock() logic, canonical delegation, or transparent equivalence. **M1E-1 "won't fix" was
> settled with the user** (design §4).

---

## Table of contents

1. [Overall](#1-overall)
2. [What M1E improved](#2-what-m1e-improved)
3. [Findings](#3-findings)
   - [M1E-1 (Low–Medium) The promotion path has no admission re-check, so a named resource deleted while QUEUED is re-materialised as an orphaned ephemeral](#m1e-1)
   - [M1E-2 (Low) When resource and label are both supplied, admission inspects resource but resolution uses label (selector-precedence mismatch)](#m1e-2)
   - [M1E-3 (Low / by design) Lease ops authorize on the REMOTE permission only, not lockId ownership](#m1e-3)
4. [Minor / nits](#4-minor--nits)
5. [Answer to the user's open questions in memo.txt (transparent-equivalence ruling)](#5-answer-to-the-users-open-questions-in-memotxt-transparent-equivalence-ruling)
6. [Test / verification-layer assessment](#6-test--verification-layer-assessment)
7. [Recommended actions (priority order)](#7-recommended-actions-priority-order)

---

## 1. Overall

**M1E achieves the goal the cycle declared (resolving the M1D-review H-1 / M-2 and a deliberate simplification), at high quality.**
The H-1 that the M1D review called "the one thing to close before claiming transparent equivalence" (unknown/unexposed names proliferating and persisting ephemerals) is closed via two steps:

- **removing `createResource` from the resolution path** (`addRemoteStruct` passes only validated names into `LockableResourcesStruct`), and
- **adding admission (`validateRemoteSelectors`) at the head of `enqueue`'s `syncResources` block**, rejecting unknown/unexposed up front with a uniform 404
  (`UNKNOWN_RESOURCE` / `UNKNOWN_LABEL`).

On the **immediate-acquire path this fully closes H-1** (the direct test `enqueueRejectsUnknownResourceAndCreatesNothing` asserts "FAILED and `fromName` is null").
M-2 (the exposure ExtensionPoint being AND-fixed and non-replaceable) is resolved by removing the `RemoteResourceExposurePolicy` / `ExposeLabelPolicy` SPI and
collapsing to **a single exposeLabel concept**. The accompanying extension of exposeLabel to **a whitespace-separated label set (OR exposure)** is implemented with the
right separation: "requested-label AND (any exposeLabel)" is confined **entirely to the canonical generic `Predicate` seam, leaving local single-label matching untouched**
(§4-3), and the local-unchanged evidence (375→378 green, local behaviour invariant) holds. M1D's core gains (canonical delegation, shared env-var builder,
single-`syncResources`-region concurrency) are retained without regression, and M1C's re-implementation (`claimSelector` etc.) is not revived. The cycle is faithful to
its stated intent: **the composition of "M1C admission (404) + M1D canonical resolution."**

**However, claiming "the H-1 class is fully closed" requires one more path (M1E-1).**
Admission runs **only at `enqueue`'s entry (immediate acquire)** and is **not re-checked** on the QUEUED→promotion path (`getNextRemoteEntry` → `availableForRemote`).
Promotion resolution goes through the canonical name branch `fromNames(..., /*create*/ true)`, so **if an admin deletes the target resource while a request is QUEUED,
the promotion scan re-materialises that name as an ephemeral** (the exposeLabel filter then rejects it, so it is **never locked and persists as an orphan**).
This is the **same class** of residue as the H-1 closed on the immediate path. Its trigger is narrow (admin deletes an exposed-but-busy resource that is QUEUED) and its impact
is bounded (one orphan per name, not unbounded), but **design §3-4's statement "on promotion the candidateFilter keeps rejecting it" overlooks the side effect that
`fromNames(create=true)` materialises the entity first.**

In sum, **M1E succeeds on the main line of design, implementation, and tests**, and on the immediate-acquire main path H-1 is resolved. What remains is the single M1E-1
(missing promotion-path admission re-check), which should be closed before PR or at least documented as a known limitation. All other findings (M1E-2 / M1E-3 / nits) are
not fail-open (no breach of mutual exclusion) and are low priority.

---

## 2. What M1E improved

- **H-1 structurally closed on the immediate-acquire path.** Removing `createResource` plus admission cut the "remote request creates a new ephemeral on the server" path at
  the entry. `addRemoteStruct` documents the intent (`// No ephemeral creation here … (H-1, M1E)`) and `toRemoteStructs`'s Javadoc states "resolved by name only (no ephemeral
  creation)." **Validation lives inside `enqueue` (single source, correct `syncResources` lock)** and the boundary (`RemoteApiV1Action`) only maps to HTTP 404 — the right layering,
  avoiding M1C's duplicated boundary `fromName` check.
- **Exposure filter simplified to a single exposeLabel concept.** The SPI (`ExtensionPoint`, AND folding, the "no policies ⇒ expose all" dead path) is entirely removed.
  Exposure collapses to the one-line predicate `isExposed(r) = !disjoint(r.labels, exposeLabels)`, and M-2's doc/impl drift ("non-replaceable but documented as replaceable")
  **disappears with the concept** (a correct application of YAGNI).
- **exposeLabel set-ification (OR exposure) implemented without leaking into canonical.** `getExposeLabels()` splits on `\\s+` (the String `getExposeLabel()` is unchanged,
  backward compatible). "Requested-label AND exposeLabel(set)" is **100% confined to the `r -> isExposed(r, exposeLabels)` predicate the remote layer builds in
  `availableForRemote`**; canonical (`getAvailableResources` / `getFreeResourcesWithLabel`) only takes a generic `Predicate` and knows nothing about exposeLabel.
  The filter is applied **before** count-based selection (`candidates.removeIf(...)`), so `quantity 0 = all visible matching` holds. Local callers pass `r -> true`, so
  **behaviour is fully invariant**. `multipleExposeLabelsAreOredForExposure` (with `"gpu license"`, gpu-1/lic-1 ACQUIRED, other-1 `UNKNOWN_RESOURCE`) pins the OR semantics directly.
- **L-3 resolved (env-var single source).** `RemoteQueueEntry.onAcquired` no longer builds the map inline; it routes through the same
  `LockableResourcesManager.remoteLockEnvVars(variable, resources)` the immediate path uses. `buildLockEnvVars` is shared by immediate/promotion/local, so `VAR0_<PROP>` propagates.
- **L-4 resolved (invalid selectStrategy).** The POST boundary rejects an unknown strategy with **400 `INVALID_SELECT_STRATEGY`** (consistent with local "reject invalid values").
  `parseSelectStrategy`'s lenient fallback is kept as a safety net. Covered by `RemoteApiV1ActionTest`.
- **Deliberate non-equivalence documented.** "Unknown/unexposed → immediate 404" (local would QUEUE and wait) is recorded in design §6 as **a settled decision, not to be re-litigated**.
  This is also the long-standing "is what was created what was declared?" verification gap (since M1A) finally closed by making admission a single source.
- **Verification evidence confirmed present.** mvn 378/0 failures (+3 over M1D's 375: H-1 regression, unexposed rejection, OR exposure, selectStrategy, promotion env-var),
  E2E 20/20 (adds S17 "unknown acquire → 404 + ephemeral not created `NOT_CREATED=true`"). Reports exist; tree clean at `5d956de`.

---

## 3. Findings

<a id="m1e-1"></a>
### M1E-1 [Low–Medium / robustness — H-1-class residue on the promotion path] A named resource deleted while QUEUED is re-materialised as an orphaned ephemeral by the promotion scan

**Symptom:** A remote acquire for an exposed but currently busy named resource R passes admission and becomes **QUEUED** (correct). If an admin then removes R from configuration
while it is QUEUED, a subsequent promotion scan (`getNextRemoteEntry`, the 1-second tick) **re-creates R as a `LockableResource` and persists it to `config`**. The re-created R
carries no exposeLabel, so the candidateFilter (`isExposed`) immediately rejects it → `available=null` → the entry stays QUEUED, but **the created ephemeral is never locked by anyone
and is never reclaimed**.

**Path:**

1. Admission (`validateRemoteSelectors`) runs **only at `enqueue`'s entry** (`RemoteLockManager.enqueue`, head of the `syncResources` block). There is **no re-check** after QUEUED.
2. Promotion is `proceedNextContext` → `getNextRemoteEntry` → `availableForRemote(entry.getStructs(), …)` → `getAvailableResources(structs, …, candidateFilter)`. A name-based
   struct is built at enqueue time via `new LockableResourcesStruct(names, label, quantity)` and **holds resolved `LockableResource`s in `required`** (`LockableResourcesStruct.java:90-99`,
   resolved by `fromName` at construction).
3. Deleting R leaves `struct.required` holding an **orphaned `LockableResource`** detached from the manager. The canonical name branch calls
   `available = fromNames(getResourcesNames(required), /*create*/ true)` (around `LockableResourcesManager.java:1738`), so it **re-creates the now-absent name with `create=true`**
   (`allowEphemeralResources` defaults to `true`).
4. The following `available.stream().anyMatch(r -> !candidateFilter.test(r))` rejects the re-created unlabeled ephemeral → `available=null` → entry stays QUEUED. **The ephemeral
   remains** (subsequent ticks find the existing one, so it converges to a single orphan; it survives `QUEUE_EXPIRED` and persists in `config`, restart-resilient).

**Why it matters:**

- The **same class M1E declared "closed"** in H-1 (an ephemeral that is neither exposed nor locked persisting on the server) is closed on the immediate path but **remains on the
  promotion path**. The immediate path is safe because existence is guaranteed within the same `syncResources` as admission; the promotion path admits an admin delete in the time gap.
- **Design §3-4's text diverges from reality.** §3-4 says "on promotion the candidateFilter keeps rejecting it and it degrades to `QUEUE_EXPIRED`" but does not mention the side effect
  that `fromNames(create=true)` creates the entity *before* the rejection.
- That said it is **not fail-open** (no incorrect lock is ever granted), the trigger is narrow (exposed, busy, admin delete while QUEUED), and the orphan converges to one per name.
  Hence severity **Low–Medium** (below the Medium of H-1 proper).

**Fix options (either; (a) is cheap):**

- **(a) Re-check admission on promotion (recommended).** Before `getNextRemoteEntry` attempts resolution, re-run `validateRemoteSelectors(entry.getLockRequest())`; if `!= null`,
  `markFailed` the entry (e.g. the existing `QUEUE_EXPIRED` or a new `TARGET_GONE`) and add it to `toRemove`. This rejects ahead of re-creation, so no ephemeral is created, and it
  matches §3-4's description.
- **(b) Add a seam to resolve remote names with `create=false`.** Split the canonical name branch so `create` is selectable, and pass `false` from remote. Broader change than (a).
- **Add a regression test (L-class) too:** "name request becomes QUEUED → admin deletes that resource → after a promotion tick, `fromName` for that name is still null (not re-created)."
  The current promotion tests do not exercise a delete interleaving.

<a id="m1e-2"></a>
### M1E-2 [Low / consistency — not fail-open] When resource and label are both supplied, admission inspects resource while resolution uses label

`validateSelector` **checks resource first** and, if resource is present, ignores label (returns in the `resource != null` branch). Meanwhile `getAvailableResources` **prefers the
label branch** when label is present, ignoring the name (existing canonical behaviour). So for a both-supplied request like `{resource:"<exposed>", label:"<some>"}`, **admission passes
on resource exposure, but actual resolution uses label**.

- **Exclusion/exposure safety is preserved.** The resolution's label branch also applies the candidateFilter (`isExposed`), so **no unexposed resource is ever locked** (no bypass).
- But "the selector admission validated" disagreeing with "the selector resolution uses" is **semantically inconsistent** and can produce counterintuitive error behaviour (resource
  is exposed but label has no candidate → passes admission, then `availableForRemote` returns null → QUEUED).
- Local lock() also ignores resource when label is present, so **the ambiguity itself is local-derived**. Rejecting "both resource and label supplied" with 400 at the boundary
  (`RemoteApiV1Action` POST), or making `validateSelector` validate both when both are present, would align it. Severity **Low**.

<a id="m1e-3"></a>
### M1E-3 [Low / by-design confirmation] Lease ops (heartbeat / release) authorize on the REMOTE permission only, not lockId ownership

`POST /lease/{lockId}/heartbeat` and `/release` only check the `LockableResourcesRootAction.REMOTE` permission and **do not confirm the caller's clientId owns that lockId**. The
lockId is a UUID (a capability) others normally cannot learn, but **another client holding the REMOTE permission could, if it learns a lockId, release / heartbeat another client's lock**.

- For the intended user (small-scale, mutually trusting CI/CD — the design's premise) this is **acceptable**, and it is exactly the existing (M1A/M1B) trust model
  (trust boundary = the REMOTE permission). It is not a new M1E issue.
- For multi-tenant expansion, lease ops could verify "record.clientId matches the caller's clientId" (a P1+ candidate). For this cycle it is **recorded as a known design choice**.
  Severity **Low (design confirmation)**.

---

## 4. Minor / nits

| # | Item | Weight | Location |
|---|---|---|---|
| L-a | Only `setRemotes` calls `save()` mid-binding (the others — `setExposeLabel`/`setClientId`/`setForcedServerId`/`setRemoteApiEnabled` — do not). The final GlobalConfiguration `save()` overwrites it, so it is harmless, but an eager save mid form-binding is inconsistent and also causes an unneeded early save via CasC. Recommend unifying (no save in setters) | Low (consistency) | `LockableResourcesManager.setRemotes` |
| L-b | `RemoteConnection.validate()` only checks serverId/url non-empty and **does not validate the url scheme (http/https)**. `file:` etc. pass (`RemoteApiClient.resolve` flows straight through `URI.create`). Low risk as it is an admin-set value, but a `doCheckUrl` (FormValidation) requiring http(s) would be friendlier | Low (robustness) | `RemoteConnection` |
| L-c | `RemoteApiV1Action.parseJsonBody` reads the POST body **without a cap** (`while read`). With REMOTE-authenticated callers the real risk is low, but a huge body can induce OOM. A `Content-Length` cap or a read-byte cap would be a safety net | Low (DoS safety net) | `RemoteApiV1Action.parseJsonBody` |
| L-d | In `RemoteApiV1Action` POST, if `enqueue` returns `FAILED` for a reason other than `UNKNOWN_*` (effectively `MISSING_TARGET`, unreachable due to the boundary `MISSING_TARGET` check), it falls through to **returning FAILED with 202**. Unreachable today, but defensively mapping "FAILED → 4xx" hardens it against future code | Low (defensive) | end-of-POST branch in `RemoteApiV1Action` |
| L-e | `getExposeLabels()` rebuilds the set via `split` on every call (per tick × candidates during the promotion scan). Negligible at small scale, but it could be cached in the `exposeLabel` setter (optional) | Low (perf) | `LockableResourcesManager.getExposeLabels` |

---

## 5. Answer to the user's open questions in memo.txt (transparent-equivalence ruling)

The user's `memo.txt` questions are the heart of M1E, so here is a settled answer grounded in the actual code (to prevent re-litigation).

> **Q. Can a remote resource request be read as "the lock() parameters PLUS exposeLabel ANDed on top"?**

**A. Yes.** This is exactly M1E's design (design §4-3), and the code is strict about it:

- Resolution is delegated to canonical `getAvailableResources`, and **the only remote-specific difference is applying `candidateFilter = r -> isExposed(r, exposeLabels)`** to the
  candidate pool **before** count-based selection (`candidates.removeIf(...)` in `getFreeResourcesWithLabel`).
- That is, "label match (or name match) = the existing single-label match (unchanged)" AND "carries any of the exposeLabel set" = the visibility filter. The exposeLabel AND/OR logic is
  confined to the remote layer and never mixes into local semantics.

Implementation behaviour for memo.txt's example (res1: `dev1` / res2: `dev1 exposed` / res3: `dev1 exposed` / res4: `dev2 exposed`, i.e. exposeLabel=`exposed`):

| Request | Admission (`validateRemoteSelectors`) | Result | memo expectation | Match |
|---|---|---|---|---|
| `lock(resource:'res1')` | res1 lacks `exposed` → `UNKNOWN_RESOURCE` | **404** | http 404 | ✓ |
| `lock(resource:'res2')` | res2 has `exposed` → pass. ACQUIRED if free / QUEUED if busy | **202 (ACQUIRED/QUEUED)** | QUEUED | ✓ |
| `lock(label:'dev1')` | `hasExposedCandidate('dev1', {exposed})` = res2/res3 match → pass. Acquire from the `dev1`∧`exposed` visible candidates | **202 (ACQUIRED/QUEUED)** | QUEUED | ✓ |

> **Note (memo's "the original lock can only pass one label"):** Correct, and local single-label matching is unchanged. The remote side absorbs "requested label X (single) AND
> exposeLabel(set, OR)" in the visibility filter, so **there is no need to embed multi-label AND into local**. exposeLabel being **multiple** is the "exposing side's marker set," whereas
> the requesting side's label is still one. They are separate axes (the §4-3 separation).

> **On memo's "the remote-path ephemeral could be stamped out":** On the immediate-acquire path, **yes** (H-1 resolved, test-proven). But one same-class residue remains on the
> promotion path (**M1E-1**). To say it is "fully stamped out," M1E-1 must be addressed.

---

## 6. Test / verification-layer assessment

- **The test gaps flagged in the M1D review are largely filled.** Direct H-1 (`enqueueRejectsUnknownResourceAndCreatesNothing`: FAILED and `fromName==null`), unexposed-name
  rejection (`unexposedNamedResourceIsRejected`), exposeLabel OR exposure (`multipleExposeLabelsAreOredForExposure`), invalid selectStrategy → 400 (`RemoteApiV1ActionTest`),
  the promotion env-var path, and E2E S17 (real-environment `NOT_CREATED=true`) are all covered. This follows the [[rlr-equivalence-test-defaults]] lesson of "poke defaults/absent/0/empty."
- **The one gap is the M1E-1 path.** There is no test exercising "name request becomes QUEUED → admin deletes that resource → after a promotion tick it has not been re-created."
  Add it when closing M1E-1 via (a) (see the regression test sketch under §3 M1E-1).
- The E2E spec (`E2E_TEST_SPECIFICATION.md`) could, when time permits, add the M1E-1 "no resource growth on delete-while-QUEUED" scenario under a future tag.

---

## 7. Recommended actions (priority order)

1. **Close M1E-1** (recommended (a): re-run `validateRemoteSelectors` before `getNextRemoteEntry` resolves, terminal-mark the entry if inadmissible). This **closes on the promotion
   path** the H-1 closed on the immediate path and aligns the implementation with design §3-4's text. Add the regression test too.
   **Then you can claim "the remote-path ephemeral is stamped out (on every path)."**
2. **Update design §3-4 to match reality** (state that, on promotion, `fromNames(create=true)` can re-create the entity before the candidateFilter rejects it, and how it is handled).
   After closing M1E-1 via (a), update to "admission is re-checked on promotion too."
3. **M1E-2** (resource+label selector mismatch) is optional. Reject with 400 at the boundary, or make `validateSelector` validate both. Low priority since it is not fail-open.
4. **M1E-3 / L-a–L-e** can be deferred. Record M1E-3 as "lease-op ownership check is P1+ (when multi-tenant)" in notes. L-b (url scheme check) / L-c (body cap) are cheap safety nets.
5. Add "M1E-1 registered as a residual task" to the M1E entry in memory/notes ([[remote-lock-project-state]]).

> **Wrap-up:** M1E resolves the two main M1D-review findings (H-1 / M-2) as designed and adds the practical exposeLabel-set (OR) exposure **without polluting canonical** — a low-risk,
> high-value cycle. On the immediate-acquire main path H-1 is closed and tests are thick. What remains is the single **M1E-1 (ephemeral re-creation from the missing promotion-path
> admission re-check)** — narrow and not fail-open, but addressing (or documenting) it is needed to declare "the H-1 class is closed on every path." With that handled, M1E reaches PR quality.

---

## Change log

- 2026-06-14: Initial version. Static read of the full `master`(`863ea4d`)..M1E(`5d956de`) diff (43 files / +5256). Evaluated the resolution of the M1D-review H-1 / M-2 (immediate-acquire
  path) and the consistency of exposeLabel-set (OR) exposure / canonical delegation as an architectural success. Detected the new finding M1E-1 (missing promotion-path admission
  re-check → ephemeral re-creation/orphaning of a deleted resource, a residue of the H-1 class, Low–Medium). Added M1E-2 (resource+label selector mismatch, Low, not fail-open),
  M1E-3 (lease-op no ownership check, by design), and nits L-a–L-e. Gave a settled "Yes" to memo.txt's question (remote request = lock() + exposeLabel AND) and demonstrated the
  example behaviours matching in a table.
