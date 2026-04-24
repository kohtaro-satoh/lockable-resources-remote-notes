# Remote Lock — Target Use Cases (Small to Mid-Scale)

> Practice / Draft. This is a learning draft, not a production-ready design.

## 1. Purpose of This Document

- Describe real-world operational scenarios that motivate remote lock support.
- Provide concrete examples to validate design choices when details are debated.
- Show that the proposal is grounded in practical operations, not abstract architecture.

Target scale for this proposal:
- a few to low tens of controllers
- tens to hundreds of shared resources

Very large clusters are intentionally out of scope.

## 2. Shared Assumptions

- Jenkins controllers are separated by team, product, or operational boundaries.
- Each controller owns its own jobs/pipelines.
- Some resources cannot be split and must be shared across those boundaries.
- For each shared resource, one controller can be designated as the management authority (source of truth).

This explicit ownership assumption is why a narrow explicit-remote model is sufficient for Phase 1.

## 3. Use Cases

### UC-1: Shared Hardware Boards / Device Farm

**Situation**

- Team A (embedded) and Team B (QA) run separate Jenkins controllers.
- Hardware boards are limited and physically shared.
- Concurrent access can corrupt measurements or damage hardware.

**Current workaround pain**

- Merging everything into one Jenkins is undesirable.
- Teams fall back to ad-hoc coordination (chat-based locks, custom scripts, etc.).

**Desired behavior**

- QA controller manages board resources (for example, `Remote1`).
- Embedded pipelines acquire locks remotely while still executing locally:

```groovy
lock(resource: 'board-a1', serverId: 'Remote1') {
    sh 'run-hw-test.sh'
}
```

**Safety note**

- For physical assets, fail-closed behavior is mandatory.
- On communication uncertainty, no automatic release.

### UC-2: Finite Commercial Tool Licenses

**Situation**

- A paid tool has a fixed number of licenses.
- Multiple controllers need access.
- Exceeding the count can violate contract terms.

**Desired behavior**

- Licenses are pre-registered as lockable resources/labels on a designated controller.
- Other controllers request locks remotely:

```groovy
lock(label: 'eda-license', serverId: 'LicenseServer') {
    sh 'run-eda-flow.sh'
}
```

**Operational note**

- Unknown resources/labels must be rejected (no remote auto-create).
- `skipIfLocked` remains usable, with final status observed through request polling APIs.

### UC-3: Shared Staging Environment

**Situation**

- Only one staging environment is available for E2E.
- Multiple controllers compete for it.
- Concurrent usage contaminates test outcomes.

**Desired behavior**

- The staging environment is managed by one controller as a lockable resource.
- Other controllers acquire it remotely and run locally.

**Risk note**

- Even if physical damage is unlikely, investigation cost from mixed results is high; strict exclusion is still valuable.

### UC-4: 24/7 Operations and Redundancy (Future Work)

**Situation**

- Teams want maintenance windows without stopping all automation.

**Future direction**

- Multi-controller failover and replicated state would be needed.
- This requires broader architecture (`serverId: 'any'`, replication, HA coordination).
- Explicitly out of scope for this proposal.

### UC-5: Centralized Operational Visibility

**Situation**

- With multiple controllers, operators lose easy visibility into "who is using what now."

**Future direction (Phase 2)**

- Local dashboards may include read-only mirrors of remote resource state.
- Mirror views are for visibility only and must not be lock-decision truth.

## 4. Out-of-Scope / Not Targeted

- Very large clusters (hundreds of controllers, thousands of resources).
- Transparent multi-master with automatic failover.
- Freestyle project support in initial phase (Pipeline first).
- Non-lock orchestration concerns (credential federation, job forwarding, etc.).

## 5. TODO / Open Questions

- TODO: add one concrete pipeline example for each of UC-1 to UC-3.
- Open question: for label-based remote usage in UC-2, finalize pre-registration model and admin workflow.
- TODO: define recommended profiles by use case (poll interval, heartbeat interval, `skipIfLocked` guidance).
