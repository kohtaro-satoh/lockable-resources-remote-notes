# M1E Result (Remote lock - Phase 1 / M1E)

> **Plugin branch:** `feature/1025-remote-lockable-resources-p1-m1e` (HEAD `5d956de`)
> **Design:** `LRR_DESIGN_P1_M1E.md` / **Steps:** `LRR_IMPLEMENTATION_STEPS_P1_M1E.md` / **Review:** `LRR_REVIEW_P1_M1D.md`
> **Scope:** M1D review fixes (H-1 / M-2) + intentional simplification — unknown/unexposed → uniform 404; the exposure filter is a single exposeLabel (multi-label).

---

## 1. What was achieved

The M1D-completion review findings were resolved while keeping canonical delegation (M1D's win). M1C's re-implementation (`claimSelector` etc.) was not revived; the result is **"M1C's admission check (404) + M1D's canonical resolution"**.

| M1D review finding | M1E resolution |
|---|---|
| **H-1 [Medium / new regression]** ephemeral proliferation/persistence for unknown/unexposed names | ✅ Resolved. Dropped `createResource` from the resolution path. An exposeLabel-set admission check (`validateRemoteSelectors`) at the top of `enqueue` `markFailed(UNKNOWN_*)`s unknown/unexposed → POST maps to a **uniform 404**. A busy (exposed) target still 202 QUEUED. **S17 proves "404 + no ephemeral created on the server" end-to-end** (`no_ephemeral=NOT_CREATED=true`). |
| **M-2 [Low–Med / over-engineering]** exposure ExtensionPoint AND-only/non-replaceable | ✅ Resolved. Deleted `RemoteResourceExposurePolicy` / `ExposeLabelPolicy`; **single exposeLabel filter**. Also made **exposeLabel a multi-label set (whitespace-separated, OR exposure)** (`getExposeLabels`). allowlist/authz deferred to P1+ (YAGNI). |
| **L-3** env-var generation duplication | ✅ `RemoteQueueEntry.onAcquired` unified onto `LockableResourcesManager.remoteLockEnvVars` (same as the immediate path). |
| **L-4** invalid resourceSelectStrategy silently defaulted | ✅ POST boundary returns **400 `INVALID_SELECT_STRATEGY`** (`parseSelectStrategy`'s lenient fallback kept as a safety net). |
| **L-5** test gaps | ✅ Added unknown→404 + **no resource created** regression / unexposed→404 / multi-label exposeLabel OR / env vars on the QUEUED→promotion path / invalid strategy 400. Added S17 (E2E). |

## 2. Design highlights (confirmed concern)

- **Intentional non-equivalence:** "unknown/unexposed → uniform 404" intentionally **replaces** local's "QUEUE and wait" (small-scale scope, existence hiding, no ephemeral pollution, API convention). Anti-re-litigation note in design §6. "exposed but busy → QUEUED" stays transparent equivalence.
- **Local untouched (compatible with multi-label exposeLabel):** "requested label X AND (any exposeLabel)" is satisfied with local's single-label matching (`getResourcesWithLabel`) **unchanged** — the remote layer feeds an exposeLabel-set OR predicate into the canonical **generic `Predicate` seam**. exposeLabel knowledge stays in the remote layer and never enters local's matching logic (design §4-3, anti-re-litigation). The filter runs before count selection so `quantity` unspecified (= all visible matching) is also correct.

## 3. Verification

| Aspect | Result | Evidence |
|---|---|---|
| Unit (full, worktree) | **mvn test 378 / 0 fail / 0 error / 1 skip** (known JENKINS-40787) | `dev/reports/20260614002216-mvn-test.log` |
| E2E (`--clean-start`, all) | **20 scenarios 20/20 PASS** | `dev/reports/20260614004015-e2e-test.md` |
| New E2E | S17 `remote-unknown-rejected` (404 + no ephemeral) | same |
| New/updated units | unknown→404 + not created / unexposed→404 / multi-label exposeLabel OR / promotion-path env vars / invalid strategy 400 | RemoteLockManagerTest, RemoteApiV1ActionTest |

> Note: the first full mvn run had the unrelated local restart test `LockStepWithRestartTest.lockOrderRestart` time out at 180s (182s wall) under build load, but it **passes in 7.4s in isolation** and in 22s on the full re-run — a load-induced flake unrelated to M1E. The final report `20260614002216-mvn-test.log` is 378/0/0 BUILD SUCCESS.

S17 verification: `build result=FAILURE` (fast 404, not a hang) / console shows `HTTP 404` and `UNKNOWN_RESOURCE` / the lock body did not run / **`NOT_CREATED=true` (no ephemeral on the server = H-1 proven)**.

## 4. State

- plugin `feature/...-m1e` HEAD `5d956de` (clean). **No push/PR yet** (after final polishing, awaiting the user).
- Docs (DESIGN/IMPLEMENTATION_STEPS/this, j+e) ready. The E2E spec reflects S17/`m1e-series` (j+e). README index/Status updated. The resolution table was added to `LRR_REVIEW_P1_M1D`.

## Change log

- 2026-06-14: Initial version. M1E (404 admission + multi-label exposeLabel) result summary. mvn 378 / E2E 20/20.
