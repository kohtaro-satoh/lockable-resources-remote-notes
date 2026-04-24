# Remote Lock — Design Decision Notes

> Practice / Draft. This is a learning draft, not a production-ready design.

## 1. Purpose of This Document

- Capture the reasoning behind decisions summarized in the parent Epic.
- Preserve decision context so future revisions can be made intentionally.

Decisions may be changed later. The rule is simple: **if a decision changes, record why**.

## 2. Why `serverId` Must Be Explicit

### Decision

- Caller must specify `serverId: 'Remote1'` (or equivalent explicit routing).
- Automatic routing such as `serverId: 'any'` is not part of the initial phase.

### Rationale

- Locking is fundamentally about exclusivity. The lock authority must be unambiguous.
- Automatic routing obscures:
  - which controller owns the lock state
  - where the source of truth lives during failures
- In small/mid-scale environments, operational ownership is usually explicit already, so this complexity is unnecessary initially.

### Future option

- Keep `serverId: 'any'` and failover routing as future work, but only with strict source-of-truth guarantees.

## 3. Why Communication Is Local -> Remote Only

### Decision

- Network direction is one-way: local caller -> remote lock owner.
- No remote-initiated callback to the local controller.
- Liveness is inferred from local heartbeat requests.

### Rationale

- Cleaner firewall posture in enterprise networks.
- Simpler trust model: local side holds credentials and initiates calls.
- Smaller attack surface than bi-directional callback designs.
- More predictable failure behavior.

### Trade-off

- Remote side cannot instantly detect local death via callback loss.
- We accept this and model uncertainty conservatively.

## 4. Why Short Polling Instead of Long Polling

### Decision

- Use short polling (`GET` at fixed intervals) for acquisition progress.
- Do not implement server-held long-poll connections in Phase 1.

### Rationale

- For small/mid-scale use, a few seconds of latency is acceptable.
- Long polling increases server complexity:
  - connection lifecycle management
  - timeout tuning
  - behavior through proxies/load balancers
- Short polling keeps both implementation and review surface smaller.

### Trade-off

- Slightly slower reaction time.
- Potentially higher polling overhead at very large scale (out of current scope).

## 5. Why We Do Not Auto-Release on Timeout (Fail-Closed)

### Decision

- A granted lease is not auto-released due to heartbeat timeout.
- On uncertainty, mark lease as STALE and keep it held.
- Release happens only by:
  - explicit local `POST /release`, or
  - explicit admin action (planned for a later UI phase).

### Rationale

- Many targets are physical devices or finite contractual licenses.
- Incorrect auto-release can cause hardware corruption or license violations.
- We explicitly prioritize safety over availability.

### Trade-off

- Resource may remain blocked until an operator intervenes.
- This is an intentional safety cost, not an implementation bug.

### Future option

- Resource-level opt-in auto-release for low-risk software-only resources (not in initial phase).

## 6. Why We Still Use the Term "Lease" Without Auto-Expiry

### Decision

- Keep `leaseId` as the ownership handle.
- Do not interpret lease as automatic expiry/release in Phase 1.

### Rationale

- Heartbeat and release operations need a stable ownership token.
- `leaseId` is used as a capability handle, not as a timer-based auto-release contract.

### Documentation requirement

- Whenever lease terminology is introduced, explicitly state that timeout does not auto-release.

## 7. Why HTTP Methods Are Strictly Separated

### Decision

- `GET` for read-only operations.
- `POST` for state transitions.
- Do not encode state-changing operations in `GET`.

### Rationale

- GET can be retried or prefetched by intermediaries.
- Side effects on GET can cause severe safety issues (for example, accidental duplicate release).
- Query strings are often logged, so capability tokens should not be exposed there.
- This aligns with common OSS API review expectations.

### Note on CSRF concerns

- API token + non-browser API usage generally avoids practical crumb friction.
- "Use GET everywhere to avoid CSRF" is not acceptable for lock state transitions.

## 8. Why `POST /acquire` Returns Only `requestId`

### Decision

- `POST /acquire` returns `{requestId}` only.
- Status (`ACQUIRED`, `SKIPPED`, `FAILED`, etc.) is always retrieved via `GET /acquire/{requestId}`.
- Unknown resource/label requests are rejected immediately with 4xx.

### Rationale

- Keeps the client loop uniform:

```text
POST /acquire -> loop: GET /acquire/{requestId}
```

- Avoids mixed semantics where POST responses change meaning by option combinations.
- Keeps mutation and observation concerns separated.

### Trade-off

- `skipIfLocked` may require one extra round trip.
- Under short-poll architecture, this cost is acceptable.

## 9. Why Remote Ephemeral Resource Creation Is Prohibited

### Decision

- Remote API must reject unknown resource/label acquisition attempts.
- No remote-side auto-create behavior.

### Rationale

- Remote lock owner should manage only intentionally declared resources.
- Allowing auto-create can introduce:
  - ghost resources from typos
  - broken license accounting assumptions
  - reduced auditability
- Explicit routing + explicit resource registration is safer.

### Trade-off

- Pipeline authors need remote-side pre-registration workflows.
- This is considered healthy operational discipline.

## 10. Security and Authentication Direction

### Decision

- Use Jenkins standard authentication model on remote side.
- Local side references service credentials via `credentialsId`.
- API endpoints enforce permission checks.

### Open points

- Reuse existing lockable-resources permissions vs introduce remote-specific permissions.
- Confirm crumb behavior in final implementation context.

## 11. UI and Observability Direction (Bridge to Phase 3)

### Current agreement

- Lease listing, STALE highlighting, and manual release UI belong to Phase 3.
- Phase 1 provides minimum observability through logs and diagnostic API.
- Phase 2 may provide read-only remote resource mirror views.
- Mirror views must never be used as lock-decision truth.

### Open points

- Whether local UI should merge remote rows or separate them into dedicated sections.
- Source labeling and STALE display conventions.

## 12. Glossary (v1)

- **local controller**: Jenkins instance that executes `lock(..., serverId: 'Remote1')`.
- **remote controller**: Jenkins instance referenced by `serverId`, owning lock truth.
- **requestId**: handle returned by `POST /acquire` to observe wait/progress.
- **leaseId**: ownership handle for heartbeat/release operations.
- **STALE**: lease state where heartbeat is missing; not equivalent to released.

## 13. TODO / Open Questions

- TODO: map decisions to upstream precedents where possible (core Jenkins and other plugins).
- Open question: timing for introducing `maxWaitSeconds` and `EXPIRED` semantics.
- Open question: whether to add opt-in auto-release for low-risk resource classes in later phases.
- TODO: decide whether to reframe this document as ADR records once implementation starts.
