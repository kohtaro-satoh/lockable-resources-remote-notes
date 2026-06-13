# M1D Result (Remote lock - Phase 1 / M1D)

> **Plugin branch:** `feature/1025-remote-lockable-resources-p1-m1d` (HEAD `819daa0`)
> **Design:** `LRR_DESIGN_P1_M1D.md` / **Steps:** `LRR_IMPLEMENTATION_STEPS_P1_M1D.md`
> **Scope:** True bridging — the server stops re-implementing lock() semantics and delegates to local's canonical path.

---

## 1. What was achieved

**"Per-feature residue" is eliminated structurally.** The server converts a `RemoteLockRequest` into the
same `List<LockableResourcesStruct>` local builds and calls the same `getAvailableResources()`. Exposure is
injected from the outside as a candidate-visibility `Predicate<LockableResource>`.

| Former "true non-equivalence" (M1C residue) | M1D resolution |
|---|---|
| Resource-property env vars | ✅ transparent (`LockStepExecution.buildLockEnvVars` shared by local/remote; `VAR0_<PROP>` reaches the body) |
| Ephemeral auto-creation | ✅ transparent (via `fromNames(create=true)`, gated by `allowEphemeralResources`, identical to local) |
| resourceSelectStrategy | ✅ transparent (canonical `getAvailableResources(…, strategy)` handles it) |

As a side effect, **extra / label / quantity(0=all) / de-duplication** are also canonical now, so
re-implementation drift cannot recur (prevents a repeat of C-1/F-1).

## 2. Architecture (two layers)

- **Bridge layer (transparent equivalence)**: canonical delegation. Removed `resolveRemoteAvailable` /
  `claimSelector` / `validateRemoteSelectors` / `generateLockEnvVars`. Unknown/unexposed → QUEUED
  (local-equivalent). Return values stay transparent via `BodyExecutionCallback.TailCall` Object passthrough.
- **Filter layer (seam)**: `RemoteResourceExposurePolicy` (public `ExtensionPoint`). The default
  `ExposeLabelPolicy` reproduces exposeLabel; third parties add an `@Extension` for
  exposure-restriction/allowlist/authorization. The bridge folds policies into the `Predicate` passed to the
  canonical path.
- The coarse gates (`remoteApiEnabled` / `RemoteUse` permission) remain as the network-control-layer entrance.

**Remaining true non-equivalences (un-bridgeable, retained by design)**: time delay / fail-close /
restart-transient only.

## 3. Verification

| Aspect | Result | Evidence |
|---|---|---|
| Unit (worktree full) | **mvn test 375 / 0 failures / 1 skip** (known JENKINS-40787) | `dev/reports/20260613125351-mvn-test.log` |
| E2E (`--clean-start`, full) | **19 scenarios 19/19 PASS** | `dev/reports/20260613132702-e2e-test.md` |
| New E2E | S16 `remote-resource-properties` (property env var propagation) | same |
| New unit | property env var propagation / exposure-policy hiding | RemoteLockManagerTest |

S16 CP03: `S16RES0_S16_IP` equals the property value (e.g. `10.9.8.37`) → property env vars propagate to the
remote body, proven end-to-end.

## 4. Note (the cost of transparency = inheriting local behaviour)

Canonical delegation also **inherits local's known quirks** (an inevitable consequence of transparent
equivalence):
- A same-label main+extra request (`lock(label:'X', extra:[[label:'X']])`) follows local's
  `getAvailableResources` `isPreReserved` behaviour (it does NOT allocate two distinct resources the way
  M1C's `claimSelector` did). The two M1C-specific dedup tests were removed (no remote-specific behaviour).
- Unknown resource/label → QUEUED, not terminal (like local; resources may appear later).

## 5. Status

- plugin `feature/...-m1d` HEAD `819daa0` (clean). **Not pushed** (after final polishing; awaiting instruction).
- Docs (DESIGN/IMPLEMENTATION_STEPS/this, j+e) in place; E2E spec carries S16/`m1d-series`.

## Change Log

- 2026-06-13: Initial version. Result summary of M1D (true bridging). mvn 375 / E2E 19/19.
