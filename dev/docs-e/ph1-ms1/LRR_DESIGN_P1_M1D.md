# Remote Lockable Resources Specification (Phase 1 / M1D)

> **Source:** [jenkinsci/lockable-resources-plugin #1025](https://github.com/jenkinsci/lockable-resources-plugin/issues/1025)
> **Prerequisites:** `LRR_DESIGN_P1_M1C.md` (M1C spec) / `LRR_RESULT_P1_M1C.md` (M1C result)
> **Scope:** Phase 1 M1D (**true bridging** — transparent equivalence of lock() over the network)

---

## Table of Contents

1. [Design philosophy (why per-feature residue kept appearing)](#1-design-philosophy-why-per-feature-residue-kept-appearing)
2. [Two-layer architecture](#2-two-layer-architecture)
3. [Bridge layer: delegate to the canonical path](#3-bridge-layer-delegate-to-the-canonical-path)
4. [Filter layer: RemoteResourceExposurePolicy (ExtensionPoint)](#4-filter-layer-remoteresourceexposurepolicy-extensionpoint)
5. [Return-value / exception transparency](#5-return-value--exception-transparency)
6. [Code removed / retained](#6-code-removed--retained)
7. [True non-equivalences (un-bridgeable)](#7-true-non-equivalences-un-bridgeable)
8. [Scope](#8-scope)

---

## 1. Design philosophy (why per-feature residue kept appearing)

Across M1A→M1B→M1C, `extra`/`label` bugs recurred despite being "fixed" (C-1, F-1). The root cause is
that **the server re-implements lock() resolution and env-var generation**:

```text
Current (through M1C):
  client serializes the lock args to JSON → the server parses it and re-derives
    "which resources, how many" and "how to build env vars" in
    RemoteLockManager / claimSelector / generateLockEnvVars
  ⇒ each semantic dimension (extra / label / quantity / properties / selectStrategy /
     ephemeral) is implemented separately and can drift independently
```

local lock() has no "per-feature residue" because it goes through a **single canonical path**:

```text
local LockStepExecution.start():
  step.getResources()                    → List<LockableResourcesStruct> (main + each extra)
  → getAvailableResources(structs, strategy)   ← the one source of truth (label/quantity(0=all)/extra/selectStrategy)
  → lock(available, build)
  → proceed(name→properties map)               ← the one source of truth for env vars (VAR / VAR0 / VAR0_<PROP>)
```

**M1D approach:** route the server through the same canonical path. Stop re-implementing, and per-feature
residue **cannot appear by construction**.
> Except for "time delay", "fail-close on network failure", and "restart-transient state", the remote
> feature is transparently equivalent to local. M1D removes the remaining semantic differences.

## 2. Two-layer architecture

Filtering (exposure / authorization) is a layer **outside** the bridge. The bridge is **fully transparent
within the exposed surface** defined by the filter.

```text
┌─ Access-policy layer (remote-specific; outside the network-control layer)
│    RemoteResourceExposurePolicy (ExtensionPoint, §4). Default = exposeLabel.
│    Supplies "which resources are visible to remote clients" as a Predicate<LockableResource>.
│    Future: exposure restriction / per-client allowlist / authorization plug in here.
│      ↓ Predicate<LockableResource> visible
├─ Network-control layer (bridge) = transparent equivalence of lock(). Completed in M1D.
│    Resolves identically to local within the visible surface (§3). No re-implementation of lock() semantics.
│    Existing coarse gates (remoteApiEnabled = bridge on/off, RemoteUse permission = caller auth) stay at the entrance.
└─ True non-equivalences (un-bridgeable, §7) = time delay / fail-close / restart-transient only.
```

"Transparent equivalence" need only hold **within the visible surface**. exposeLabel is a remote-specific
concept absent from local lock(), so it belongs in the filter layer, not hardcoded into the bridge (where it
leaked through M1C).

## 3. Bridge layer: delegate to the canonical path

### 3-1. Resolution: delegate to `getAvailableResources`

Convert `RemoteLockRequest` into `List<LockableResourcesStruct>` (mirroring `LockStep.getResources()`) and
call **the same** `getAvailableResources` local uses. Visibility is passed as a predicate:

```text
getAvailableResources(structs, logger, selectStrategy, Predicate<LockableResource> candidateFilter)
  ├ label struct: getFreeResourcesWithLabel(...) filters candidates by candidateFilter
  │    then selects amount (amount<=0 → all visible matching = "0 = all")
  └ name struct: fromNames(names, create=true) (ephemeral gated transparently by allowEphemeralResources)
                  names not passing candidateFilter are invisible → not acquirable
```

This single call makes **extra / label / quantity(0=all) / resourceSelectStrategy / de-dup / ephemeral** all
canonical (no per-feature code). Availability uses the existing `isFree()` (and `isLocked()` already includes
`remoteLockedBy`), so existing remote locks are respected — no double-locking.

**Core change is an additive, backward-compatible overload only:** add a `Predicate<LockableResource>`
variant to `getAvailableResources(...)` / `getFreeResourcesWithLabel(...)`; the existing ones delegate with
`r -> true`. local is untouched.

### 3-2. Env vars: share the generator with local

Extract the inline env-var generation in `proceed()` into a shared function so **local and remote call the
same function**:

```text
buildLockEnvVars(variable, LinkedHashMap<resourceName, List<LockableResourceProperty>>)
  → { VAR: "r1,r2", VAR0: "r1", VAR0_<PROP>: <value>, VAR1: "r2", ... }
```

On acquire, the server calls it with the `name→properties` map (from the `LockableResource` objects it
holds) and returns the result as `lockEnvVars`. Properties are name/value strings → serializable → fully
bridgeable. → **resource-property env vars become transparent**; remote's partial `generateLockEnvVars` is removed.

### 3-3. Queue converges too

A remote queue entry also carries `List<LockableResourcesStruct>` and uses
`getAvailableResources(structs, candidateFilter)` for promotion checks — identical in shape to local's
`getNextQueuedContextEntry`→`getAvailableResources(entry.getResources())`. The remote-specific
`resolveRemoteAvailable` is removed.

## 4. Filter layer: RemoteResourceExposurePolicy (ExtensionPoint)

Exposure decisions are separated and exposed as a Jenkins `ExtensionPoint`:

```java
@Restricted(Beta.class) // SPI
public interface RemoteResourceExposurePolicy extends ExtensionPoint {
    /** Whether resource is visible to the remote client in the context of this request. */
    boolean isExposed(LockableResource resource, RemoteLockRequest request /*, Authentication caller*/);
}
```

- The bridge folds all `@Extension`s into a `Predicate<LockableResource>` and passes it to the core (§3-1).
- **Default `ExposeLabelPolicy` (`@Extension`)** = current exposeLabel behaviour (exposed iff the resource
  carries exposeLabel). → works as before by default.
- Third parties add an `@Extension` to swap/extend exposure-restriction/allowlist/authorization.
  **This shows in both code and docs that the filtering mechanism is prepared, for the eventual PR.**
- The policy method is context-rich (resource + request + future caller); the bridge folds it into a
  `Predicate<LockableResource>`. The core sees only a simple predicate (separation of concerns).
- Tests can inject any policy via `@TestExtension`.

> Note: `remoteApiEnabled` (whole-server on/off) and the `RemoteUse` permission (caller auth) stay as the
> **entrance gates of the network-control layer** (not per-resource resolution filters).

## 5. Return-value / exception transparency

- **lock() return value**: in the remote flow the **step itself runs client-side**, and so does the body.
  The body's result is passed through automatically as an `Object` by `BodyExecutionCallback.TailCall`
  (same as local's `Callback`). → **Even if lock() later returns a boolean/string/any Object, the bridge
  stays transparent without doing anything.** M1D must only avoid breaking TailCall (no `onSuccess(null)`
  swallowing).
- **Exceptions**: server-side errors map to error codes and are restored client-side to the matching
  exception (AbortException, etc.). Fail-close (comms failure) holds and fails per §7.

## 6. Code removed / retained

| Removed (re-implemented lock() semantics) | Replaced by (canonical / shared) |
|---|---|
| `LRM.resolveRemoteAvailable` / `claimSelector` | `getAvailableResources(structs, candidateFilter)` |
| `LRM.validateRemoteSelectors` / `validateSelector` / `hasExposedCandidate` | filter layer (policy) + canonical satisfiability (shortfall → QUEUED, like local) |
| `RemoteLockManager.generateLockEnvVars` | shared `buildLockEnvVars` (identical to local) |
| `RemoteLockManager.tryAcquireRecord` custom branches | request→structs adapter + canonical call |

**Retained (genuinely remote-specific):** transport (HTTP/wire), fault tolerance
(poll/heartbeat/onResume + retry budget), lock representation (`remoteLockedBy` / `RemoteLockRecord` /
STALE / QUEUE_EXPIRED), filter layer (policy), admin Force Release. These are network/operational concerns,
not lock() semantics.

## 7. True non-equivalences (un-bridgeable)

Network-induced constraints that remain even in a pure bridge (already stated in M1B §1):

- **Time delay** (round-trip latency).
- **Fail-close on network failure** (a dead link can't be bridged; locks are not auto-released).
- **Restart semantics** (a server restart loses the transient `remoteLockedBy`).

Everything else becomes transparent in M1D. **Unknown labels / non-existent resources also follow local:**
local queues an unsatisfiable request (resources may be added later, M1B §5); remote queues likewise, and
M1C's synchronous `UNKNOWN_RESOURCE`/`UNKNOWN_LABEL` terminal is reorganized into the filter layer's
admission (explicit denial).

## 8. Scope

### Included (M1D)

| Item | Content |
|---|---|
| Canonical resolution delegation | `getAvailableResources(structs, strategy, candidateFilter)`: extra/label/quantity(0=all)/selectStrategy/de-dup/ephemeral all transparent |
| Env-var sharing | `buildLockEnvVars` (incl. property env vars) shared by local/remote |
| Filter ExtensionPoint | `RemoteResourceExposurePolicy` (default = exposeLabel) made public; seam documented in code/docs |
| Return-value transparency | keep TailCall (body Object result passthrough) |
| Queue convergence | remote queue also uses canonical satisfiability |

### Excluded (out of M1D scope)

| Item | Note |
|---|---|
| M-1 onResume displayTarget degradation | display-only; deferred (needs resource-name persistence) |
| Richer filter implementations (allowlist, etc.) | seam only; implementation later (P1+) |
| True non-equivalences (§7) | retained as design constraints |

## Change Log

- 2026-06-13: Initial version. Defines M1D (true bridging): delegate resolution to the canonical path, share
  env-var generation with local, and separate exposure into `RemoteResourceExposurePolicy` (ExtensionPoint,
  default exposeLabel). Return values stay transparent via TailCall Object passthrough.
