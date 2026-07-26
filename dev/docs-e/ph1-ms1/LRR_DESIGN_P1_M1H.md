# M1H Design (Remote lock - Phase 1 / M1H: PR #1055 CI follow-up)

> Starting review: `LRR_REVIEW_P1_M1H.md`
> Branch: `feature/1025-remote-lr-p1-m1` (HEAD at M1H start = `5136daa`, base `master` = `87c4a7e`)
> Positioning: a remediation cycle for the 4 security findings and the master drift raised by the upstream CI **after M1G
> (the pure refactor) was complete and PR #1055 was submitted**. It is an independent development cycle from M1G; only M1H
> contains one intentional behaviour change (B2).

## 1. Goal

Make PR #1055 mergeable and CI-clean. Scope: (a) the 4 `github-advanced-security[bot]` findings, (b) master sync.

## 2. Security remediation (#49/#50/#51 — mechanical)

CSRF/permission hardening for Stapler web methods. Behavioural semantics unchanged.

| # | Target | Remediation |
|---|---|---|
| 49/51 | `RemoteConnection.DescriptorImpl#doCheckUrl` | add `@POST` (`org.kohsuke.stapler.verb.POST`) + `Jenkins.get().checkPermission(Jenkins.ADMINISTER)`; add `checkMethod="post"` to the `url` field in `RemoteConnection/config.jelly` |
| 50 | `LockableResourcesManager#doCheckForcedServerId` | add `@POST` only (ADMINISTER check already present); add `checkMethod="post"` to `forcedServerId` in `LRM/config.jelly` |

> The jelly `checkMethod="post"` makes the form-validation request a POST once `@POST` is on the method (without it the
> default GET validation gets a 405 and validation breaks).

## 3. #52 remediation = B2 (behaviour change, the core of this cycle)

**Decision (see starting review §5):** make `GET /acquire/{lockId}` a pure read and fold QUEUED liveness onto the
server-side queue timeout.

### Design rationale

- State transitions (QUEUED→ACQUIRED, timeout failure) never depended on the GET; they are owned by server-side local
  logic (`proceedNextContext` / the 1-second `PeriodicWork` / the `RemoteQueueEntry` deadline).
- The GET's `touchPoll` side effect is exclusively a "GC for abandoned QUEUED clients", and only has any effect when
  `timeoutForAllocateResource == 0` (infinite wait).

### Changes

- `RemoteApiV1Action.AcquireStatusResource#doIndex`: remove the `touchPoll(lockId)` call (pure-read GET). Keep the
  `REMOTE` permission check and the API-enabled check.
- `RemoteLockManager`: remove `touchPoll(String)` / `getQueuePollExpiryMs()` / `DEFAULT_QUEUE_POLL_EXPIRY_MS`, and remove
  the **QUEUED branch (`QUEUE_EXPIRED`) of `maybeScanStale`**. Keep the ACQUIRED STALE detection and terminal TTL cleanup.
- `RemoteLockRecord`: remove `lastPolledAt` / `polled()` / `getLastPolledAt()`.
- QUEUED expiry is folded onto `RemoteQueueEntry.timeoutDeadlineMillis` (= `timeoutForAllocateResource`).

### Accepted trade-off (documented)

We give up the ~60s early reclamation of a QUEUED slot when `timeoutForAllocateResource == 0` (infinite wait) and the
client has died. While QUEUED it holds no resource (slot only); once promoted, ACQUIRED heartbeat-STALE reclaims it, so it
is safe. Consistent with a local `lock()` without a timeout.

### Alternatives and why rejected

| Option | Content | Assessment |
|---|---|---|
| B1 | GET pure read + move keepalive onto POST `/lease` heartbeat, started from QUEUED | keeps fast GC and clean REST, but runs 2 channels (poll+heartbeat) during QUEUED; larger change. Not adopted |
| **B2 (adopted)** | remove `touchPoll` from the GET = pure read, fold QUEUED expiry onto the server-side queue timeout | minimal, most faithful to the design view (transitions owned by server-side local logic), #52 disappears naturally |
| B3 | make the status GET a POST | symptom treatment, turns a read into a mutation, non-RESTful. Rejected |

