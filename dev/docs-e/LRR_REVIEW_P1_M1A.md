# Remote LR Development — Full Review (as of Phase 1 / M1A)

> **Review date:** 2026-06-11
> **Plugin branch under review:** `feature/1025-remote-lockable-resources-p1-m1a` (HEAD: `c782c28`, through M1A Step 5, 347 tests passing)
> **Documents under review:** `docs-j/` (background / usecase / design-notes), `dev/docs-j/` (LRR_DESIGN / IMPLEMENTATION_STEPS / E2E_TEST_SPECIFICATION for P1_M1 and P1_M1A)
> **Perspective:** A bird's-eye evaluation covering not only code but also specs, use cases, and process

---

## Resolution Status in M1B (added 2026-06-12)

M1B (`LRR_DESIGN_P1_M1B.md`) was executed in response to this review. Current
status of each finding:

| Finding | Status in M1B |
|---|---|
| 3-1 extra dropped | ✅ Resolved (fully implemented; proven by E2E S10) |
| 3-2 lockEnvVars not equivalent | ✅ Resolved (comma join; property env vars declared "unsupported") |
| 3-3 restart semantics | ✅ Documented as a known constraint (transient is by design; operational assumption stated) |
| 3-4 missing onResume | ✅ Resolved |
| 3-5 no STALE release path | ✅ Resolved (Force Release UI; proven by E2E S13) |
| 4-1 instant death on one failure | ✅ Resolved (poll retry budget + heartbeat warn-and-continue; proven by E2E S11. BodyExecution retention made unnecessary by adopting option B) |
| 4-2 queue semantics divergence | ✅ Resolved (unified LRM queue bridge; proven by E2E S12) |
| 4-3 local waiters not woken | ✅ Resolved (automatic with the unified queue) |
| 4-4 no TTL on QUEUED | ⏳ Open (post-M1B work) |
| 4-5 release/tick race | ✅ Structurally eliminated (tick promotion removed; queue operations unified under syncResources) |
| 4-6 unsatisfiable requests stay QUEUED forever | △ Partially resolved (with a timeout set, FAILED via LOCK_WAIT_TIMEOUT; without one, unchanged) |
| 5-1 permission model | ⏳ Open (must be addressed before an upstream PR) |
| 5-2 anonymous requests | ✅ Re-decided as intended behavior (empty credentialsId = legitimate use case for no-auth servers; M1B decision 1-c) |
| Drift #3 exposeLabel Javadoc | ✅ Resolved |
| Drift #4 forcedServerId validation | ⏳ Open (M1B Step 1-d was planned only; carried over) |
| Drift #10 empty README | ✅ Resolved (indexed README in place) |

---

## Table of Contents

