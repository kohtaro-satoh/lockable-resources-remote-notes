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

- [ ] Create the m1d branch (based on m1c, HEAD `2d88834`)
- [ ] `LRR_RESULT_P1_M1C` / `LRR_DESIGN_P1_M1D` / this file (j+e) in place (notes commit)

### Step 1: add a candidateFilter overload to `getAvailableResources`

- Add `getAvailableResources(structs, logger, strategy, Predicate<LockableResource> candidateFilter)`; the
  existing two overloads delegate with `r -> true` (backward-compatible).
- Thread the predicate through `getFreeResourcesWithLabel(...)`, filtering candidates **before** count
  selection (`amount<=0 → all visible candidates`). The name branch rejects invisible names.
- local (`start()`) is unchanged (uses the existing overload).

#### Done criteria
- [ ] Implemented / [ ] `mvn test` green / [ ] committed

### Step 2: RemoteResourceExposurePolicy (ExtensionPoint) + default ExposeLabelPolicy

- `RemoteResourceExposurePolicy extends ExtensionPoint` (`isExposed(resource, request)`).
- `@Extension ExposeLabelPolicy` = current exposeLabel behaviour (exposed iff resource carries exposeLabel).
- A helper that folds all policies into a `Predicate<LockableResource>`.
- The seam ("plug exposure restriction/allowlist/authorization here") is documented (design §4).

#### Done criteria
- [ ] Implemented / [ ] `mvn test` green / [ ] committed

### Step 3: shared buildLockEnvVars (local/remote)

- Extract the inline env-var generation in `proceed()` into `buildLockEnvVars(variable, name→properties)`.
- local `proceed()` calls the extracted function (behaviour unchanged).
- The server calls it on acquire with `name→properties` and returns `lockEnvVars` (incl. properties).
- Remove remote's partial `generateLockEnvVars`.

#### Done criteria
- [ ] Implemented / [ ] `mvn test` green / [ ] committed

### Step 4: route bridge acquire/queue through the canonical path (remove re-implementation)

- `RemoteLockRequest → List<LockableResourcesStruct>` adapter (mirror `getResources()`).
- Immediate acquire and queue promotion both go through `getAvailableResources(structs, strategy, predicate)`.
- Commit via `lockForRemote(available, lockId)`, env vars via `buildLockEnvVars`, keep TailCall.
- Remove: `resolveRemoteAvailable` / `claimSelector` / `validateRemoteSelectors` group / `generateLockEnvVars`.
- Unknown label / non-existent → QUEUED instead of terminal (local-equivalent, §7); explicit denial moves to
  the policy admission.
- RemoteApiV1Action: drop resolution pre-processing; lean on policy admission + canonical delegation.

#### Done criteria
- [ ] Implemented / [ ] `mvn test` green / [ ] committed

### Step 5: tests + full regression

- Unit: remote transparency of property env vars / RANDOM selectStrategy applied remotely / ephemeral
  transparency (allowEphemeralResources) / ExtensionPoint policy (default exposeLabel + `@TestExtension`
  swap) / keep C-1/C-2/F-1 regressions. Revise M1C terminal-based tests to QUEUED expectations.
- Full `mvn test` via `stabilize-build.sh` (worktree).

#### Done criteria
- [ ] Tests in place / [ ] record count & 0 failures / [ ] committed

### Step 6: E2E maintenance + full run

- Follow M1D behaviour in existing scenarios (verify the effect of exposeLabel moving to the filter layer).
- Candidate additions: remote property env var propagation / RANDOM strategy / ephemeral remote (policy-dependent).
- `run-e2e.sh --clean-start` all PASS, save the report.

#### Done criteria
- [ ] E2E maintained / [ ] record all PASS / [ ] notes commit

---

## Test policy (M1D)

1. Full regression via `stabilize-build.sh` (worktree mode).
2. E2E via the latest `run-e2e.sh` **whole suite**, `--clean-start`, saving the report (cycle done-criterion).

## Change Log

- 2026-06-13: Initial version. Implementation-step plan for M1D (true bridging).
