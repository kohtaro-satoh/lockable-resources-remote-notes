# LRR-ISSUE (P1M1H): acquire polling 404s after the QUEUED record expires, so a legitimate allocation timeout surfaces as a "communication failure"

| Item | Content |
|---|---|
| ID | LRR-ISSUE-P1M1H-queued-expiry-poll-404 |
| Severity | **Correctness = low** (nothing breaks; fail-closed is preserved) / **diagnosability & operability = medium** (invites misdiagnosis) |
| Type | **Logic bug**: the terminal-record TTL is measured from the wrong instant (`enqueuedAt`). Initially misdiagnosed as a "client/server timeout race"; corrected to the confirmed root cause after reading the code (2026-06-22) |
| Status | **Fixed in the M1I cycle** (plugin `e231367`; regression guarded by E2E S18). Design / steps / result: `LRR_DESIGN_P1_M1I.md` / `LRR_IMPLEMENTATION_STEPS_P1_M1I.md` / `LRR_RESULT_P1_M1I.md` |
| Trigger | Deterministic whenever **`timeoutForAllocateResource > TERMINAL_TTL_MS (=120s)`** (independent of load) |
| Milestone | Derived from P1M1H (a side effect of B2 = #52, "fold QUEUED expiry onto the queue timeout") |
| Found by | Load suite G01 `grid-storm`, `stress` preset (hold 60s, 200 concurrent, timeout = 3 min). The root cause, however, is **load-independent** and reproducible with a single E2E using timeout > 120s (see "Detectability") |
| Found on | 2026-06-22 |

---

## 1. Summary

When a remote acquire fails because the queue wait is exhausted, it should fail closed with an explicit
`LOCK_WAIT_TIMEOUT`. Instead, **when `timeoutForAllocateResource > 120s` the server cannot retain the
FAILED record and deletes it immediately**, so the client's status polling receives a 404 and fails
closed as "server may have restarted / communication failure". Both paths fail closed (the body never
runs, consistency holds) so **nothing breaks**, but a legitimate timeout is mislabelled as a transport
failure.

- **Path A (clean; the intended behaviour)**: the client's poll hits while the FAILED record still
  exists and receives `state=FAILED, errorCode=LOCK_WAIT_TIMEOUT` — explicitly "the lock wait timed out".
- **Path B (the bug)**: the FAILED record is deleted immediately, the client's
  `GET /acquire/{lockId}` returns **HTTP 404 LOCK_NOT_FOUND**, and a `RemoteApiException`
  ("server may have restarted") fails the build closed. **A legitimate allocation timeout is
  mislabelled as a communication failure.**

Measured (stress, timeout = 3 min > 120s): of 9 failures, **6 were B and 3 were A**. B dominates because
the TTL bug in §5 collapses the FAILED window to zero. The remaining 3 A cases are polls that landed in
the gap between `markFailed` and the next sweep. **Only that A/B split is timing-dependent; the primary
cause is a deterministic TTL bug, not a race.**

---

## 2. Impact

- **Correctness holds** (important): 0 mutual-exclusion violations, 0 deadlocks/HUNG, 0 lock bodies
  executed on failed jobs. The fail-closed design works as intended; no double acquisition and no
  phantom locks. **The requirement "remote LR does not break under load" is met.**
- **Rough edges in diagnosability and operability**: in path B the log and the exception read
  `Remote API communication failure: GET /acquire/{id}` even though the only thing that happened is
  "the queue wait timed out". Operators are likely to **misdiagnose it as a network or infrastructure
  failure**.
- **Inconsistent signal**: the same "allocation timeout" **looks like two different things** —
  A (`LOCK_WAIT_TIMEOUT`) versus B (404 → communication failure). That misleads retry policy, alert
  classification and SLO accounting.

---

## 3. Reproduction environment and conditions

- Harness: `dev/jenkins-env/run-load.sh --preset stress` (= 200 concurrent / ITER 3 / **hold 60s** /
  lock timeout 3 min / job timeout 15 min / loopback OFF = strictly cross-controller).
- Topology: 4 controllers (a/b/c/d) acting as both server and client, 50 resources each (40 exposed),
  quantity selection over the `pool` label.
- Precondition: the lock step must pass `timeoutForAllocateResource: 3, timeoutUnit: 'MINUTES'`
  correctly. (Note that `timeout:` / `unit:` are *not* valid parameters and are silently ignored. The
  observations here were taken after the parameters were corrected.)
- Exhaustion condition: 40 exposed per server and remote quantity 2 means demand is roughly 2.5x supply,
  and with a 60s hold the wait reaches the 180s lock timeout, so some acquires time out.

Source run (evidence):

```
run id   : 20260622083826  (preset=stress)
reports  : dev/reports/20260622083826-load-test/grid-storm/   (may be pruned later; evidence is inlined below)
```

---

## 4. Evidence (inlined)

### 4.1 Result summary (excerpt from metrics.json)

```
builds=200  results={SUCCESS: 191, FAILURE: 9}
overlap_violations=0   hung=0           <- consistency fully preserved
all 9 failures fail-closed (0 body-execution markers)
queue_wait_ms: p50=3901.5  p95=167373.7  p99=179262.3  max=182276   <- cut off at ~180s (=3 min)
```

### 4.2 Classification of the 9 failures (by console errorCode)

| build | Path | Surfaced as |
|---|---|---|
| d#251 | **A** | `errorCode=LOCK_WAIT_TIMEOUT` (clean) |
| c#248 | **A** | `errorCode=LOCK_WAIT_TIMEOUT` |
| c#244 | **A** | `errorCode=LOCK_WAIT_TIMEOUT` |
| c#214 | **B** | `GET /acquire/{id}` -> HTTP 404 -> RemoteApiException (communication failure) |
| b#217 | **B** | same |
| c#245 | **B** | same |
| b#229 | **B** | same |
| c#246 | **B** | same |
| c#236 | **B** | same |

-> **A = 3 / B = 6.** Under load, B (404 -> communication failure) dominates.

### 4.3 Path A evidence (clean: d#251, verbatim excerpt)

```
Trying to acquire remote lock on [Label: pool, Quantity: 2] (serverId=a)
Remote acquire enqueued (serverId=a, lockId=ecdbace2-b375-4ca1-9ed6-5993dfa96162)
ERROR: Remote acquire failed (serverId=a, lockId=ecdbace2-b375-4ca1-9ed6-5993dfa96162, state=FAILED, errorCode=LOCK_WAIT_TIMEOUT, message=null)
Finished: FAILURE
```

### 4.4 Path B evidence (rough: c#214, verbatim excerpt)

```
Trying to acquire remote lock on [Label: pool, Quantity: 2] (serverId=a)
Remote acquire enqueued (serverId=a, lockId=0a2c23c9-6e43-44c2-bc4f-48cb94bbb2c4)
... (the server-side record expires and disappears during QUEUED polling) ...
org.jenkins.plugins.lockableresources.remote.RemoteApiException: Remote API request failed: GET /acquire/0a2c23c9-6e43-44c2-bc4f-48cb94bbb2c4/ returned HTTP 404
Also:   org.jenkinsci.plugins.workflow.actions.ErrorAction$ErrorId: d6c859c4-b052-4c40-bda8-7ecb4567739d
Caused: org.jenkins.plugins.lockableresources.remote.RemoteApiException: Remote API communication failure: GET /acquire/0a2c23c9-6e43-44c2-bc4f-48cb94bbb2c4/
Finished: FAILURE
```

> What to observe: the enqueue succeeded (QUEUED), then the status poll 404s, and a **legitimate
> allocation timeout** surfaces as **`Remote API request failed ... HTTP 404` plus `communication failure`**.

---

## 5. Root cause (confirmed)

**The terminal-record TTL is measured from the enqueue time rather than from the instant the record
became terminal, so a timeout-induced FAILED record is already past its TTL the moment it is created
and is deleted on the next sweep.**

- **Timestamps** — `RemoteLockRecord`
  ([RemoteLockRecord.java](../../../../lockable-resources-plugin/src/main/java/org/jenkins/plugins/lockableresources/remote/RemoteLockRecord.java)):
  `enqueuedAt` is set once at construction. `markFailed()` **does not record the terminal-transition
  instant** (there is no `terminalAt` equivalent).

- **Sweep** — `RemoteLockManager.maybeScanStale`
  ([RemoteLockManager.java:228-230](../../../../lockable-resources-plugin/src/main/java/org/jenkins/plugins/lockableresources/remote/RemoteLockManager.java)),
  with `TERMINAL_TTL_MS = 120s`:
  ```java
  } else if (state == SKIPPED || state == FAILED) {
      if (now - record.getEnqueuedAt() > TERMINAL_TTL_MS) {   // <- measured from enqueue (bug)
          records.remove(record.getLockId());
      }
  }
  ```

- **Timeline** (with `timeoutForAllocateResource = 180s`):
  1. enqueue (t=0) -> QUEUED
  2. queue timeout (t=180s) -> `RemoteQueueEntry.onTimeout` -> `markFailed("LOCK_WAIT_TIMEOUT")`.
     The record becomes FAILED (not deleted)
  3. next `maybeScanStale`: `now - enqueuedAt = 180s > 120s` is **already true at creation** ->
     **immediate `records.remove`**
  4. every subsequent `GET /acquire/{lockId}` finds no record -> **404 LOCK_NOT_FOUND**

  So the 120s grace window that should exist for returning FAILED is **zero from the start** whenever
  `timeoutForAllocateResource (180s) > TERMINAL_TTL (120s)`. That is why path B dominates. With
  `timeoutForAllocateResource <= 120s` the window still has `120 - timeout` seconds left, giving
  path A (clean), so **the bug does not surface**.

- **How 404 becomes a communication failure**: with no record, `AcquireStatusResource` returns
  404 LOCK_NOT_FOUND
  ([RemoteApiV1Action.java](../../../../lockable-resources-plugin/src/main/java/org/jenkins/plugins/lockableresources/actions/RemoteApiV1Action.java)),
  and the client treats a 404/410 during polling as "server may have restarted" and fails closed
  immediately
  ([RemoteLockSession.java:234-248](../../../../lockable-resources-plugin/src/main/java/org/jenkins/plugins/lockableresources/remote/RemoteLockSession.java)).
  Hence a legitimate allocation timeout is mislabelled as "communication failure / server restart".

> This issue was originally described as "a race between the client allocate-timeout and the server
> queue timeout", which is **wrong**. The client has no allocate-timeout of its own (it polls
> indefinitely at a 3s interval while QUEUED,
> [RemoteLockSession.java:186](../../../../lockable-resources-plugin/src/main/java/org/jenkins/plugins/lockableresources/remote/RemoteLockSession.java));
> the real cause is the TTL-origin bug above. The remaining A/B variance is only the gap between
> `markFailed` and the next sweep.

