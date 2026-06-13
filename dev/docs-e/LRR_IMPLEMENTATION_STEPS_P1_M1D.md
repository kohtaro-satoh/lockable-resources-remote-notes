# M1D Implementation Steps (Remote lock - Phase 1 / M1D)

Progress tracker for M1D (design: `LRR_DESIGN_P1_M1D.md`).
**True bridging** — route the server through lock()'s canonical path so per-feature residue cannot appear.

---

## Background

The three "true non-equivalences" remaining at M1C (`LRR_RESULT_P1_M1C.md`) — property env vars / ephemeral
auto-creation / resourceSelectStrategy — remained per-feature because the server **re-implements** resolution
and env-var generation. M1D removes the re-implementation via canonical delegation + env-var sharing, making
all of them transparent at once. The filter (exposeLabel) is separated into a second layer as an ExtensionPoint.

### Decisions (2026-06-13, with the user)

- The filter seam is a **public `ExtensionPoint` from the start**. Default = exposeLabel.
- The visibility predicate is passed into the canonical resolution via a **backward-compatible overload** of
  `getAvailableResources` (option B = pre-filter is impossible because count selection runs internally).
- The lock() return value stays transparent via `BodyExecutionCallback.TailCall` Object passthrough (do not break TailCall).

---

## Step list

### 0. Preliminaries

- [x] Create the m1d branch (based on m1c, HEAD `2d88834`)
- [x] `LRR_RESULT_P1_M1C` / `LRR_DESIGN_P1_M1D` / this file (j+e) in place (notes `14403df`)

### Step 1: add a candidateFilter overload to `getAvailableResources`

- Add `getAvailableResources(structs, logger, strategy, Predicate<LockableResource> candidateFilter)`; the
  existing two overloads delegate with `r -> true` (backward-compatible).
- Thread the predicate through `getFreeResourcesWithLabel(...)`, filtering candidates **before** count
  selection (`amount<=0 → all visible candidates`). The name branch rejects invisible names.
- local (`start()`) is unchanged (uses the existing overload).

#### Done criteria
- [x] Implemented / [x] `mvn test` green (375 / 0 failures) / [x] committed (plugin `819daa0`)

### Step 2: RemoteResourceExposurePolicy (ExtensionPoint) + default ExposeLabelPolicy

- `RemoteResourceExposurePolicy extends ExtensionPoint` (`isExposed(resource, request)`).
- `@Extension ExposeLabelPolicy` = current exposeLabel behaviour (exposed iff resource carries exposeLabel).
- A helper that folds all policies into a `Predicate<LockableResource>`.
- The seam ("plug exposure restriction/allowlist/authorization here") is documented (design §4).

#### Done criteria
- [x] Implemented / [x] `mvn test` green (375 / 0 failures) / [x] committed (plugin `819daa0`)

### Step 3: shared buildLockEnvVars (local/remote)

- Extract the inline env-var generation in `proceed()` into `buildLockEnvVars(variable, name→properties)`.
- local `proceed()` calls the extracted function (behaviour unchanged).
- The server calls it on acquire with `name→properties` and returns `lockEnvVars` (incl. properties).
- Remove remote's partial `generateLockEnvVars`.

#### Done criteria
- [x] Implemented / [x] `mvn test` green (375 / 0 failures) / [x] committed (plugin `819daa0`)

### Step 4: route bridge acquire/queue through the canonical path (remove re-implementation)

- `RemoteLockRequest → List<LockableResourcesStruct>` adapter (mirror `getResources()`).
- Immediate acquire and queue promotion both go through `getAvailableResources(structs, strategy, predicate)`.
- Commit via `lockForRemote(available, lockId)`, env vars via `buildLockEnvVars`, keep TailCall.
- Remove: `resolveRemoteAvailable` / `claimSelector` / `validateRemoteSelectors` group / `generateLockEnvVars`.
- Unknown label / non-existent → QUEUED instead of terminal (local-equivalent, §7); explicit denial moves to
  the policy admission.
- RemoteApiV1Action: drop resolution pre-processing; lean on policy admission + canonical delegation.

#### Done criteria
- [x] Implemented / [x] `mvn test` green (375 / 0 failures) / [x] committed (plugin `819daa0`)

### Step 5: tests + full regression

- Unit: remote transparency of property env vars / RANDOM selectStrategy applied remotely / ephemeral
  transparency (allowEphemeralResources) / ExtensionPoint policy (default exposeLabel + `@TestExtension`
  swap) / keep C-1/C-2/F-1 regressions. Revise M1C terminal-based tests to QUEUED expectations.
- Full `mvn test` via `stabilize-build.sh` (worktree).

#### Done criteria
- [x] Tests in place (property env var propagation / exposure-policy hiding / unknown→QUEUED /
  same-label main+extra matches local. M1C terminal-based tests revised to QUEUED; the two same-label
  dedup tests were removed to match canonical behaviour)
- [x] `mvn test` **375 / 0 failures / 1 skip** (`dev/reports/20260613125351-mvn-test.log`)
- [x] committed (plugin `819daa0`)

### Step 6: E2E maintenance + full run

- Existing scenarios pass under M1D (no impact from exposeLabel moving to the filter layer).
- Added: **S16 `remote-resource-properties`** (proves property env var `VAR0_<PROP>` propagation, `m1d-series`).
- `run-e2e.sh --clean-start` all PASS, report saved.

#### Done criteria
- [x] E2E maintained (S16 added + run-e2e registered + spec j+e)
- [x] **all 19 PASS 19/19** (`dev/reports/20260613132702-e2e-test.md`; S16 CP03: `S16RES0_S16_IP` = property value)
- [x] notes commit

Note: completed 2026-06-13. mvn 375 / E2E 19/19. Removed the re-implementation of lock() semantics;
delegated to the canonical path + shared env-var generation + a public exposure ExtensionPoint. The three
remaining "true non-equivalences" (property env vars / ephemeral / selectStrategy) are now all transparent
at once (no per-feature implementation).

---

## Test policy (M1D)

1. Full regression via `stabilize-build.sh` (worktree mode).
2. E2E via the latest `run-e2e.sh` **whole suite**, `--clean-start`, saving the report (cycle done-criterion).

## Change Log

- 2026-06-13: Initial version. Implementation-step plan for M1D (true bridging).
- 2026-06-13: All steps complete. mvn 375 / 0 failures, E2E 19/19 PASS (S16 added). plugin `819daa0`.
