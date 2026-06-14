# M1F Implementation Steps (Remote lock - Phase 1 / M1F)

Progress tracker for M1F (design is `LRR_DESIGN_P1_M1F.md`).
**Triage of the M1E-review findings** — implement only network-bridge transport/boundary hardening (L-b/L-c/L-d).
Lock()-logic-derived gaps (M1E-1 etc.) are intentionally retained per the lens and documented in design §4.

---

## Background

Findings of `LRR_REVIEW_P1_M1E.md` triaged by the user-settled lens "lean on lock()'s existing logic; do not add
remote-specific judgement that is not network-bridge-derived." Implement = L-b/L-c/L-d (bridge hardening). Retain =
M1E-1/M1E-2/M1E-3/L-a/L-e.

---

## Steps

### 0. Preparation

- [x] Create the m1f branch (on top of m1e, HEAD `5d956de`) = `feature/1025-remote-lockable-resources-p1-m1f`
- [x] Prepare `LRR_DESIGN_P1_M1F` / this doc (j+e), update the README index (below)

### Step 1: L-b — scheme validation of the remote base URL

- [x] Add the `isHttpUrl` check to `RemoteConnection.validate()` (non-http(s) → `IllegalArgumentException`).
- [x] Register `RemoteConnection.DescriptorImpl` with `@Extension` and add `doCheckUrl` (`FormValidation`).
- [x] Shared helper `isHttpUrl` (trim + lowercase + `http(s)://` prefix).
- Tests: `RemoteConnectionTest`
  - [x] `testValidateAcceptsHttpsUrl` (accepts https)
  - [x] `testValidateRejectsNonHttpUrl` (rejects `file:` / `ftp:` / no-scheme)
  - [x] `testDoCheckUrl` (http/https=OK, file/empty/null=ERROR)

### Step 2: L-c — POST body size cap

- [x] Add `MAX_BODY_CHARS = 1 MiB` + private `PayloadTooLargeException` (`IOException`) to `RemoteApiV1Action`.
- [x] `parseJsonBody` throws `PayloadTooLargeException` when the cumulative char count exceeds the cap.
- [x] POST handler catches `PayloadTooLargeException` first → **413 `PAYLOAD_TOO_LARGE`** (existing `INVALID_JSON` 400 kept).
- Tests: `RemoteApiV1ActionTest`
  - [x] `acquireWithOversizedBodyReturns413` (>1 MiB body → 413 `PAYLOAD_TOO_LARGE`)

### Step 3: L-d — generalise POST's FAILED → 4xx mapping

- [x] Generalise the `FAILED` branch in POST `/acquire`: `UNKNOWN_*` → 404, anything else → **400 `ACQUIRE_FAILED`** (errorCode preferred).
- [x] Close the 202 fall-through path.
- Defensive change (today `MISSING_TARGET` is unreachable at the boundary). The existing 404 tests (`UNKNOWN_RESOURCE`/`UNKNOWN_LABEL`) regression-cover the generalised branch.

### Step 4: Docs — record the retained concerns

- [x] Record M1E-1 / M1E-2 / M1E-3 / L-a / L-e as "intentionally retained concerns" in design §4 (prevent re-litigation).
- [x] Add an M1F-resolution banner (implemented/retained table) to `LRR_REVIEW_P1_M1E.md` (j+e).
- [x] Update the README review index / Status.

### Step 5: Build, E2E, commit

- [x] `dev/stabilize-build.sh` (worktree, builds the committed HEAD `6319f12`): full mvn pass = **382 / 0 failures / 1 skip**.
  - `dev/reports/20260614104134-mvn-test.log` (BUILD SUCCESS).
- [x] `dev/jenkins-env/run-e2e.sh --clean-start` all pass = **20/20 PASS** (regression over the existing 20 scenarios; no new scenario).
  - `dev/reports/20260614105955-e2e-test.md`.
- [x] plugin commit `6319f12`. Old reports (M1E) deleted, trimmed to the latest one each. notes commit done in this step.

---

## Changed files (plugin)

| File | Change |
|---|---|
| `RemoteConnection.java` | L-b: `validate()` scheme check, `isHttpUrl`, `@Extension DescriptorImpl.doCheckUrl` |
| `actions/RemoteApiV1Action.java` | L-c: `MAX_BODY_CHARS`/`PayloadTooLargeException`/`parseJsonBody` cap + 413 map. L-d: generalise `FAILED`→4xx |
| `RemoteConnectionTest.java` | 3 L-b tests |
| `actions/RemoteApiV1ActionTest.java` | 1 L-c test |

## E2E policy

M1F only hardens the HTTP boundary / transport and changes neither lock() behaviour, transparent equivalence, nor exposure
semantics. **No new E2E scenario is added; keeping the existing 20/20 regression is sufficient** (L-b/L-c/L-d are covered directly by unit tests).
