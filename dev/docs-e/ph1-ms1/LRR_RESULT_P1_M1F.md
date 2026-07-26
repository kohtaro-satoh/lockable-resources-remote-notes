# M1F Result (Remote lock - Phase 1 / M1F)

> **Plugin branch:** `feature/1025-remote-lockable-resources-p1-m1f` (HEAD `6319f12`)
> **Design:** `LRR_DESIGN_P1_M1F.md` / **Steps:** `LRR_IMPLEMENTATION_STEPS_P1_M1F.md` / **Review:** `LRR_REVIEW_P1_M1E.md`
> **Position:** Triage of the M1E-review findings — implement only network-bridge transport/boundary hardening (L-b/L-c/L-d).
>   Lock()-logic-derived gaps (M1E-1 etc.) are intentionally retained per the lens and documented in design §4.

---

## 1. What was achieved

The findings of `LRR_REVIEW_P1_M1E.md` were triaged by the user-settled lens "**lean on lock()'s existing logic; do not add
remote-specific judgement that is not network-bridge-derived**." **Only the three bridge-hardening items were implemented**; the
lock()-logic-derived gaps are retained (documented to prevent re-litigation).

| Finding | Class | M1F action |
|---|---|---|
| **L-b** url scheme unvalidated | bridge hardening | ✅ Done. `RemoteConnection.validate()` rejects non-http(s) (`file:`/`ftp:`/no-scheme) with `IllegalArgumentException`. `DescriptorImpl` becomes an `@Extension` with `doCheckUrl` for live UI validation. Shared `isHttpUrl` |
| **L-c** POST body unbounded | bridge hardening | ✅ Done. `parseJsonBody` cap `MAX_BODY_CHARS=1 MiB`; over-cap → `PayloadTooLargeException` → **413 `PAYLOAD_TOO_LARGE`** (existing `INVALID_JSON` 400 kept) |
| **L-d** FAILED→202 fall-through | bridge hardening | ✅ Done. POST `/acquire` maps `FAILED`: `UNKNOWN_*`→404, otherwise **400 `ACQUIRE_FAILED`**. Closes the 202 fall-through (defensive) |
| **M1E-1** promotion-path `fromNames(create=true)` ephemeral re-creation | lock()-logic-derived | ⏸ **Intentionally retained**. `create=true` is canonical name resolution itself; making remote alone `create=false` is non-bridge remote-specific judgement, against the lens. Narrow, not fail-open, converges to one orphan → accepted. Documented in design §4 |
| **M1E-2** resource+label both set | local-derived, not fail-open | ⏸ Retained (candidateFilter enforces exposure → no bypass) |
| **M1E-3** lease ops no ownership check | by design | ⏸ Retained (P1+ when multi-tenant) |
| **L-a** setRemotes eager save | harmless | ⏸ Retained (atomic via `configure()`'s BulkChange) |
| **L-e** getExposeLabels re-splits | perf only | ⏸ Retained |

> admission (unknown→404) is **kept** as the remote terminal policy. The three implemented items are confined to the HTTP
> boundary / transport and do not touch lock() logic, canonical delegation, or transparent-equivalence semantics (the
> transparent-equivalence behaviour is unchanged from M1E).

## 2. Design points (retained-concern ruling)

- **M1E-1 "won't fix" was settled with the user** (2026-06-14), per the "lean on lock()'s existing logic" lens. `fromNames(create=true)`
  is the same code path as local's on-demand ephemeral feature; treating remote specially violates the lens. The trigger is narrow
  (exposed, busy, admin delete while QUEUED), it is not fail-open, and the orphan converges to one per name. Design §4 records that
  threading a `create` flag through the canonical seam would be revisited only if that lens is ever changed.
- M1E-2 / M1E-3 / L-a / L-e retention rationale is documented in design §2/§4 (prevent re-litigation).

## 3. Verification

| Aspect | Result | Evidence |
|---|---|---|
| Unit (full worktree) | **mvn test 382 / 0 failures / 0 errors / 1 skip** (M1E 378 + 4 new) | `dev/reports/20260614104134-mvn-test.log` |
| E2E (`--clean-start`, all) | **20 scenarios 20/20 PASS** (existing regression maintained; no new scenario) | `dev/reports/20260614105955-e2e-test.md` |
| New unit | L-b: https accepted, file/ftp/no-scheme rejected, `doCheckUrl` (`RemoteConnectionTest` ×3) / L-c: >1 MiB body → 413 (`RemoteApiV1ActionTest` ×1) | same |

> M1F changes only the HTTP boundary / transport and does not alter lock() behaviour, transparent equivalence, or exposure
> semantics, so **no new E2E scenario was added; keeping the existing 20/20 regression is sufficient** (L-b/L-c/L-d are covered directly
> by unit tests). L-d's non-`UNKNOWN_*` branch is unreachable today (the boundary `MISSING_TARGET` check rejects first); the existing
> `UNKNOWN_RESOURCE`/`UNKNOWN_LABEL` 404 tests regression-cover the generalised branch.

## 4. Status

- plugin `feature/...-m1f` HEAD `6319f12` (clean). **Not pushed / no PR** (after final polishing, awaiting the user).
- Docs (DESIGN/IMPLEMENTATION_STEPS/this, j+e) prepared. An M1F-resolution banner was added to `LRR_REVIEW_P1_M1E` (j+e).
  README index / Status / branch list updated.
- Reports trimmed to the latest one each (`20260614104134-mvn-test.log` / `20260614105955-e2e-test.md`).

## Change log

- 2026-06-14: Initial version. Result summary of M1F (bridge hardening L-b/L-c/L-d). mvn 382 / E2E 20/20. M1E-1 intentionally retained.