---

## 6. Candidate fixes

**With the primary cause confirmed, fixing the TTL origin is the first choice.**

1. **Measure the TTL from the terminal-transition instant** (**recommended; the real fix**):
   add `terminalAt` (or `failedAt` / `skippedAt`) to `RemoteLockRecord` and set it in
   `markFailed` / `markSkipped`. Change `maybeScanStale` to
   `now - record.getTerminalAt() > TERMINAL_TTL_MS` (falling back to `max(enqueuedAt, terminalAt)`).
   -> Regardless of the timeout length, a FAILED record always lives for 120s, so a polling client
   always receives a clean `LOCK_WAIT_TIMEOUT` (path A). The 404 stops happening at all.

2. (Reinforcement) **Have the client normalize a polled 404 LOCK_NOT_FOUND into a timeout**:
   map it to `RemoteAcquireStatus(state=FAILED, errorCode=LOCK_WAIT_TIMEOUT)`. Because this cannot be
   distinguished from a genuine server restart, it should stay secondary to fix 1.

3. (Optional) **Split the 404 errorCode**: return different codes for "absent because it timed out"
   and "unknown lockId".

> The exact `Caused:` wrapping order in 4.4 will be settled by the fix. The observable stays the same:
> an allocation timeout surfaces as 404 / communication failure.

