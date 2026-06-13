# M1E Implementation Steps (Remote lock - Phase 1 / M1E)

Progress tracker for M1E (design: `LRR_DESIGN_P1_M1E.md`).
**M1D review fixes + intentional simplification** — reject unknown/unexposed with a uniform 404; commit to a single exposeLabel filter (multi-label).

> Naming note: `作業手順一覧.md` calls the work plan `LRR_IMPLEMENTATION_PLAN_XX_YYY.md`, but the existing five
> milestones (M1/M1A/M1B/M1C/M1D) and the cycle definition-of-done use `LRR_IMPLEMENTATION_STEPS_*`, so this
> doc follows `STEPS` for consistency (a wording drift in the procedure doc; rename on request).

---

## Background

Resolves the M1D-completion review (`LRR_REVIEW_P1_M1D.md`) findings H-1 (ephemeral proliferation/persistence for unknown/unexposed names = new regression) and M-2 (over-engineered exposure `ExtensionPoint`). Canonical delegation (M1D's win) is kept; M1C's re-implementation (`claimSelector` etc.) is not revived. Effectively "M1C's admission check (404) + M1D's canonical resolution".

### Decisions (2026-06-13, user-confirmed)

- **H-1 = (a) + API-natural rejection**: drop `createResource` from the resolution path. Unknown/unexposed → uniform **404** (`UNKNOWN_RESOURCE` / `UNKNOWN_LABEL`). Busy (exposed, locked) still 202 QUEUED (peer-release wait).
- **M-2 = simplify**: delete `RemoteResourceExposurePolicy` / `ExposeLabelPolicy`; exposeLabel is the single filter. The `getAvailableResources(..., Predicate)` seam is kept (needed for label quantity=all; local untouched). allowlist/authz deferred to P1+ (YAGNI).
- **exposeLabel multi-label**: interpret as a whitespace-separated set, OR exposure (R's labels ∩ exposeLabel set ≠ ∅). Single value backward compatible. "requested-label AND exposeLabel(set)" absorbed via the generic Predicate, leaving local's matching untouched (design §4-3).
- **L-3/L-4/L-5**: unify env vars / 400 on invalid strategy / expand tests.

---

## Steps

### 0. Preparation

- [x] Create the m1e branch (m1d-based, HEAD `819daa0`) = `feature/1025-remote-lockable-resources-p1-m1e`
- [x] Author `LRR_DESIGN_P1_M1E` / this doc (j+e), an M1E banner in `LRR_REVIEW_P1_M1D`, README index update

### Step 1: M-2 simplification (exposeLabel filter) + multi-label exposeLabel

- Delete `RemoteResourceExposurePolicy.java` / `ExposeLabelPolicy.java`.
- **Multi-label exposeLabel**: add `getExposeLabels()` (split `exposeLabel` String by `\s+` + fixEmpty into a set). `getExposeLabel()` / setter unchanged (backward compatible).
- Change `availableForRemote` from `RemoteResourceExposurePolicy.visibilityFor(req)` to an **exposeLabel-set OR predicate**: `r -> !Collections.disjoint(r.getLabelsAsList(), exposeLabels)` (empty exposeLabels → `r -> false`).
- Keep the `getAvailableResources(..., Predicate)` / `getFreeResourcesWithLabel(..., Predicate)` seam (local untouched).
- Tidy imports (remove the `RemoteResourceExposurePolicy` reference).
- Config UI: update help (`config.jelly`) / title (`config.properties`) to "space-separated, multiple allowed" (the textbox itself is unchanged).

#### Done when
- [x] implemented / [ ] compiles green (no policy references remain) / [ ] single-value backward compat verified / [ ] committed

### Step 2: H-1 fix (drop createResource + 404 admission)

- Remove the `createResource(resource)` call in `addRemoteStruct`.
- Revive `validateRemoteSelectors` / `validateSelector` / `hasExposedCandidate` on an **exposeLabel-set basis** (exposeLabel direct, not an `ExtensionPoint`; validate main + each extra; unknown/unexposed → `UNKNOWN_RESOURCE`; label with no exposed candidate → `UNKNOWN_LABEL`; absent selector → null).
- In `RemoteLockManager.enqueue`, call `validateRemoteSelectors` at the top of the `synchronized` block; on a non-null errorCode `record.markFailed(errorCode)` and return (do not reach `toRemoteStructs` = no creation, no resolution).
- `RemoteApiV1Action` POST `/acquire`: after enqueue, map `record.state == FAILED && errorCode ∈ {UNKNOWN_RESOURCE, UNKNOWN_LABEL}` to **404** (otherwise 202 as before).

#### Done when
- [x] implemented / [ ] unknown/unexposed → 404 and no resource created / [ ] busy → 202 QUEUED preserved / [ ] committed

### Step 3: Minor (L-3 / L-4)

- **L-3**: route `RemoteQueueEntry.onAcquired` through `LockableResourcesManager.remoteLockEnvVars(variable, resources)`.
- **L-4**: reject an unknown `resourceSelectStrategy` at the POST boundary with **400 `INVALID_SELECT_STRATEGY`**. Keep `parseSelectStrategy`'s lenient fallback as a safety net.

#### Done when
- [x] implemented / [ ] committed

### Step 4: Tests (L-5)

- Flip M1D's "unknown → QUEUED" tests to M1E's "unknown → 404 (terminal)":
  - `enqueueQueuesWhenResourceDoesNotExist` → assert the unknown-name acquire is 404/FAILED `UNKNOWN_RESOURCE` **and that no resource for that name was created/persisted** (H-1 regression).
  - `enqueueQueuesForUnknownLabel` → `UNKNOWN_LABEL`.
- Flip `RemoteApiV1ActionTest`'s "unexposed → 202 QUEUED" back to "→ 404" (uniform 404).
- Adjust tests for the policy deletion (any `RemoteResourceExposurePolicy` references → exposeLabel-based). Change the exposeLabel-filter test (the `unexposedNamedResourceStaysQueued` analogue) to "unexposed → 404".
- Add: selectStrategy (`RANDOM`) reflected over remote / resource-property env vars on the QUEUED→promotion (`onAcquired`) path / invalid strategy → 400 / multi-label exposeLabel OR.
- Full `mvn test` via `stabilize-build.sh` (worktree), save the report.

#### Done when
- [x] tests flipped/added / [ ] `mvn test` green (count / 0 fail / `dev/reports/…-mvn-test.log`) / [ ] committed

### Step 5: E2E maintenance + full run

- Existing scenarios pass under M1E (verify exposeLabel-single→set and 404 changes), especially S08 (label-env-vars) / S14 / S15 / S16 unchanged with a single exposeLabel filter.
- Add: **S17 `remote-unknown-rejected`** (`m1e-series`) — an acquire for an unknown/unexposed resource returns **404** and the server's resource list does **not** grow (no ephemeral creation), proven end-to-end.
- `run-e2e.sh --clean-start` all pass, save report.

#### Done when
- [x] E2E maintenance (add S17 + register in run-e2e + spec j+e) / [ ] all pass (`dev/reports/…-e2e-test.md`) / [ ] notes committed

### Step 6: Finalize docs + cycle completion

- Author `LRR_RESULT_P1_M1E` (j+e), add the resolution table (H-1/M-2/L-3/L-4/L-5) to `LRR_REVIEW_P1_M1D`, reflect the E2E spec (S17 / `m1e-series`, j+e), update the README index, fully sync docs-e.
- Commit plugin / notes (no Co-Authored-By, no push).

#### Done when
- [x] `*_M1E.md` (DESIGN/STEPS/RESULT, j+e) ready / [ ] mvn full green / [ ] E2E all pass / [ ] resolution table & index updated

---

## Test execution policy (M1E)

1. Full regression via `stabilize-build.sh` (worktree mode). `mvn test` covers the code changed in M1E.
2. Run the **whole** latest `run-e2e.sh` with `--clean-start` and save the report (cycle done-condition).
3. Cycle done-condition per [[rlr-cycle-definition-of-done]]: `*_M1E.md` (j+e) + full stabilize-build + full run-e2e.

## Change log

- 2026-06-13: Initial version. M1E (M1D review fixes + simplification) implementation plan. Implementation not yet started (begins after review).
- 2026-06-14: All steps complete. plugin `5d956de`. mvn 378 / 0 fail (`dev/reports/20260614002216-mvn-test.log`),
  E2E 20/20 PASS (S17 added, `dev/reports/20260614004015-e2e-test.md`). Docs (DESIGN/STEPS/RESULT, j+e) ready,
  `LRR_REVIEW_P1_M1D` resolution table updated, README index/Status updated.