## 4. Master sync

Rebase `feature/1025-remote-lr-p1-m1` onto `upstream/master` (`8f03dbf`: #1056 crowdin bump / #1057 BOM bump). No conflict
(`pom.xml` is a different hunk; both `merge-tree` and the real merge dry-run are clean — see starting review §2).

## 5. Test plan

- Remove/replace the two poll-keepalive cases in `RemoteLockManagerTest` (using `queuePollExpiryMs`, expecting
  `QUEUE_EXPIRED`):
  - `queuedRecordExpiresViaQueueTimeout`: QUEUED expires via the `RemoteQueueEntry` timeout
    (`timeoutForAllocateResource`) and becomes `LOCK_WAIT_TIMEOUT`; after expiry it does not grab the resource. Driven by
    `checkTimeouts()` (→ proceedNextContext → getNextRemoteEntry).
  - `queuedRecordWithoutTimeoutSurvivesWithoutPolling`: with no timeout and no polling, repeated `doRun()` does not expire
    the QUEUED record (regression guard for removing the poll-keepalive GC); `find()` (the GET status path) is a pure read;
    promotion on release still works.
- `RemoteConnectionTest`: `doCheckUrl` now requires ADMINISTER, so the class is made `@WithJenkins`; a
  `testDoCheckUrlRequiresAdmin` is added asserting a non-admin gets `AccessDeniedException` (coverage for #49).
  `doCheckForcedServerId` is kept under the existing `@WithJenkins` test.
- Since only B2 changes behaviour, E2E is verified by keeping all existing cases green (the infinite-wait + dead client
  early reclamation is out of scope for scenarios = accepted trade-off).

## 6. Out of scope (not in M1H)

| Item | Note |
|---|---|
| New features / new E2E scenarios | not added in a CI-remediation cycle |
| Client UI / read-only mirror | Phase 2 (issue #1025) |
| B1 (QUEUED heartbeat) | the fast-GC alternative; not done since B2 is adopted |

## 7. Verification

Per the development cycle (`作業手順一覧.md`), `run-mvn-verify.sh` (mvn verify) + `run-e2e.sh` are the verification of
record.

- `dev/run-mvn-verify.sh` (in-place, `mvn clean verify`): full tests + static gates (spotless/spotbugs/checkstyle/pmd/cpd)
  pass.
- `dev/jenkins-env/run-e2e.sh`: all cases pass (behaviour regression).
- After master sync (rebase), re-run `dev/run-mvn-verify.sh` to confirm full tests + gates pass with the new BOM (#1057).

## Changed files (plugin)

| File | Change |
|---|---|
| `RemoteConnection.java` | `@POST` + ADMINISTER on `doCheckUrl`, add imports |
| `RemoteConnection/config.jelly` | `checkMethod="post"` on `url` |
| `LockableResourcesManager.java` | `@POST` on `doCheckForcedServerId`, add import |
| `LockableResourcesManager/config.jelly` | `checkMethod="post"` on `forcedServerId` |
| `actions/RemoteApiV1Action.java` | remove `touchPoll` from `doIndex` (pure-read GET) |
| `remote/RemoteLockManager.java` | remove poll-keepalive set + QUEUED-expiry branch |
| `remote/RemoteLockRecord.java` | remove `lastPolledAt`/`polled()`/`getLastPolledAt()` |
| `remote/RemoteLockManagerTest.java` | replace 2 poll-keepalive cases (queue-timeout expiry / pure-read survival) |
| `RemoteConnectionTest.java` | make `doCheckUrl` test `@WithJenkins`, add non-admin permission test |
| `pom.xml` | pull in the BOM bump (#1057) via rebase |

## Change log

- 2026-06-20: Initial version. Defines the M1H development cycle addressing PR #1055's 4 CI security findings (#49–52) +
  master sync. #49/#50/#51 are mechanical hardening; #52 adopts B2 (pure-read GET, remove poll-keepalive, fold QUEUED
  expiry onto the queue timeout).