---

## 7. Detectability (catchable by E2E; load-independent)

Because the issue **fires deterministically whenever `timeoutForAllocateResource > TERMINAL_TTL_MS (120s)`**
rather than under load, it can be reproduced and regression-guarded at E2E scale (1 holder, 1 waiter).

- **E2E that reproduces it**: a holder keeps the resource -> a waiter issues a remote acquire with
  `timeoutForAllocateResource > 120s` (e.g. 130s) -> the wait times out -> **assert strictly on
  `errorCode == LOCK_WAIT_TIMEOUT`**. With the bug present this becomes 404 / "server may have
  restarted" and the assertion fails, detecting it.
- **How to write it wrong (caution)**: setting the timeout **short (<120s)** leaves the FAILED window
  intact, producing the clean path A and a false PASS. A regression test **must use timeout >
  TERMINAL_TTL** (or lower the TTL temporarily).
- Why the existing E2E missed it: there was no timeout scenario at all, so the boundary (the TTL) was
  never probed — the same class of gap as `rlr-equivalence-test-defaults`.
- The load suite found it first only because `stress` happened to use timeout = 3 min (>120s). Load is
  not a necessary condition.

---

## 8. Out of scope and notes

- This is **not a correctness bug**. Mutual exclusion, fail-closed behaviour and termination all hold
  (measured under `stress`: 0 overlaps, 0 HUNG, 0 bodies executed). The issue is about
  **diagnosability and signal consistency**.
- Passing `timeout:` / `unit:` to the lock step has no effect (silently ignored with an
  `Unknown parameter` warning, i.e. 0 = wait forever). The correct names are
  `timeoutForAllocateResource` / `timeoutUnit`. That is a separate operational caveat.
- Related specification: the load suite as a whole is documented in
  `dev/docs-e/LOAD_TEST_SPECIFICATION.md` (verification record and findings sections).

---

## Appendix: related runs (same day)

| run id | preset | Scale | Result | Notes |
|---|---|---|---|---|
| 20260622072853 | full (loopback OFF) | 200 | 200/200 COMPLETED | lock timeout not yet corrected (waited forever); no timeout occurred |
| 20260622082344 | stress (timeout not yet corrected) | 200 | 200/200 COMPLETED | succeeded even at max wait 238s because the wait was unbounded |
| **20260622083826** | **stress (timeout corrected)** | **200** | **191/9** | **source of this issue (A=3 / B=6)** |
