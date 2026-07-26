# M1I Result (Remote lock - Phase 1 / M1I: queued-expiry-poll-404 regression fix)

> Design: `LRR_DESIGN_P1_M1I.md` / Steps: `LRR_IMPLEMENTATION_STEPS_P1_M1I.md` / Origin: `LRR_ISSUE_P1_M1H_queued_expiry_poll_404.md`
> Branch: `feature/1025-remote-lr-p1-m1` (M1I commit `e231367`, on top of PR #1055 head `65d8415`)

## Summary

The (A) minimal fix for a regression found by the newly built load test suite (load-test-suite, `run-load.sh`
stress): a legitimate remote acquire allocation timeout surfaced as 404 / "communication failure" when
`timeoutForAllocateResource > 120s`. The terminal-record retention TTL is now measured from the terminal
transition time, and the client normalizes a poll 404 to `LOCK_WAIT_TIMEOUT`. E2E S18 added as the regression guard.

## What changed

| Layer | Change |
|---|---|
| Server | `RemoteLockRecord.terminalAt` (set in markFailed/markSkipped); `RemoteLockManager.maybeScanStale` terminal TTL keyed off `getTerminalAt()` |
| Client | `RemoteLockSession` normalizes poll 404/410 (before body) to `LOCK_WAIT_TIMEOUT` (safety net) |
| Tests | unit `timedOutRecordRecordsTerminalTimestampAndSurvivesMaintenance`, E2E `S18 remote-acquire-timeout` (`m1i-series`) |

## Diff (plugin, commit `e231367`)

| File | Change |
|---|---|
| `remote/RemoteLockRecord.java` | `terminalAt` + `getTerminalAt()`, set in markFailed/markSkipped |
| `remote/RemoteLockManager.java` | `maybeScanStale` terminal TTL from terminalAt |
| `remote/RemoteLockSession.java` | normalize poll 404/410 to LOCK_WAIT_TIMEOUT |
| `remote/RemoteLockManagerTest.java` | terminalAt-mechanism test |

Total 4 files / +73, -1.

## Verification

Per the dev cycle (`作業手順一覧.md`), `run-mvn-verify.sh` (mvn verify) + `run-e2e.sh` are the source of truth.

- **mvn verify (in-place, committed HEAD `e231367`): BUILD SUCCESS / 384 tests, 0 failures, 0 errors, 1 skipped**,
  spotless/spotbugs(effort=Max, threshold=Low)/checkstyle/pmd/cpd all ok (`dev/reports/20260622120114-mvn-verify.md`).
  New unit (terminalAt mechanism) green. (Initial spotless violation -> `spotless:apply`, then green.)
- **E2E: 21/21 PASS / 0 fail** (`dev/reports/20260622123929-e2e-test.md`). New **S18 remote-acquire-timeout** + 20 existing, no regression.
- **S18 works as a regression guard**: with the pre-fix plugin (a stale `.jpi` in the jhX volume) it **FAILED**
  (404 / communication failure); after deploying the fix via `start.sh --clean --in-place-build` it **PASSED**
  (`errorCode=LOCK_WAIT_TIMEOUT`, body not executed, wait 153s).
- **Server retention confirmed via Groovy probe**: with a short (1s) timeout, after QUEUED->FAILED the
  `terminalAt - enqueuedAt` is ~1520ms and the record is **RETAINED** (not evicted) by `doRun()` = maybeScanStale.

> Local pass of the CI gates (spotless/spotbugs, etc.) that `mvn test` skips (jenkinsci-ci-mvn-verify).

## Commit

- plugin: `feature/1025-remote-lr-p1-m1` head `e231367` "Report a remote acquire timeout as LOCK_WAIT_TIMEOUT,
  not a 404 failure" (stacked on `65d8415`, **no amend** = keep PR #1055's submitted hashes). **Not pushed** (on request).
- notes: load suite + issue + S18 (`b6e0583`), latest 3 reports (`dfcb8d8`), this cycle's docs (DESIGN/STEPS/RESULT j+e, README). No Co-Authored-By.

## Next / open

- **(B) state-abolition redesign** is a separate issue (needs a cross-version-compatibility / extensibility design). This cycle closes with (A).
- Maintainer review (PR #1055) and force push are separate steps. Client UI is Phase 2 (issue #1025).
