# M1H Result (Remote lock - Phase 1 / M1H: PR #1055 CI follow-up)

> Design: `LRR_DESIGN_P1_M1H.md` / steps: `LRR_IMPLEMENTATION_STEPS_P1_M1H.md` / starting review: `LRR_REVIEW_P1_M1H.md`
> Branch: `feature/1025-remote-lr-p1-m1` (M1H commit `7c3b325`, after rebase onto `upstream/master` = `8f03dbf`)

## Summary

A remediation cycle for the **4 security warnings** (`github-advanced-security[bot]`) and the **master drift** raised by
the upstream CI after PR #1055 was submitted. #49/#50/#51 are CSRF/permission hardening for Stapler web methods (behaviour
unchanged); #52 is **B2** = making `GET /acquire/{lockId}` a pure read (remove the poll-keepalive, fold QUEUED expiry onto
the server-side queue timeout), the one **intentional behaviour change**. The "master conflict" the user worried about did
not exist; it was resolved by simply taking master in via rebase.

## What was done

### Security remediation

| # | Target | Remediation |
|---|---|---|
| 49/51 | `RemoteConnection.DescriptorImpl#doCheckUrl` | add `@POST` + `Jenkins.get().checkPermission(Jenkins.ADMINISTER)`; `checkMethod="post"` on `url` in `RemoteConnection/config.jelly` |
| 50 | `LockableResourcesManager#doCheckForcedServerId` | add `@POST` (ADMINISTER already checked); `checkMethod="post"` on `forcedServerId` in `LRM/config.jelly` |
| 52 | `RemoteApiV1Action.AcquireStatusResource#doIndex` | **B2**: remove `touchPoll` to make the GET a pure read |

### #52 = B2 removal targets

- `RemoteApiV1Action.doIndex`: remove the `touchPoll(lockId)` call (keep the `REMOTE` permission and API-enabled checks).
- `RemoteLockManager`: remove `touchPoll(String)` / `getQueuePollExpiryMs()` / `DEFAULT_QUEUE_POLL_EXPIRY_MS` and the
  QUEUED branch (`QUEUE_EXPIRED`) of `maybeScanStale`. Keep ACQUIRED STALE detection and terminal TTL.
- `RemoteLockRecord`: remove `lastPolledAt` / `polled()` / `getLastPolledAt()`.
- QUEUED expiry folded onto `RemoteQueueEntry.timeoutDeadlineMillis` (= `timeoutForAllocateResource`).

**Accepted trade-off**: lose the ~60s early reclamation of a QUEUED slot when `timeoutForAllocateResource == 0` (infinite
wait) and the client has died (QUEUED holds no resource; once promoted, ACQUIRED heartbeat-STALE reclaims it = safe;
consistent with a local `lock()` without a timeout).

## Diff (plugin, commit `7c3b325`)

| File | Change |
|---|---|
| `RemoteConnection.java` | `@POST` + ADMINISTER on `doCheckUrl` (2 imports) |
| `RemoteConnection/config.jelly` | `checkMethod="post"` on `url` |
| `LockableResourcesManager.java` | `@POST` on `doCheckForcedServerId` (1 import) |
| `LockableResourcesManager/config.jelly` | `checkMethod="post"` on `forcedServerId` |
| `actions/RemoteApiV1Action.java` | remove `touchPoll` from `doIndex` (pure-read GET) |
| `remote/RemoteLockManager.java` | remove poll-keepalive set + QUEUED-expiry branch (~-49 lines) |
| `remote/RemoteLockRecord.java` | remove `lastPolledAt`/`polled()`/`getLastPolledAt()` |
| `RemoteConnectionTest.java` | make `doCheckUrl` test `@WithJenkins`, add `testDoCheckUrlRequiresAdmin` |
| `remote/RemoteLockManagerTest.java` | replace 2 poll-keepalive cases with `queuedRecordExpiresViaQueueTimeout` / `queuedRecordWithoutTimeoutSurvivesWithoutPolling` |

Total: 9 files / +87, -109 (net removal).

## Master sync (rebase)

- Rebased `feature/1025-remote-lr-p1-m1` onto `upstream/master` (`8f03dbf`: #1056 crowdin bump / #1057 BOM bump
  `6549...`→`6585...`).
- **No conflict** (4/4 auto-replayed). In `pom.xml` the BOM bump (master, lines 73-74) and the credentials dependency
  (PR, line 88) coexist in different hunks.
- 4 commits after rebase: `913e3a5` (phase1) / `f8feeae` (spotless) / `ac49db9` (spotbugs) / `7c3b325` (M1H security).

## Verification

Per the development cycle (`作業手順一覧.md`), `run-mvn-verify.sh` (mvn verify) + `run-e2e.sh` are the verification of
record.

- **mvn verify (pre-rebase, in-place): BUILD SUCCESS / 383 tests, 0 failures, 1 skipped**, all of
  spotless/spotbugs (effort=Max, threshold=Low)/checkstyle/pmd/cpd ok (`dev/reports/20260620220250-mvn-verify.md`). New
  tests (doCheckUrl permission, queue-timeout expiry, pure-read survival) are green.
- **E2E: 20/20 PASS / 0 fail** (`dev/reports/20260620222354-e2e-test.md`, working tree built via
  `start.sh --in-place-build`). **S13 stale-admin-release** (ACQUIRED heartbeat-STALE reclamation), which B2 relies on, is
  green = the alternative to the removed QUEUED poll-GC works in a real environment.
- **mvn verify (post-rebase, new BOM #1057, committed HEAD `7c3b325`, clean tree): BUILD SUCCESS / 383 tests, 0 failures,
  0 errors, 1 skipped**, all gates ok (`dev/reports/20260621082011-mvn-verify.md`) = no regression after taking in the new
  BOM (the verification of record).

> Passes locally the CI gates that `mvn test` misses (spotless/spotbugs, etc.) ([[jenkinsci-ci-mvn-verify]]).

## Commit

- plugin: `feature/1025-remote-lr-p1-m1` = `7c3b325` (single M1H commit, on top of `upstream/master 8f03dbf`). **No push**
  (force push at submission).
- notes: committed in this step (REVIEW/DESIGN/STEPS/RESULT j+e, README index/Status, reports). No Co-Authored-By.

## Open items / next

- B1 (keeping fast GC by heartbeating during QUEUED) remains not adopted; revisit if early reclamation of the
  infinite-wait + dead-client case is needed later.
- Maintainer review (PR #1055, mergeState BLOCKED=REVIEW_REQUIRED) and the force push are separate steps. Client UI is
  Phase 2 (issue #1025).