1. [Overall Assessment](#1-overall-assessment)
2. [Strengths](#2-strengths)
3. [Critical Issues (must fix before push/PR)](#3-critical-issues-must-fix-before-pushpr)
4. [Robustness / Semantics Issues (high priority)](#4-robustness--semantics-issues-high-priority)
5. [Security](#5-security)
6. [Spec ⇔ Implementation Drift List](#6-spec--implementation-drift-list)
7. [Use-Case Perspective](#7-use-case-perspective)
8. [Recommended Actions (in priority order)](#8-recommended-actions-in-priority-order)

---

## 1. Overall Assessment

**The process and documentation system are exceptionally strong for an OSS
proposal effort. The code, however, contains multiple serious inconsistencies
that violate the project's own core principles — "fail-closed" and "transparent
equivalence" — and must be fixed before push/PR.**

In particular, these two points fail M1A's very goal:

- `extra` silently dropped (the body runs under a partial lock)
- `lockEnvVars` not equivalent (local joins with commas, remote with spaces)

A process gap was also found: some tests recorded as "complete" in the
implementation-steps document do not exist
([§6 drift table #5](#6-spec--implementation-drift-list)).

The "what to build and why" work is strong enough to stand up to the upstream
proposal, but **the verification layer — cross-checking spec ⇔ implementation ⇔
test records — has holes, and serious bugs have accumulated there.**

---

## 2. Strengths

### Exemplary documentation layering

- `docs-j/remote-lock-background-j.md` (why)
  → `docs-j/remote-lock-usecase-j.md` (for whom)
  → `docs-j/remote-lock-design-notes-j.md` (decision log)
  → `dev/docs-j/LRR_DESIGN_P1_M1*.md` (what to build)

  This separation is a strong foundation for persuading upstream.
- The design-notes policy of "leave a reason when overturning a decision", the
  deliberate avoidance of the word "federation" for scope control, and the
  rationale in §7 (GET/POST usage) and §9 (ephemeral ban) are of a quality that
  can withstand upstream maintainer review.

### Consistent scope control and safe-side design

The four pillars — explicit routing, one-way communication, short-polling, and
no automatic release — derive directly from the use cases (UC-1's physical board
damage avoidance), keeping the reasoning traceable.

### Implementation process discipline

- One step = one commit, with commit hashes, test counts, and dates recorded per step
- Operationalized isolated worktree builds (stabilize-build.sh)
- A 12-scenario E2E harness (3-controller docker setup) with saved run reports

Unusual traceability for solo development.

---

## 3. Critical Issues (must fix before push/PR)

### 3-1. `extra` silently dropped server-side (violates the exclusivity guarantee) [Critical]

- The client includes `extra` in the JSON via `RemoteLockRequest.from(step)`
  (`buildLockRequestJson()` in `remote/RemoteApiClient.java`, around lines 110–120).
- But the server's `actions/RemoteApiV1Action.java:158` does not parse `extra`
  and constructs the `RemoteLockRequest` with a **hard-coded `null`**.
- As a result, `lock(resource: 'r1', extra: [...], serverId: 'b')` **locks only
  r1, returns ACQUIRED, and the body runs believing the extras are locked too**.
- From the UC-1 (HW damage) perspective, this is the worst kind of silent partial lock.
- No client-side guard either (`LockStepExecution.resolveRemoteDisplayTarget()`
  actually tolerates extra-only requests).
- `RemoteLockManager.tryAcquireAll()` is dead code unreachable via HTTP.
- **Zero tests for `extra` across the entire suite** (neither unit nor HTTP layer).

**Minimal fix:** Within M1A scope, explicitly reject "extra + remote" with 400.
Also reject client-side with an AbortException.

### 3-2. lockEnvVars is not equivalent to local `lock()` [Critical]

- Local joins with **commas**: `LockStepExecution.java:578`
  `String.join(",", lockedResources.keySet())`
- Remote joins with **spaces**: `remote/RemoteLockManager.java:297`
  `String.join(" ", names)`
- `LRR_DESIGN_P1_M1A.md` itself writes `"resource1 resource2"` (spaces) —
  evidence that **the spec was written without checking the local implementation**.
- Local additionally injects resource-property env vars (`VAR0_<PROP>`), which
  remote lacks.
- With "transparent equivalence" as M1A's central goal, this is a double drift:
  spec bug + implementation bug.

### 3-3. Restart breaks fail-closed (not documented in the design) [Critical]

- `LockableResource.remoteLockedBy` is **transient**; a restart of the remote
  (B) Jenkins erases all remote locks.
- Client A's body keeps running while others can acquire the same resource on B
  — **a mutual-exclusion violation**, in direct conflict with the "no automatic
  release" principle.
- Neither the M1/M1A designs nor the design-notes mention restart semantics.
- Either persist it, or at minimum document it as a "known Phase 1 constraint"
  with operational mitigations.

### 3-4. No client-side `onResume()` [Critical]

- Polling/heartbeat tasks are transient `ScheduledFuture`s and are not re-armed
  after a local (A) restart.
- **A restart while QUEUED hangs the step forever.**
- A restart while ACQUIRED stops heartbeats, unjustly marking the lease STALE on B.
- The local flow is protected by persistence + resume; the remote flow lacks any
  resume design at all.

### 3-5. No admin path to release STALE locks [Critical (operational)]

- The design-notes say release happens only via explicit release or manual admin
  release, delegating STALE recovery to admins — yet the only code path that can
  clear `remoteLockedBy` is `RemoteLockManager.release()` (i.e. the remote
  client's API call).
- Not only is the Phase-3 manual UI missing — there is no interim API/CLI path
  either, leaving "restart Jenkins" as effectively the only recovery (and per
  3-3, a restart erases all locks).
- Fail-closed design presupposes "someone can notice and manually release", so
  even a minimal admin release path should be part of M1A.

---

## 4. Robustness / Semantics Issues (high priority)

### 4-1. A single communication failure kills the build immediately

- Both poll and heartbeat go straight to `finishRemoteFailure()` on one exception.
- The server tolerates 6 missed heartbeats (60s); the client tolerates zero.
- A multi-hour HW test (UC-1) dies from a 5-second network blip.
- A retry budget is needed (e.g. retry up to the STALE threshold).
- Additionally, since no `BodyExecution` is retained, the body cannot be
  cancelled on failure during execution; post-`onFailure` behavior is undefined.

### 4-2. Queue semantics diverge from local

- QUEUED record retries follow `ConcurrentHashMap` iteration order (effectively
  random) — not even FIFO.
- `priority` / `inversePrecedence` / `timeoutForAllocateResource` ride the wire
  but are **all unimplemented** (the EXPIRED state in the diagram is unreachable).
- Contrary to the M1A design's claim that "queue control and timeout decisions
  are delegated to the remote side's traditional lock policy", the implementation
  bypasses that policy with a simplistic concurrent algorithm.
- Either narrow the document's claim to match the implementation, or integrate
  into the traditional queue.

### 4-3. A remote release does not wake local waiters

- `RemoteLockManager.release()` calls neither `proceedNextContext()` nor
  `refreshQueue()`, so local pipelines waiting on that resource on B sit idle
  until the 15-second safety net (`LockWaitTimeoutPeriodicWork`).
- Combined with the opposite direction (local unlock → remote waiters get a
  1-second tick), fairness breaks down in mixed environments.

### 4-4. QUEUED records of dead clients can grab resources later

- With no TTL or liveness check on QUEUED, records survive client death and
  acquire the moment a resource frees up → nobody heartbeats → STALE blockage.
- Using GET polling itself as the liveness signal (expire QUEUED entries not
  polled for a while) is the natural fix.

### 4-5. Race between release and the tick (orphan locks)

- `release()` of a QUEUED record removes from the map outside `syncResources`,
  so if the tick thread concurrently promotes it to ACQUIRED, the
  **`remoteLockedBy` is orphaned with no record** (unrecoverable except restart).
- The promotion path needs a re-check (is the record still in the map).

### 4-6. label + quantity exceeding the total stays QUEUED forever

- An unsatisfiable request falls into neither FAILED nor EXPIRED.

---

## 5. Security

### 5-1. All endpoints gated only by `Jenkins.READ`

- With mere READ permission, acquire/heartbeat/release are all possible; the
  lockId (UUID) is the only barrier.
- The "Lock-permission-equivalent check" promised by design-notes §10 is unimplemented.
- This will be the first thing flagged in upstream review. A dedicated
  Permission, or binding to the plugin's existing permissions, is recommended.

### 5-2. Anonymous requests sent when credentialsId is unset

- `LRR_DESIGN_P1_M1.md` explicitly says "missing credentials are fail-closed
  (build failure)", but the implementation
  (`LockStepExecution.resolveAuthorizationHeader()`) returns an empty string and
  **sends without an Authorization header**.
- On remotes permitting anonymous READ this goes through unauthenticated,
  contradicting the spec.

---

## 6. Spec ⇔ Implementation Drift List

| # | Content | Severity |
|---|---|---|
| 1 | M1 design: "pre-registration required, no auto-creation" ⇔ M1A design: "delegate to remote-side policy". The implementation does not auto-create, but design-notes §9's core guarantee disappeared from the M1A document | Medium |
| 2 | The DSL resolution pseudocode in M1A §3 lacks the `forcedServerId` branch (inconsistent with §2/§6 and the implementation) | Low |
| 3 | The `exposeLabel` Javadoc in `LockableResourcesManager.java` — "empty means all resources are exposed" — is **the exact opposite of actual behavior** (opt-in; empty = nothing exposed) | Medium (dangerous comment) |
| 4 | `forcedServerId` save-time validation (remotes key existence): recorded "complete" in design and implementation-steps docs but **unimplemented** (`configure()` is a bare bindJSON) | Medium |
| 5 | The "resource + extra test" and "forcedServerId config round-trip test" recorded by implementation-steps Steps 2/5 **do not exist in the test code** (zero `extra` tests overall; forcedServerId tests only in LockStepRemoteTest) | Medium (process) |
| 6 | Error code on label mismatch: E2E spec says `UNKNOWN_RESOURCE`, implementation returns `UNKNOWN_LABEL`. Also asymmetric paths: resource → immediate 404, label → 202+FAILED (undocumented) | Low |
| 7 | The `message` field in GET responses: recorded as "to be added in Step 3", unimplemented (the client parses it but it is always null) | Low |
| 8 | Auto-trim of leading/trailing spaces in `serverId` (stated in the design): unimplemented | Low |
| 9 | `step.validate()` fully skipped for remote: DSL rejected locally (e.g. `resource`+`label` together) silently passes remotely (resource wins, label ignored) — contrary to transparent equivalence | Medium |
| 10 | The notes repository `README.md` is empty — no entry point into a high-quality document set | Low |

Supplementary (spec addendum suffices):

- The `POST /acquire` response now includes `state` (the design says `lockId`
  only). Additive and harmless, but should be documented.

---

## 7. Use-Case Perspective

- UC-1 (HW boards) and UC-2 (licenses) are the sources of the safety
  requirements, and 3-1 (extra dropped), 3-3 (restart), 3-5 (STALE unrecoverable)
  **all strike these two UCs directly**.
- 4-1 (instant failure on a blip) leaves the lock held while only the build
  dies — for UC-1 this is the worst combination: "the test failed AND the board
  stays blocked".
- UC-2 (licenses) depends on quantity semantics and fairness, where 4-2 / 4-6
  are relevant.

### E2E coverage gaps

The E2E covers 12 scenarios of happy path + fail-closed, but **the scenarios
that most exercise the design philosophy are missing**:

- Lock retention while the remote (B) restarts
- Recovery from a client (A) restart
- Network partition during body execution (both blips and long outages)

These are exactly what substantiates M1A's safety claims — top candidates for
E2E expansion.

---

## 8. Recommended Actions (in priority order)

1. **Explicitly reject `extra` + remote with 400** (close the accident path
   before implementing it properly), plus a client-side AbortException
2. **Match the lockEnvVars separator to local** (comma).
   Make the property-env-var stance explicit in the design (implement if
   included; declare "unsupported" if not)
3. **Implement `onResume()`** (re-arm poll/heartbeat tasks; fix the QUEUED hang)
4. **Add a minimal admin release path for remote locks** (secure a STALE recovery means)
5. **Document restart semantics in the design**
   (why transient was chosen, its limits, future persistence policy)
6. Introduce a **retry budget** for poll/heartbeat, and retain `BodyExecution`
   to interrupt the body on failure
7. Fix drift table #3 and #4 (dangerous Javadoc and unimplemented validation),
   and reconcile the implementation-steps "complete" records against the actual tests
8. Before an upstream PR, address the **permission model** (READ → dedicated
   permission) and make anonymous sending fail-closed

---

## Revision History

- 2026-06-11: Initial version. Full review as of M1A Step 5 completion (plugin `c782c28`).
- 2026-06-12: English translation added (docs-e sync).
