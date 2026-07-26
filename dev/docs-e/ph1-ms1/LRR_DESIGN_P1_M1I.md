# M1I Design (Remote lock - Phase 1 / M1I: queued-expiry-poll-404 regression fix)

> Origin: `LRR_ISSUE_P1_M1H_queued_expiry_poll_404.md` (an M1H/#52 regression found by load testing)
> Branch: `feature/1025-remote-lr-p1-m1` (M1I commit `e231367`, stacked on PR #1055 head `65d8415`, no amend)
> Position: an independent cycle, after M1H and the PR #1055 submission, fixing a degraded-path regression
> surfaced by the newly built load test suite (see load-test-suite). Contains one behaviour change (how a
> timeout surfaces only; lock correctness is unchanged).

## 1. Goal

A remote acquire that times out waiting for a busy resource must fail closed with a clear `LOCK_WAIT_TIMEOUT`.
Before the fix, when `timeoutForAllocateResource > 120s`, a legitimate allocation timeout surfaced as
HTTP 404 -> "communication failure / server may have restarted" (still fail-closed, so not a correctness bug,
but misleading to operators).

## 2. Root cause (summary of the origin issue, section 5)

- `RemoteLockManager.maybeScanStale` measured the terminal-record (SKIPPED/FAILED) retention TTL
  (`TERMINAL_TTL_MS = 120s`) from **`enqueuedAt`**.
- A timeout-originated FAILED record only becomes terminal at `t = timeoutForAllocateResource` (from enqueue),
  so when `timeoutForAllocateResource > 120s` it is already past the enqueue-based TTL the instant it is
  created and gets evicted on the next sweep. The client's next `GET /acquire/{lockId}` poll then receives
  **404 LOCK_NOT_FOUND**, which `RemoteLockSession` mapped to "server may have restarted".
- The buggy line dates to the first #1025 commit (`4f3577f`); M1H's **#52 (B2: remove poll-keepalive, own the
  QUEUED lifetime via the queue timeout)** made the actively-polled QUEUED->FAILED path reachable, surfacing it
  as observable degradation.
- Not load-dependent: deterministic when `timeoutForAllocateResource > TERMINAL_TTL (120s)` (the load test hit
  it first only because the stress preset happened to use a 3-minute timeout).

## 3. Design (chosen = (A), minimal fix)

### Server (primary)

- Add `terminalAt` to `RemoteLockRecord`, set in `markFailed` / `markSkipped`.
- Change the `maybeScanStale` terminal TTL check from `now - getEnqueuedAt()` to **`now - getTerminalAt()`**.
- A FAILED/SKIPPED record is then always observable for the full TTL regardless of how long the wait was, so a
  polling client reads a clean `LOCK_WAIT_TIMEOUT` and the 404 no longer occurs.

### Client (safety net)

- In `RemoteLockSession` poll handling, normalize a `RemoteApiException` **404/410 received before the body
  starts (still QUEUED) to `LOCK_WAIT_TIMEOUT`**.
- Rationale: holding a lockId means admission passed at POST; `skipIfLocked` resolves synchronously at POST
  (never polled). So a never-acquired record vanishing can only be an allocation timeout, robust even past the
  server TTL or across a partition.

## 4. Alternatives and why rejected

| Option | Summary | Verdict |
|---|---|---|
| **(A) chosen** | terminal TTL from terminalAt + client normalizes poll 404 to timeout | minimal, backward compatible, no miss window; best for the in-flight PR |
| (B) | abolish `SKIPPED`/`FAILED` states, delete immediately, infer 404 from request type + last state | cleaner end-state but a protocol / state-machine change with cross-version compatibility (remote is client/server, possibly different versions) and errorCode extensibility costs; deferred to a separate issue |

## 5. Test plan

- Unit: `RemoteLockManagerTest.timedOutRecordRecordsTerminalTimestampAndSurvivesMaintenance`
  (after timeout -> FAILED, `terminalAt` is set after enqueue and the record is not evicted by an immediate
  `doRun()` = maybeScanStale).
- E2E: new **S18 `remote-acquire-timeout`** (`m1i-series`). A holder pins R while a waiter does a remote acquire
  with `timeoutForAllocateResource > 120s` (130s) and times out. Asserts **`errorCode == LOCK_WAIT_TIMEOUT`**,
  absence of `server may have restarted` / `communication failure` / `HTTP 404`, body not executed, wait >= 120s.
  The timeout **must exceed 120s** to cross the TTL boundary (a shorter timeout leaves the FAILED window intact
  and passes spuriously). FAIL before the fix / PASS after = a real regression guard.

## 6. Out of scope (M1I)

| Item | Note |
|---|---|
| (B) state-abolition redesign | separate issue; needs its own protocol/compatibility design |
| Client UI / read-only mirror | Phase 2 (issue #1025) |

## 7. Verification

Per the dev cycle (`作業手順一覧.md`), `run-mvn-verify.sh` (mvn verify) + `run-e2e.sh` are the source of truth.

- `dev/run-mvn-verify.sh` (in-place `mvn clean verify`): all tests + static gates (spotless/spotbugs/checkstyle/pmd/cpd) pass.
- `dev/jenkins-env/run-e2e.sh`: all scenarios PASS (including S18).
- **Deployment note** (rlr-build-environment): a stale `.jpi` in a jhX volume overrides the ref/plugins seed,
  so an uncommitted working-tree fix needs `start.sh --clean --in-place-build` to reach E2E.

## Changed files (plugin, commit `e231367`)

| File | Change |
|---|---|
| `remote/RemoteLockRecord.java` | add `terminalAt` + `getTerminalAt()`, set in markFailed/markSkipped |
| `remote/RemoteLockManager.java` | `maybeScanStale` terminal TTL keyed off `getTerminalAt()` |
| `remote/RemoteLockSession.java` | normalize poll 404/410 (before body) to `LOCK_WAIT_TIMEOUT` |
| `remote/RemoteLockManagerTest.java` | add terminalAt-mechanism test |

Total 4 files / +73, -1.

## Changelog

- 2026-06-22: Initial. Defines (retroactively) the M1I cycle for the (A) minimal fix of the queued-expiry-poll-404
  regression (M1H #52 origin; latent line from 4f3577f): terminal TTL from terminalAt + client 404 normalization,
  with S18 as the regression guard.
