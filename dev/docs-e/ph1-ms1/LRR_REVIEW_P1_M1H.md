# Remote LR Development Review (Phase 1 / M1H — start of the PR #1055 CI follow-up)

> **Positioning:** this review targets the events raised by the upstream CI **after M1G (the pure refactor) was complete
> and PR #1055 was submitted**, and serves as the starting review that carves the remediation out as the **M1H
> development cycle** (it is not an addition to M1G).
> **Review date:** 2026-06-20
> **Target PR:** [jenkinsci/lockable-resources-plugin #1055](https://github.com/jenkinsci/lockable-resources-plugin/pull/1055)
>   `feature/1025-remote-lr-p1-m1` (HEAD: `5136daa`, base `master` = `87c4a7e`).
> **Trigger:** Two events after PR submission — (1) a suspected "conflict with upstream master", and
>   (2) **4 security warnings** from `github-advanced-security[bot]`.
> **Target docs:** `dev/docs-e/` (M1G completion record = LRR_DESIGN_P1_M1G / LRR_RESULT_P1_M1G; this cycle =
>   LRR_DESIGN_P1_M1H / LRR_IMPLEMENTATION_STEPS_P1_M1H / LRR_RESULT_P1_M1H), the GitHub PR checks / review comments.
> **Scope:** (a) does the conflict actually exist and how to resolve it, (b) validity and remediation of each of the
>   4 security findings, (c) in particular, whether it is correct for `GET /acquire/{lockId}` to mutate state.
> **Method:** PR metadata / checks / review comments via `gh`; fetch of `upstream/master` and a local 3-way merge
>   (`merge-tree --write-tree` plus a real merge dry-run); static reading of the relevant code.

---

## Table of contents

1. [Summary](#1-summary)
2. [Conflict diagnosis — it does not exist (sync only)](#2-conflict-diagnosis--it-does-not-exist-sync-only)
3. [The 4 security warnings](#3-the-4-security-warnings)
4. [Focus on #52 — why does the GET mutate state](#4-focus-on-52--why-does-the-get-mutate-state)
5. [Decision: B2 (make the GET a pure read)](#5-decision-b2-make-the-get-a-pure-read)
6. [Remediation summary](#6-remediation-summary)
7. [Hand-off to the development cycle](#7-hand-off-to-the-development-cycle)

---

## 1. Summary

**The code in PR #1055 is sound; the only things to address are the 4 security warnings raised by the external CI.**
The "master conflict" the user worried about **does not exist right now** (GitHub reports `mergeable: MERGEABLE`, and a
local 3-way merge is clean). `mergeStateStatus: BLOCKED` is caused by `REVIEW_REQUIRED` (awaiting a maintainer review),
not a conflict. The PR branch is 2 commits behind master, so the GitHub UI was likely showing a transient "out of date".

Three of the four findings (#49/#50/#51) are routine CSRF/permission hardening for Stapler web methods and can be fixed
mechanically. The remaining one (#52) flags that `GET /acquire/{lockId}` mutates state via `touchPoll()`, and is **the
only item requiring a design decision**. On reading the code, the state transitions do not depend on the GET at all; the
GET's side effect is purely a "GC for abandoned QUEUED clients". Given that, we adopt **B2 (make the GET a pure read and
fold QUEUED expiry onto the server-side queue timeout)**.

---

## 2. Conflict diagnosis — it does not exist (sync only)

| Item | Value |
|---|---|
| `mergeable` | `MERGEABLE` |
| `mergeStateStatus` | `BLOCKED` (caused by `reviewDecision: REVIEW_REQUIRED`, not a conflict) |
| merge-base | `87c4a7e` (PR base) |
| upstream/master tip | `8f03dbf` (#1056 crowdin bump, #1057 BOM bump) |
| `merge-tree --write-tree` | exit 0, no conflict markers |
| real merge dry-run | `Auto-merging pom.xml` → clean success |

The files master changed are `pom.xml` (#1057 bumps the BOM `6549...`→`6585...`) and `.github/workflows/crowdin.yml`.
This PR also touches `pom.xml` (adds the `credentials` dependency, a different hunk), so the two auto-merge.

**Conclusion:** no conflict. A rebase onto (or merge of) `upstream/master` to clear the 2-commit lag is enough; it is
taken in together with the security-fix commit.

---

## 3. The 4 security warnings

Raised by `github-advanced-security[bot]` as inline review comments (the "Jenkins Security Scan" check itself does not
block and shows pass, but the bot comments are visible to maintainers. **As a cross-repo PR, the submitter cannot dismiss
the alerts** → fixing in code is the practical path).

| alert | Location | Rule | Status |
|---|---|---|---|
| [49](https://github.com/jenkinsci/lockable-resources-plugin/security/code-scanning/49) | `RemoteConnection.DescriptorImpl#doCheckUrl` | Stapler: Missing permission check | **no** permission check |
| [51](https://github.com/jenkinsci/lockable-resources-plugin/security/code-scanning/51) | same | Stapler: Missing POST/RequirePOST (CSRF) | **no** annotation |
| [50](https://github.com/jenkinsci/lockable-resources-plugin/security/code-scanning/50) | `LockableResourcesManager#doCheckForcedServerId` | Stapler: Missing POST/RequirePOST (CSRF) | `Jenkins.ADMINISTER` check present, annotation missing |
| [52](https://github.com/jenkinsci/lockable-resources-plugin/security/code-scanning/52) | `RemoteApiV1Action.AcquireStatusResource#doIndex` | Stapler: Missing POST/RequirePOST (CSRF) | `REMOTE` permission check present, **mutates state on GET** |

- **#49/#51 (doCheckUrl):** descriptor validation for a global (admin) setting. Add `@POST` +
  `Jenkins.get().checkPermission(Jenkins.ADMINISTER)`, and add `checkMethod="post"` to the `url` field in
  `RemoteConnection/config.jelly` (once `@POST` is on the method, the validation request becomes POST; without the jelly
  attribute the default GET validation would get a 405).
- **#50 (doCheckForcedServerId):** already has the ADMINISTER check. Add `@POST` only, plus `checkMethod="post"` on the
  `forcedServerId` field in `LRM/config.jelly`.
- **#52 (doIndex):** see next section.

---

## 4. Focus on #52 — why does the GET mutate state

### 4.1 State transitions do not depend on the GET poll

The QUEUED→ACQUIRED promotion and the timeout failure are **owned entirely by server-side local logic**; the GET is not
involved.

- A busy POST `/acquire` is registered in the unified queue (`RemoteLockManager.enqueue` → `lrm.queueRemote(entry)`).
- It is dispatched by priority alongside local `lock()` steps (`LockableResourcesManager.proceedNextContext` →
  `proceedRemoteEntry`).
- Acquisition is decided by `proceedNextContext()` (queue promotion) and the 1-second `PeriodicWork`
  (`RemoteLockManager.doRun`).
- **Timeout is also fully server-side:** `RemoteQueueEntry` holds `timeoutDeadlineMillis` derived from
  `timeoutForAllocateResource`, and `getNextRemoteEntry()` / the scheduled timeout task fail expired entries.

As the client's `RemoteLockSession.pollStatus` shows with `case QUEUED: return;`, the GET only **reads state to start the
body once ACQUIRED** — it does not drive the transition. That is short polling.

### 4.2 The only reason the GET calls `touchPoll()`

It is exclusively the "**GC for abandoned QUEUED clients**".

- A local `lock()` waiter is a "live thread / Run", and its queue entry is removed when the build is aborted.
- A remote waiter is **only a record**, with no live thread attached; there is no way to know "is it still alive and still
  interested".
- So "still polling = alive" is assumed, and after polling stops, the QUEUED record is marked `QUEUE_EXPIRED` after
  `getQueuePollExpiryMs()` (= `STALE_THRESHOLD` = `max(heartbeat*6, 60)s`) in the `maybeScanStale` QUEUED branch.

**Key point:** this keepalive only has any effect when `timeoutForAllocateResource == 0` (infinite wait). For a finite
timeout, the `RemoteQueueEntry` deadline already handles it. So `touchPoll` is merely "insurance to reclaim a queue slot
within ~60s when an infinite-wait client dies"; while QUEUED it holds no resource (slot only), so it is fail-safe.

---

## 5. Decision: B2 (make the GET a pure read)

The point that "a GET should be read-only" is correct. Rather than band-aiding #52 in code (making status a POST), we make
it **disappear as a consequence of correct design**. Of the 3 options considered, we adopt B2.

| Option | Content | Assessment |
|---|---|---|
| B1 | GET pure read + move keepalive onto POST `/lease` heartbeat, started from QUEUED | keeps fast GC and clean REST, but runs 2 channels (poll+heartbeat) during QUEUED; larger change |
| **B2 (adopted)** | remove `touchPoll` from the GET = pure read, fold QUEUED expiry onto the server-side queue timeout | minimal, most faithful to the design view (transitions owned by server-side local logic), #52 disappears naturally |
| B3 | make the status GET a POST | symptom treatment, turns a read into a mutation, non-RESTful. **Rejected** |

**Behaviour given up under B2 (documented):** a QUEUED slot for an `timeoutForAllocateResource == 0` (infinite wait) client
that has died, which was previously reclaimed as `QUEUE_EXPIRED` within ~60s, will no longer be reclaimed. However:
- while QUEUED it holds no resource (slot only);
- if it is promoted, the ACQUIRED heartbeat-STALE mechanism reclaims it;
- "asked to wait forever, so it waits forever" is consistent with a local `lock()` without a timeout.

→ What is lost is only the early reclamation of the narrow "infinite wait + dead client" corner case. Accepted.

---

## 6. Remediation summary

| # | Remediation | Kind |
|---|---|---|
| 49/51 | `doCheckUrl`: add `@POST` + `checkPermission(ADMINISTER)`, jelly `checkMethod="post"` | mechanical |
| 50 | `doCheckForcedServerId`: add `@POST`, jelly `checkMethod="post"` | mechanical |
| 52 | **B2**: remove `touchPoll` from `doIndex` (pure-read GET), drop the poll-keepalive set, fold QUEUED expiry onto `RemoteQueueEntry` deadline | design change |
| — | rebase onto `upstream/master` (no conflict) | sync |

Removal targets (B2): the `touchPoll` call in `RemoteApiV1Action.doIndex`; `touchPoll` / `getQueuePollExpiryMs` /
`DEFAULT_QUEUE_POLL_EXPIRY_MS` / the QUEUED branch of `maybeScanStale` in `RemoteLockManager`; `lastPolledAt` / `polled()`
/ `getLastPolledAt()` in `RemoteLockRecord`. Tests: replace the two poll-keepalive cases in `RemoteLockManagerTest` with
"QUEUED expires via the queue timeout" and "GET does not affect QUEUED lifetime".

---

## 7. Hand-off to the development cycle

The conclusion of this review (B2 + mechanical fixes for #49/#50/#51 + master sync) is implemented as the **M1H
development cycle** (a separate cycle from M1G). New `LRR_DESIGN_P1_M1H.md` and `LRR_IMPLEMENTATION_STEPS_P1_M1H.md` are
created; after passing `run-mvn-verify` (CI-parity gate = full tests + static gates) and all `run-e2e`,
`LRR_RESULT_P1_M1H.md` is created and the plugin + notes are committed (no push).
