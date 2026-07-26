# Remote LR Development Review (Phase 1 / at M1D completion)

> **Review date:** 2026-06-13
> **Plugin branch under review:** `feature/1025-remote-lockable-resources-p1-m1d` (HEAD: `819daa0`, single commit; mvn 375 pass, E2E 19/19)
> **Documents under review:** `dev/docs-j/` (LRR_DESIGN_P1_M1D / LRR_IMPLEMENTATION_STEPS_P1_M1D / LRR_RESULT_P1_M1D / E2E_TEST_SPECIFICATION), `LRR_REVIEW_P1_M1B.md`
> **Lens:** original intent ([#1025](https://github.com/jenkinsci/lockable-resources-plugin/issues/1025)); how well M1D meets its core goal ("true bridging" = delegating to lock()'s canonical path = transparent equivalence); soundness of the delegation refactor; any new regressions.
> **Method:** Same as the M1A/M1B reviews. The full build (~17 min) was not re-run; the `819daa0` diff and code were read statically. The test count (375) / E2E (19/19) are trusted from the recorded reports, whose existence was verified (`dev/reports/20260613125351-mvn-test.log` = `Tests run: 375, Failures: 0, Skipped: 1` / `BUILD SUCCESS`; `dev/reports/20260613132702-e2e-test.md` = `pass: 19 / fail: 0`; working tree clean at `819daa0`). As noted below, however, that test layer never exercises one path M1D newly opened.

---

## M1E response (updated 2026-06-14, **resolved**)

The M1E cycle addressing these findings is complete (plugin branch `feature/1025-remote-lockable-resources-p1-m1e`
HEAD `5d956de`, m1d-based). Directions and resolution (`LRR_DESIGN_P1_M1E.md` / `LRR_IMPLEMENTATION_STEPS_P1_M1E.md` /
`LRR_RESULT_P1_M1E.md`):

| Finding | M1E direction (confirmed) |
|---|---|
| H-1 ephemeral proliferation | **(a) + API-natural rejection**: drop `createResource` from the resolution path. Unknown/unexposed → uniform **404** (`UNKNOWN_RESOURCE`/`UNKNOWN_LABEL`). A busy (exposed) target still 202 QUEUED. "unknown → 404" intentionally replaces M1D's "unknown → QUEUED" (small-scale scope, existence hiding, no resource pollution). |
| M-2 ExtensionPoint over-engineering | **Simplify**: delete `RemoteResourceExposurePolicy`/`ExposeLabelPolicy`; **exposeLabel is the single filter**, now a whitespace-separated **set of labels (OR exposure)**. "requested-label AND exposeLabel" is absorbed in the remote layer as a plain Predicate, leaving local untouched (design §4-3). allowlist/authz deferred to P1+ (YAGNI). |
| L-3 env-var duplication | Unify `onAcquired` to `remoteLockEnvVars`. |
| L-4 invalid strategy | **400** `INVALID_SELECT_STRATEGY` at the POST boundary. |
| L-5 test gaps | unknown→404 with **no resource created** regression, unexposed→404, selectStrategy, promotion-path env vars, new S17. |

**Resolution confirmed (2026-06-14):** all of the above implemented and verified. **mvn test 378 / 0 fail**
(`dev/reports/20260614002216-mvn-test.log`), **E2E 20/20 PASS** (`dev/reports/20260614004015-e2e-test.md`).
S17 proves end-to-end "unknown acquire → fast 404 failure + no ephemeral created on the server
(`NOT_CREATED=true`)". See `LRR_RESULT_P1_M1E.md`. All M1D review findings are closed.

---

## Table of contents

1. [Summary](#1-summary)
2. [What M1D got right (an architectural success)](#2-what-m1d-got-right-an-architectural-success)
3. [Findings (H-1 / M-2)](#3-findings)
4. [Minor (L-3/L-4/L-5)](#4-minor-l-3l-4l-5)
5. [Transparent-equivalence confirmations](#5-transparent-equivalence-confirmations)
6. [Test / verification layer](#6-test--verification-layer)
7. [Recommended actions (priority order)](#7-recommended-actions-priority-order)

---

## 1. Summary

**M1D's central design decision is correct and the implementation is high quality.** The diagnosis — that "the server re-implementing lock() semantics" was the root cause of the recurring per-feature `extra`/`label`/`quantity` residue (M1A→M1B→M1C) — is accurate, and cutting it structurally by **delegating to the canonical `getAvailableResources` path** is the biggest architectural step forward in this project. Removing the whole re-implementation block (`resolveRemoteAvailable`/`claimSelector`/`validateRemoteSelectors`/`generateLockEnvVars`) and doing it via a backward-compatible overload (the `Predicate<LockableResource>` variant; existing callers pass `r -> true`) without touching local is low-risk and high-impact. Sharing env-var generation (`LockStepExecution.buildLockEnvVars`) so resource-property env vars become transparent, and lifting exposure out of the bridge into `RemoteResourceExposurePolicy` (an `ExtensionPoint`), are both correct layering.

Concurrency does not regress from M1C. Both the immediate acquire (`RemoteLockManager.enqueue`) and queue promotion (`getNextRemoteEntry`→`proceedRemoteEntry`) resolve-then-lock **within a single continuous `syncResources` hold**, so there is no resolve→lock TOCTOU (the promotion path runs entirely under `synchronized (syncResources)` in `proceedNextContext()`). The M1B C-2 fix (client release vs promotion race) is preserved.

**However, to claim "transparent equivalence" at face value, one path M1D newly opened has an unresolved problem (H-1).** To make "unknown/unexposed → QUEUED", M1D removed the POST-boundary existence/exposure checks. That removal is reasonable by itself, but as a result **any client with RemoteUse permission can, just by requesting a non-existent resource name, create an ephemeral resource on the server that is neither exposed nor locked, and persist it to disk** (`createResource` runs before the exposure filter, and the created resource is never reclaimed). This is not an exclusivity violation (fail-open) like M1A/M1B; it is resource pollution / DoS by an authenticated client — but it is a regression **introduced by M1D itself**, and M1D's tests (unit and E2E) never exercise this "create-on-demand" path because they always pre-create the resource before requesting it. The structural weakness that runs through M1A→M1C — "the 'is what we built what we declared?' verification layer has a hole" — reappears here in a new form.

In conclusion, **M1D is a success on its main line** of design and implementation, but until H-1 is closed it cannot be called "transparent equivalence achieved, ready for PR".

## 2. What M1D got right (an architectural success)

- **Canonical delegation eliminates "per-feature residue" structurally.** `toRemoteStructs` converts a `RemoteLockRequest` into a `List<LockableResourcesStruct>` (mirroring `LockStep.getResources()`) and calls the same `getAvailableResources(structs, …, candidateFilter)` local uses. extra / label / quantity(0=all) / resourceSelectStrategy / dedup (`isPreReserved`) / ephemeral all come **from the canonical path**, so per-feature implementations — and per-feature drift — are gone. Ideal as a recurrence guard against the C-1/F-1 class.
- **Backward-compatible overload leaves local untouched.** `getAvailableResources(...)` / `getFreeResourcesWithLabel(...)` gain a `Predicate<LockableResource> candidateFilter` variant; existing variants delegate with `r -> true` (`LockableResourcesManager.java:1612`). The filter is applied to the candidate pool **before** count selection (`candidates.removeIf(...)`, `:1728`), so `amount<=0` ("all") correctly means "all *visible* matching".
- **Shared env-var generation.** `proceed()`'s inline generation was extracted to `LockStepExecution.buildLockEnvVars` (~`LockStepExecution.java:649`), called by both local and the remote bridge. Generation (incl. `VAR0_<PROP>`) is unified and resource-property env vars become transparent.
- **Exposure layering.** `RemoteResourceExposurePolicy` (`ExtensionPoint`, SPI) + default `@Extension ExposeLabelPolicy`. The bridge folds policies into a `Predicate` for the canonical path. Since exposeLabel is a remote-only concept local lock() lacks, lifting it out of the resolution code into a filter layer is the right call (it was hardcoded in resolution up to M1C).
- **No concurrency regression.** resolve→lock under a single `syncResources` hold (no TOCTOU). M1C's release serialization preserved.
- **Verification trail exists.** mvn 375/0 fail, E2E 19/19 (S01–S16 + D01–D03). S16 `remote-resource-properties` proves property env-var propagation end-to-end. The report files exist; the tree is clean at `819daa0`.

## 3. Findings

### H-1 [Medium / security-robustness — new regression] Unknown/unexposed resource names cause ephemeral-resource proliferation and persistence

**Symptom:** Against a server with `remoteApiEnabled=true`, a client with RemoteUse permission that issues an acquire for a non-existent resource name (e.g. `resource: "scratch-" + random`) causes a **new ephemeral `LockableResource` to be created and saved to disk** every time. That resource is then never exposed, never locked, and **never reclaimed** because it never passes through a release path; it stays QUEUED. Looping over varying names grows the server's resource list and config XML **without bound**, and it survives restart.

**Path:**

1. M1D removed the POST-boundary existence/exposure check (see `RemoteApiV1Action.java:108-116` and `:145` comments "Exposure is decided by RemoteResourceExposurePolicy at resolution time, not here"). The only remaining acquire gates are `remoteApiEnabled` / `RemoteUse` / `MISSING_TARGET` — **no existence check**; any name reaches the resolver.
2. The resolver entry `toRemoteStructs` → `addRemoteStruct` calls `createResource(resource)` **before** the exposure filter is applied (`LockableResourcesManager.java:1223`). This is necessary because the `LockableResourcesStruct(resources,label,quantity)` constructor resolves names with `fromName` (no creation) and silently drops non-existent ones — so to make the request "look canonical" the resource must be materialised first.
3. `createResource` creates an ephemeral when `allowEphemeralResources` (**default `true`**, `:86`) and calls `addResource(resource, /*doSave*/ true)`, i.e. `this.save()` persists to disk (`:1295-1304`).
4. The exposure filter (default `ExposeLabelPolicy`) then judges the resource invisible (a fresh ephemeral has no exposeLabel), so `available = null` → **QUEUED** (`:1654-1659`).
5. QUEUED expires to `QUEUE_EXPIRED` and the record is failed/unqueued, but **the created ephemeral is not removed**. Ephemeral reclamation only happens on the `freeResources` lock→release path (`:919-928`), which this never-locked resource never enters.

**Why it matters:**

- **A regression M1D introduced itself.** In M1C, unknown/unexposed → terminal 404 `UNKNOWN_RESOURCE` at the boundary, never reaching `createResource`. By switching to "unknown → QUEUED" and dropping the boundary check, the create-on-demand path became externally reachable for the first time.
- **The trust boundary differs even though authenticated.** Local lock() also creates ephemerals for unknown names, but it is called by a **trusted in-process pipeline** and, having no exposure filter, **always locks what it creates and reclaims it on release**. Remote is called by a **semi-trusted network peer** and **hides the just-created resource so it is never locked → never reclaimed**. "Transparent equivalence" copied local's behaviour but, because of the filter layer, the **create/reclaim lifecycle alone became asymmetric**.
- **Persistent, unbounded, restart-resilient.** `doSave=true` writes config XML, so disk grows (not just memory) and looping requests also cause repeated `save()` (I/O).
- **Reachable in the default configuration.** Preconditions: remote feature enabled (`remoteApiEnabled=true`, admin opt-in) + `allowEphemeralResources=true` (default) + caller has RemoteUse. The exposeLabel value is irrelevant (`createResource` does not consult it). So **once the remote feature is on, it is reachable by default.**

**Note (creation is also pointless by design):** under the default `ExposeLabelPolicy`, a freshly created ephemeral carries no labels and so **can never be exposed or locked**. Thus ephemeral creation on the remote resolution path is **never useful** (except with a custom policy that exposes by name rather than label — a niche case). The "local creates so remote creates" transparency yields zero benefit and only cost here.

**Fix options (decide one):**

- **(a) Don't create ephemerals on the remote resolution path (recommended).** Drop the `createResource` call in `addRemoteStruct`; treat a non-existent name as "currently not visible → QUEUED" (matching local's "resources may appear later", with the resource appearing only if an *admin* later creates it). Nothing is lost under the default policy.
- **(b) Reclaim created-but-never-exposed ephemerals.** Sweep ephemerals created during a resolve that did not become a visible candidate, or reclaim unlocked ephemerals on QUEUE_EXPIRED.
- **(c) Restore a light existence check at the boundary.** Not recommended: re-introduces the enumeration oracle and the chicken-and-egg with label-based exposure.

**Also add an H-1 regression test** (below, L-5).

### M-2 [Low–Medium / design-doc consistency] The exposure ExtensionPoint is AND-only with an always-on default, so it cannot "replace" exposeLabel

`RemoteResourceExposurePolicy.visibilityFor` folds all registered policies with **AND (most-restrictive wins)**. Meanwhile the default `ExposeLabelPolicy` is always registered (`@Extension`) and returns `isExposed=false` for **every** resource when exposeLabel is empty (the default) (`ExposeLabelPolicy.java`). Combined:

- A third party that adds an "allow via per-client allowlist" policy finds that **with an empty exposeLabel, ExposeLabelPolicy vetoes everything and AND hides everything**, so the custom policy is effectively dead.
- To make a custom policy work, the admin must set exposeLabel to a label all candidate resources carry, i.e. only "exposeLabel **and** your extra restriction" is expressible. **You cannot *replace* exposeLabel with different logic.**

The design doc §4 says third parties can "replace/extend" the exposure decision, but the implementation only supports "**restrict further (extend)**", not "**replace**". The interface javadoc ("restrict exposure further" / "most-restrictive wins") is more accurate. Also the javadoc's "no policies registered ⇒ accept all (transparent)" branch is effectively dead since the default is always present.

Acceptable for M1D's scope (provide a seam, default = exposeLabel), but **if the seam is going to be a selling point in the PR, the doc and implementation must agree**:

- State in design/javadoc that custom policies layer **on top of** exposeLabel and **further** restrict (AND, most-restrictive wins).
- Document how to actually replace exposeLabel (disable/override the default `ExposeLabelPolicy`, or set exposeLabel permissively).
- Note that "all exposed when no policy registered" does not occur with the default present.

## 4. Minor (L-3/L-4/L-5)

| # | Content | Severity | Location |
|---|---|---|---|
| L-3 | Env-var map building duplicated. The immediate path uses `LockableResourcesManager.remoteLockEnvVars(variable, List<LockableResource>)`, but queue promotion `RemoteQueueEntry.onAcquired` **re-implements** the same `name→properties` map inline and calls `buildLockEnvVars` directly. Unify `onAcquired` via `remoteLockEnvVars`. | Low (maintainability) | `RemoteQueueEntry.java` (onAcquired) / `LockableResourcesManager.java` (remoteLockEnvVars) |
| L-4 | `parseSelectStrategy` silently falls back to SEQUENTIAL on an invalid `resourceSelectStrategy`. Local validates at the `LockStep` setter (`LockStep.java:112-124`) and rejects invalid values, so only here is lenient. For transparent equivalence, match local (reject) or warn. `java.util.Locale.ENGLISH` is inline-qualified (import tidy). | Low (equivalence/style) | `LockableResourcesManager.java` (parseSelectStrategy) |
| L-5 | Untested paths (see §6), especially the **H-1 create-on-demand path**, resourceSelectStrategy reflection over remote, and resource-property env vars on the **QUEUED→promotion (`onAcquired`) path**. | Low→Medium (verification) | `RemoteLockManagerTest` etc. |

## 5. Transparent-equivalence confirmations

Reviewed for "does this diverge from local?" and confirmed **equivalent by intent** — recorded here to prevent re-litigation in later cycles:

- **Empty set → QUEUED matches local.** `availableForRemote`'s `available.isEmpty() ? null` matches `getAvailableResources`'s own `available.isEmpty()` → `return null` (`:1664-1667`). `lock(label:'nonexistent-label')` locally also QUEUEs, so the remote QUEUED is equivalent (the `isEmpty` guard in `availableForRemote` is harmless defensive duplication).
- **Same-label main+extra (`lock(label:'X', extra:[[label:'X']])`) → QUEUED is a correct inheritance of a local quirk.** The canonical `isPreReserved` branch (`:1669-1679`, `available.removeAll(candidates)`) empties the extra and returns null → QUEUED. This is exactly local's known behaviour; dropping M1C's "two distinct" handling to match local is M1D's intent. Deleting the two dedup tests is appropriate.
- **selectStrategy default matches.** remote default (null) → SEQUENTIAL equals local default (`ResourceSelectStrategy.SEQUENTIAL`).

These are not "true non-equivalence" (latency / fail-close / restart transient); they are transparent equivalence by design.

## 6. Test / verification layer

- **Counts and regression are sufficient (375 unit + 19 E2E), but the path M1D opened has a negative/creation hole.** Same structural weakness as M1A §6#5 / M1B C-1 (the lesson behind [[rlr-equivalence-test-defaults]]).
- **Missing tests (add next cycle):**
  - **Direct H-1:** assert "acquire for a **non-existent** name → QUEUED/terminal" *and* "no ephemeral for that name was created/persisted". The current `enqueueQueuesWhenResourceDoesNotExist` checks QUEUED but **not creation**. `unexposedNamedResourceStaysQueued` pre-creates `internal-1`, so it never exercises create-on-demand.
  - **selectStrategy:** `resourceSelectStrategy: "RANDOM"` reflected over remote (planned in the steps but no unit in the diff).
  - **Property env vars on promotion:** `resourcePropertyEnvVarsArePropagated` covers only the immediate path. Queue then promote and assert `VAR0_<PROP>` via `onAcquired`.
  - **Policy replacement (M-2):** with `@TestExtension`, pin both "AND makes the most-restrictive win" and "a custom allow-policy has no effect when exposeLabel is empty", to match the doc.
- Add the H-1 regression (no resource growth on unknown name) to `E2E_TEST_SPECIFICATION.md` as well.

## 7. Recommended actions (priority order)

1. **Close H-1** (recommended option (a): don't call `createResource` on the remote resolution path). Nothing is lost under the default `ExposeLabelPolicy`, and it stops the pollution/DoS and disk growth. **Until this is done, do not claim "transparent equivalence achieved / PR-ready".**
2. **Add the H-1 regression test** (no resource growth after an unknown-name acquire). Also fill the selectStrategy / promotion env-var / policy-replacement units (§6).
3. **M-2: align the ExtensionPoint docs** ("AND, *further* restricts; replacement not supported; here's how"). Make design §4 and the javadoc agree.
4. Minor L-3 (unify env vars) / L-4 (invalid strategy handling) optional — fold into the next cycle or defer.
5. Update the memory/notes M1D entry to register H-1 as a next-cycle task ([[remote-lock-project-state]]).

> **Bottom line:** M1D's "true bridging" moves the architecture firmly in the right direction. Delegation, layering and concurrency are high quality and the main line of transparent equivalence is achieved. What remains is the single H-1 issue — the **create-on-demand ephemeral path** opened as a side effect of the "unknown → QUEUED" switch — plus its regression test. With that closed, M1D reaches PR quality.

---

## Change log

- 2026-06-13: Initial version. Full review at M1D completion (plugin `819daa0`). Rated the canonical-delegation "true bridging" an architectural success. Detected new regression H-1 (ephemeral proliferation/persistence for unknown/unexposed names) as Medium, and the exposure ExtensionPoint's AND-only/non-replaceable nature (M-2) as a design/doc-consistency finding. Confirmed the main line of transparent equivalence (empty set, same-label, selectStrategy default) is as intended.
- 2026-06-13: Added the "M1E response" banner with the user-confirmed directions (uniform 404 for unknown/unexposed; simplify to a single exposeLabel filter, now multi-label/OR).
