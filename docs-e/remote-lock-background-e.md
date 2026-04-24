# Remote Lock — Background and Motivation

> Practice / Draft. This is a learning draft, not a production-ready design.
> It is intended as preparation material before proposing changes to `jenkinsci/lockable-resources-plugin`.

Upstream request: `https://github.com/jenkinsci/lockable-resources-plugin/issues/321`

## 1. Purpose of This Document

- Explain why we want to support `lock()` against resources managed by another Jenkins controller.
- Establish a shared motivation before discussing implementation details.
- Explicitly describe what is out of scope so discussion does not drift.

This document is not the specification itself. It records why the proposal exists and why certain boundaries were chosen. The formal specification should live in the parent Epic and related sub-Epics.

## 2. Starting Point (Request in #321)

Issue #321 in `lockable-resources-plugin` raised the following practical need:

- A single Jenkins instance becomes harder to operate as scale grows.
- Teams want to split workloads across multiple controllers, while still sharing some resources.
  - Example: if a job on controller A is using resource `r1`, a job on controller B must wait until `r1` is released.
- This can also become a building block for higher-availability operations.

In short, the core request is clear: **share lockable resources across multiple Jenkins controllers**.

Comments in #321 also discussed options such as a dedicated "lockable-master / lockable-slave" topology, or multiple master-style redundant setups.

## 3. Proposal Positioning (Why We Avoid Calling It "Federation" for Now)

Early discussion used the phrase "federation support," but that term proved too broad during design refinement.

Why this matters:

- "Federation" often implies much more than remote locking:
  - transparent multi-controller routing
  - replication
  - HA/failover orchestration
- What we actually need first is much narrower: **acquire a lock managed by another controller**.
- Locking is safety-critical. Ambiguous behavior is worse than missing features.

So this proposal intentionally starts with a narrow model:

- **Explicit routing**: caller specifies `serverId: 'Remote1'`.
- **Lightweight scope**: no new cluster manager, consensus, or orchestration subsystem.
- **Safety-first behavior**: when state is uncertain, prefer "do not acquire / do not auto-release."

Broader federation ideas (`serverId: 'any'`, replication, multi-master behavior) are tracked as **future work**, outside this Epic.

## 4. Why Discuss This Now

This need appears repeatedly in small-to-mid Jenkins environments:

- Controllers are split by team, product, or operational ownership.
- Some resources cannot be split:
  - hardware boards
  - lab devices
  - finite external licenses
  - shared staging environments
- Running everything in one large Jenkins is operationally painful, but shared assets remain.

This proposal bridges that gap: **keep Jenkins controllers separated, while sharing selected physical/logical resources safely**.

## 5. Relation to Existing/Similar Solutions

References considered during exploration:

- `node-sharing` / `node-sharing-orchestrator`
  - Focuses on sharing Jenkins agents (nodes) across controllers.
  - Our target is different: we need exclusive control over **LockableResource** entities, not node scheduling itself.
- Multi-master style ideas (for example, super-jenkins patterns)
  - Conceptually related at topology level, but not focused on lock semantics.
- Plugins such as `vra`
  - Useful as references for robust Jenkins-to-REST integration patterns.

The key distinction here is priority: this proposal optimizes for **correct lock semantics** first, and keeps network and failure behavior intentionally constrained.

## 6. Summary of In-Scope vs Out-of-Scope

Detailed scope belongs to the parent Epic. This section summarizes intent.

### In scope (initial)

- `lock(..., serverId: 'Remote1') { body }` for resources managed by a remote controller.
- Pipeline body executes locally; only lock ownership is remote.
- Communication direction is local -> remote only.
- REST + API token authentication.
- Observe state consistently via GET polling.
- Reject unknown resources/labels (no remote auto-create).
- Fail-closed on communication uncertainty (no automatic release).

### Out of scope (future work)

- `serverId: 'any'` and automatic cross-server routing.
- Push notifications from remote -> local.
- Replication, consensus, and HA orchestration.
- Freestyle project support in Phase 1 (Pipeline first).

## 7. Reference Links

- Upstream request: issue #321
- Comments in #321 discussing "lockable-master / lockable-slave" topology
- `node-sharing` plugin
- `vra` plugin REST client patterns
- Parent Epic in this practice repository: remote lockable resources with explicit `serverId` routing
- Companion use-case document: `docs-e/remote-lock-usecase-e.md`
- Design decision notes: `docs-e/remote-lock-design-notes-e.md`

## 8. TODO / Open Questions

- TODO: validate behavior of reference plugins with primary sources (`node-sharing`, etc.).
- Open question: avoid the word "federation" entirely, or keep a narrower term such as "explicit federation"?
- TODO: decide where the upstream-facing English RFC text should live (`docs-e/` in this repo vs direct PR materials).
