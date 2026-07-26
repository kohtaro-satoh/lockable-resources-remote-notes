# M1I Implementation Steps (Remote lock - Phase 1 / M1I: queued-expiry-poll-404 regression fix)

> Design: `LRR_DESIGN_P1_M1I.md` / Origin: `LRR_ISSUE_P1_M1H_queued_expiry_poll_404.md`
> Branch: `feature/1025-remote-lr-p1-m1` (M1I start HEAD `65d8415` = PR #1055 head)

### Step 1: Server - record the terminal transition time

- [x] `RemoteLockRecord.java`: add `terminalAt` (volatile long) field + `getTerminalAt()`
- [x] Set `this.terminalAt = System.currentTimeMillis()` in `markFailed` / `markSkipped`

### Step 2: Server - fix the terminal-TTL reference

- [x] `RemoteLockManager.maybeScanStale`: change the SKIPPED/FAILED eviction check from `now - getEnqueuedAt()`
      to **`now - getTerminalAt()`**
- [x] Document the intent in a comment (retain FAILED for the full TTL even when timeout > TTL, so a poll observes it)

### Step 3: Client - normalize poll 404

- [x] `RemoteLockSession.pollStatus`: map a `RemoteApiException` 404/410 to **`LOCK_WAIT_TIMEOUT` when `!bodyStarted`**
- [x] After the body starts (an acquired lease vanished) keep the existing "server may have restarted" handling
- [x] Match the message to path A (FAILED-state receipt) so `errorCode=LOCK_WAIT_TIMEOUT` is emitted

### Step 4: Tests

- [x] Unit: `RemoteLockManagerTest.timedOutRecordRecordsTerminalTimestampAndSurvivesMaintenance`
- [x] E2E: `scenarios/remote-acquire-timeout.sh` (S18), registered in `run-e2e.sh` (`M1I_SCENARIOS` / `m1i-series` / `all` / IDS / usage)
- [x] `E2E_TEST_SPECIFICATION.md` updated with S18 (P1M1I)

### Step 5: Build, verify, commit

- [x] `dev/run-mvn-verify.sh` (in-place `mvn clean verify`) SUCCESS -> `dev/reports/20260622120114-mvn-verify.md` (384/0/1skip, all gates ok)
      (spotless violation -> `spotless:apply`, then re-verify)
- [x] Deploy to containers via `start.sh --clean --in-place-build` (avoids the stale-`.jpi` volume trap)
- [x] S18 alone: FAIL before the fix (404/communication failure) / PASS after (`LOCK_WAIT_TIMEOUT`)
- [x] `dev/jenkins-env/run-e2e.sh` all PASS -> `dev/reports/20260622123929-e2e-test.md` (21/21)
- [x] plugin commit `e231367` (stacked on `65d8415`, no amend, no Co-Authored-By)
- [x] notes commit (load suite + issue + S18 / latest reports). Do **not** push.
- [ ] notes commit of this cycle's docs (DESIGN/STEPS/RESULT j+e, README index)

## Changed files (plugin)

| File | Change | Status |
|---|---|---|
| `remote/RemoteLockRecord.java` | `terminalAt` + getter, set in markFailed/markSkipped | done |
| `remote/RemoteLockManager.java` | terminal TTL keyed off terminalAt | done |
| `remote/RemoteLockSession.java` | normalize poll 404/410 to LOCK_WAIT_TIMEOUT | done |
| `remote/RemoteLockManagerTest.java` | terminalAt-mechanism test | done |
