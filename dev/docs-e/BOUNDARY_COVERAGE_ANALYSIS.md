# Boundary coverage analysis (data / time / scale)

An inventory of the remote lock E2E suite against one question: does it cover the boundaries of
data, of time, and of scale? The subjects are `dev/jenkins-env/` (run-e2e.sh / scenarios / lib) and
the remote package of the `lockable-resources-plugin` under test.

Written 2026-08-10 / plugin under test: `aa0c391` (through Phase C)

---

## 1. Conclusion

**S01–S22 were close to complete as a demonstration that the feature works, and close to empty on
all three boundary axes.** All 22 scenarios pass correct values, at normal timing, at small scale.

- **Data boundaries**: every scenario goes through `lock()`. A client only ever sends a well-formed
  request, so **the entire rejection half of the API contract - status plus errorCode - was
  unverified.** The 1 MiB body cap and the explicit `heartbeatIntervalSeconds` validation are among
  several boundaries **written in the code with not one test against them**.
- **Time boundaries**: the plugin has seven timing constants, and the tests referred to none of them
  by name - they were written as bare numbers like `sleep 25`. Move a constant and **the tests go
  quietly meaningless.** Scenarios exercising both sides of a boundary: zero.
- **Scale boundaries**: the load suite varies exactly one dimension, concurrency. Catalogue size,
  queue depth, number of polling clients and hold duration were all pinned at "a handful". The
  `GET /resources` endpoint added in M2/M3 - unpaged, and holding `syncResources` while it works -
  is **structurally scale-dependent** and was unmeasured.

Alongside the refactor, **seven scenarios B01–B07** were added to fill the most valuable of those
gaps. Beyond two defects in the harness itself (§5), they produced **one confirmed plugin defect
(F1: a remote allocate timeout that does not fire on its own deadline)** and three points that are
decisions rather than bugs (F1a / F2 / F3), in §4.

> F1 was not found by a test going red. It surfaced **while enumerating the boundaries by calling
> the API directly**, and the existing S18 could not have distinguished it by construction - see §4.

---

## 2. Where the boundaries are

Before writing any test, the boundaries were read out of the implementation. This is all of them.

### 2.1 Timing constants

| Constant | Value | Source | Meaning |
|---|---|---|---|
| `DEFAULT_POLL_INTERVAL_SECONDS` | 3s | `RemoteClientDefaults` | interval between acquire-status polls |
| `DEFAULT_HEARTBEAT_INTERVAL_SECONDS` | 10s | `RemoteClientDefaults` | interval between lease renewals |
| `DEFAULT_REQUEST_TIMEOUT_SECONDS` | 5s | `RemoteClientDefaults` | timeout of a single HTTP call |
| `MAX_CONSECUTIVE_POLL_FAILURES` | 20 (≈60s) | `RemoteLockSession` | consecutive poll failures tolerated |
| `STALE_THRESHOLD_MS` | 60s | `RemoteLockManager` | grace between the last heartbeat and STALE |
| `TERMINAL_TTL_MS` | 120s | `RemoteLockManager` | how long a terminal record stays observable |
| `TTL_MILLIS` (catalog) | 10s | `RemoteCatalogCache` | freshness of the client-side catalogue |

→ Collected by name in `lib/timings.sh`, which **re-reads the plugin source on every run and stops
if they have drifted** (`rlr_check_timing_drift`). Move a constant now and the run halts.

### 2.2 Data validation points (`RemoteApiV1Action` / `RemoteQueueEntry`)

| Input | What the implementation does |
|---|---|
| body is not JSON | 400 `INVALID_JSON` |
| `lockRequest` missing / not an object | 400 `MISSING_LOCK_REQUEST` |
| no target / resource+label together / unknown strategy / priority+inversePrecedence | 400 `INVALID_REQUEST` (canonical validator) |
| `extra[i]` has neither resource nor label | 400 `INVALID_EXTRA` |
| `heartbeatIntervalSeconds` ≤ 0 or non-integer | 400 `INVALID_HEARTBEAT_INTERVAL` |
| body > 1 MiB | 413 `PAYLOAD_TOO_LARGE` |
| unknown / unexposed resource or label | 404 `UNKNOWN_RESOURCE` / `UNKNOWN_LABEL` |
| `quantity` non-numeric or negative | **no validation** (`optInt` defaults to 0 → "all matching" for a label) |
| `timeoutUnit` not a TimeUnit | **no validation** (deadline becomes 0 = wait forever) |
| `timeoutForAllocateResource` ≤ 0 | wait forever (same as local `lock()`, deliberate) |

---

## 3. The gaps on each axis, and how they were filled

### 3.1 Data

**What was empty** (all newly covered by B01 / B03):

| Angle | Before | Now |
|---|---|---|
| The rejection contract (status paired with errorCode) | unverified; `lock()` only ever sends well-formed requests | **B01**: 13 rejections verified as status/errorCode pairs |
| 1 MiB body cap | unverified (the constant existed alone) | **B01**: **both sides** - exactly 1 MiB = 202, one character more = 413 |
| `heartbeatIntervalSeconds` validation | unverified, despite dedicated validation code | **B01**: 0 / negative / non-integer |
| Behaviour of unvalidated values | unverified and undocumented | **B01**: recorded as observations (F1/F2 in §4) |
| Resource name encoding | lowercase letters and hyphens only | **B03**: spaces / multibyte / 244 characters / commas |
| Separator collision in the combined variable | unverified | **B03**: measured the ambiguity of a name containing a comma (F3) |

**Not started, in priority order**:

1. **`extra` at scale** (10 entries / 50 entries), and **main and extra naming the same resource**.
   The latter can become a self-wait inside a single lease.
2. **`variable` expanding past ten** (ordering and naming from `V10` on). Nothing has exercised more
   than three so far.
3. **Exposure when `exposeLabel` is empty.** One setting that can mean "expose everything" or
   "expose nothing"; a large blast radius for a single value.
4. **Changing a resource definition while it is held**: removing its exposeLabel, deleting it,
   reserving it.
5. **`clientId` reaching the UI.** C2 renders `heldByClientId` on the page, so a client-supplied
   string now has a path to the server's own UI. The escaping boundary needs checking.

### 3.2 Time

**What was empty**:

| Angle | Before | Now |
|---|---|---|
| Dependence on the constants | bare numbers like `sleep 25`; a constant moving would silently void them | `lib/timings.sh` plus drift detection; S11/S13/S18 rewritten to derive from the constants |
| Both sides of `TERMINAL_TTL` (120s) | S18 covered only "waited longer than the TTL" | **B02**: inside the TTL = 200 `FAILED`+`RELEASED`, past it = 404 |
| Lease calls in the wrong state | unverified | **B02**: heartbeat/poll/release on an unknown id, double release, heartbeat after release, heartbeat on a QUEUED request |
| Withdrawing a QUEUED request | unverified | **B02**: release removes it from the queue, and it is not promoted afterwards |
| Catalogue TTL (10s) | unverified | **B04**: stale inside the TTL / follows past it / still renders while the server is down |
| **Aborting a build** | unverified | **B05**: abort while QUEUED leaves no ghost lock; abort while ACQUIRED releases without waiting for STALE |

**Not started, in priority order**:

1. **Both sides of `MAX_CONSECUTIVE_POLL_FAILURES`** (20 ≈ 60s). Nineteen failures then a recovery
   should keep the lock; the twentieth fails closed. This is **the client's only threshold for
   giving up** and it has no test at all. It is a different path from heartbeat failure (S11).
2. **Just under and just over the STALE threshold.** S11 covers an outage shorter than STALE, S13
   covers reaching STALE, neither sits near the boundary. In particular **a heartbeat that resumes
   after STALE** (410 `LOCK_STALE`) has no client-side coverage.
3. **A client holding across a server restart.** `RemoteLockManager`'s records are in memory, so a
   restart loses the record while the resources come back from XML. The client's poll should 404 and
   fail closed, but **whether the resource is left locked is unconfirmed.** This is the most likely
   event in production.
4. **Release racing queue promotion.** `RemoteLockManager.release()` carries a comment saying that
   promoting a QUEUED entry concurrently would produce an orphan remote lock - a resource pinned
   with no way back - and guards it with `syncResources`. **A known danger, named in the code, with
   no test aimed at it.**
5. **FIFO fairness within one priority.** S12 covers priority inversion; order among N entries at
   the same priority is unverified.

### 3.3 Scale

**What was empty**:

| Dimension | Load suite | E2E | Now |
|---|---|---|---|
| Concurrent clients | up to 200 in G01 | — | already covered |
| **Catalogue size** | fixed (50/controller) | fixed (a few) | **B06**: response time, size and completeness at 100 / 500 / 2000 |
| **Discovery interfering with acquire** | unmeasured | unmeasured | **B06**: median acquire while four clients pull the catalogue |
| **Queue depth** | effectively a few | 1–2 | **B07**: promotion throughput and fairness at 1 / 10 / 50 |
| Resources per request | 1–2 | up to 3 | not started |
| Duration (leaks) | — | — | not started (L03 is specification only) |

**B06 measurements** (this environment, this point in time - a baseline):

| Catalogue size | `GET /resources` | Response size | Completeness |
|---|---|---|---|
| 100 | 12 ms | 15 KB | 100/100 |
| 500 | 21 ms | 53 KB | 500/500 |
| 2000 | 42 ms | 197 KB | 2000/2000 |

Median acquire+release: **71 ms idle → 111–119 ms while four clients repeatedly pull a 2000-entry
catalogue = about 1.6×**.

→ At 2000 entries the cost is linear and the degradation gentle; **there is no cliff today**. The
interference is real and measurable, though, because `describe()` serialises the whole catalogue
inside `syncResources`. If thousands to tens of thousands are ever in view, that 1.6× is **the
baseline a regression would be measured against**.

**B07 measurements** (same conditions):

| Queue depth | Promotion latency (release → next holder), two runs | Drain time (all) | Fairness |
|---|---|---|---|
| 1 | 50 / 55 ms | 0.05 s | 1/1 |
| 10 | 54 / 106 ms | 4.5–5.4 s | 10/10 |
| 50 | 125 / 99 ms | 15.1–16.5 s | 50/50 |

→ **Promotion latency does not depend on depth.** Depth 50 beat depth 10 in one run (99 ms vs
125 ms), so the spread is noise rather than depth. Fifty entries queued behind the next one does not
change what it costs to promote it: **no second-order cost from rescanning the queue.** No
starvation either - accepted and served match at every depth.

> **A caveat about the measurement**: drain time is not a server metric. Each promotion waits for the
> previous client to notice and release, so the client's detection interval (0.5 s here) is added per
> entry. The first version of this scenario **scanned every waiting id in one loop**, needing O(N²)
> requests to watch a depth of N: the 33-second drain at depth 50 was almost entirely the harness
> polling itself (15 s after the fix). Each waiter now has one client watching only its own lease.

**Not started, in priority order**:

1. **Polling load.** A waiting client polls every 3 s and a holder heartbeats every 10 s. Two hundred
   waiters is about 66 req/s of pure polling, each request passing `checkPermission`. **Where a poll
   response starts exceeding 5 s (`DEFAULT_REQUEST_TIMEOUT_SECONDS`)** matters, because past that
   point the consecutive-failure counter starts turning.
2. **Soak and leaks.** Whether `RemoteLockManager`'s record map and `RemoteClientRegistry`'s entries
   return to baseline after a long stretch of high turnover. **L03 `sustained-soak` is specified but
   unimplemented** (§6). The `RemoteClientRegistry` added in C1 depends on `forget()`, so any failure
   path that skips `forget` is a leak.
3. **Thundering herd on recovery.** N clients waiting through a server outage all arrive at once when
   it returns.
4. **Acquire latency against resources per lease** (taking 40 at once by label, say).

---

## 4. Findings from the measurements

All confirmed by running B01/B03. Listed **as points to decide rather than as bugs**.

### F1: a remote allocate timeout does not fire on its own deadline (priority: high, **confirmed → fixed**)

**`timeoutForAllocateResource` is not an upper bound on waiting for a remote lock.** The deadline is
computed correctly, but nothing is scheduled to come and evaluate it, so **it fires only when
something else happens to sweep the queue.**

Four pieces of evidence:

1. **Asymmetry in the code**: the local path calls `scheduleTimeoutAt(deadline)` in two places - at
   the end of `queueContext()` and at the end of `getNextQueuedContext()` - and so wakes itself at
   the deadline. The remote path (`queueRemote()` / `getNextRemoteEntry()`) has **no counterpart**.
   `RemoteQueueEntry.isTimedOut()` is only evaluated when `getNextRemoteEntry()` is called.
2. **The plumbing is fine**: `RemoteLockManager.enqueue()` passes `timeoutForAllocateResource` and
   `timeoutUnit` into `RemoteQueueEntry` correctly and the deadline is computed. **Nothing was
   forgotten in the hand-off; the wake-up is missing.**
3. **Direct experiment**: acquire a held resource with `timeoutForAllocateResource: 5,
   timeoutUnit: "SECONDS"` → **still QUEUED after 60 seconds** (twelve times the deadline), with
   nothing touching the queue in between.
4. **What S18 measured**: the lateness tracks the hold, not the deadline. Hold 144 s against a 124 s
   deadline → failed at 149 s (25 s late). Stretch the hold to 184 s → **failed at 183 s (59 s
   late)**.

Impact: a client that asked for a bounded wait waits indefinitely unless the resource is released.
Against a STALE hold (waiting on an administrator) or a long build, `timeoutForAllocateResource` is
effectively inert.

Why the existing tests missed it - the same blind spot in both layers:

- **E2E**: S18 held for 144 s against a 124 s deadline and asserted `>= 120s`, so it **could not
  distinguish failing at the deadline from failing at the release.** The hold is now the deadline
  plus 60 seconds, which separates them, and CP08 is a hard assertion.
- **Unit**: the existing timeout test in `RemoteLockManagerTest` **called `manager.checkTimeouts()`
  by hand** - the test standing in for something production code never does.

**The fix, two places in `LockableResourcesManager`**:

1. `queueRemote()` - schedule a wake-up when the deadline is earlier than the current one, as local
   `queueContext()` does.
2. `getNextQueuedContext()` - compute the earliest deadline **across both queues** (new
   `earliestRemoteDeadline()`).

The second is required. `scheduleTimeoutAt()` **cancels the pending task before rescheduling**, so
recomputing from the local queue alone deletes the wake-up the remote side was relying on and never
puts it back. The first alone does not fix it.

**Regression test**: `queuedRequestTimesOutOnItsOwnDeadlineWithoutOutsideHelp` - it neither calls
`checkTimeouts()` nor releases anything. Before the fix: `expected: <FAILED> but was: <QUEUED>`
(still QUEUED ten seconds after a 500 ms deadline).

### F1a: an invalid `timeoutUnit` turns into "no timeout" (priority: medium, **fixed**)

`RemoteQueueEntry` catches the `IllegalArgumentException` from `TimeUnit.valueOf(timeoutUnit)` and
sets `deadlineMs = 0`. `isTimedOut()` requires `timeoutDeadlineMillis > 0`, so **0 means "no
deadline" - wait forever.**

A typo of `timeoutUnit: "MINUTE"` (for `MINUTES`) therefore **turns a request that should give up
after five minutes into one that waits indefinitely.** And the request is accepted with 202, so the
pipeline is given no clue.

The asymmetry is the argument: the same class of typo in `resourceSelectStrategy: "NOPE"` is
rejected with 400 `INVALID_REQUEST`. Letting one through silently is not consistent.

> Distinct from F1. F1 is "the deadline is never scheduled" and happens with a correct unit; F1a is
> "the deadline is zero to begin with". Fixing F1 left F1a standing.

**Classification (decided 2026-08-11)**: locally, `LockStep.setTimeoutUnit()` **validates and
throws** (from #1010), so **it cannot happen locally**. The equivalent branch in
`QueuedContextStruct` is unreachable defence from the DSL. The remote path reads from JSON and
arrives without passing the `LockStep` setter, reaching a branch that was supposed to be
unreachable. Since **#1055 is what created an input path with no validation**, this is category ①
and is fixed in this PR.

**Fix = the same commit as F2a (A7)**: strict JSON parsing in `RemoteApiV1Action`. A value that
cannot be interpreted is no longer coerced to a default; it is **400 `INVALID_FIELD_VALUE`**.

### F2a: a non-numeric `quantity` turns into "lock everything" (priority: medium, **fixed**)

`optInt("quantity", 0)` returns its default of 0 for anything it cannot interpret, and for a label
request 0 means "all matching" - the correct behaviour, verified by S15. So a request that meant
`quantity: "2"` but got the type wrong **locks the whole pool instead of one machine.**

The problem is the direction: it fails **towards a wider request** rather than towards a rejection.
Quietly worse than failing.

**Classification**: `quantity` is an `int` locally. The DSL fails on type conversion, and the
freestyle String path throws from `Integer.parseInt`. **The path where a bad value silently becomes
"everything" exists only over remote**, and that JSON parsing is code #1055 added → category ①,
fixed in this PR (A7).

**F2b (negative values) is out of scope**: `if (quantity > 0)` in `LockableResourcesStruct` comes
from `e8425b5` (the Label/Quantity extension, before #1055), and `quantity <= 0` meaning "all" is the
shared path's specification. Local `lock(label:'x', quantity:-1)` behaves the same → category ②,
ignored.

### F3: a comma in a resource name makes the combined variable ambiguous (priority: low–medium, **out of scope**)

`lock(variable: 'V')` joins the acquired resource names with commas into `V` (verified by
S10/S14/S15). If a name contains a comma the result is ambiguous. Measured in B03:

- resources locked: 1 (`b03-comma,inside-<stamp>`)
- `V.split(',')`: **2 elements**, neither of which is a real name
- `V0`: correct

**Classification**: `String.join(",", ...)` has been there since `018e913^` (before #1055 merged),
and local and remote now simply share the same `buildLockEnvVars()`. Local
`lock(resource:'a,b', variable:'V')` does the same → category ②, **no implementation change**.

The indexed variables (`V0`, `V1`, …) are unaffected, so **documentation avoids the harm**. Saying in
the README that multiple resources should be read from `V0..Vn` rather than by splitting `V` is the
smallest sufficient fix. Validating commas out of names would have to match local `lock()`, which is
a much wider change.

---

## 5. Defects found in the harness (fixed here)

### H1: a failing scenario left nothing in the report

All 22 scenarios generated `scenario-details.md` from a heredoc at the end of the script, with `PASS`
**written literally** into the checkpoint table. Which means:

- on success: a table of "PASS" that was never computed
- **on failure: the end of the script is never reached, so no file is written at all** - the report
  says only "Details file is not available"

The structure removed the most information exactly when it was most needed. `lib/scenario.sh` now
records at the point of judgement and writes from an EXIT trap, so the file always exists. An
unexpected stop from `set -e` is recorded too, as an ABORT row naming the step it died in.

### H2: S08 was holding a resource from a previous run

S08 used the fixed label `hw`. Label acquisition matches across runs, so it was **holding the
`s08-hw-board-<old stamp>` left behind by an earlier run.** The old assertion was a prefix match on
`^HW_LOCK=s08-hw-board-`, which passed either way.

Tightening it to an exact match caught this during verification
(`expected=...1786369030 actual=...1786367567`). S14/S15 already used stamped labels; S08 was the one
that got missed. It now uses a stamped label, plus `drop_resources` to clean up after itself.

> Incidentally this is **also a scale problem**: E2E adds resources on every run, so the catalogue
> grows monotonically across consecutive runs that skip `start.sh --clean`.

---

## 6. An adjacent known gap: L01–L03 of the load suite are unimplemented

`LOAD_TEST_SPECIFICATION.md` defines L01 `contention-storm`, L02 `throughput-acquire` and L03
`sustained-soak` alongside G01, but `run-load.sh` merely assigns `ONLY="grid-storm"`: it **never
parses `--only` and never reads `$ONLY`**. All three are specification with no implementation.

Of these, **L03 `sustained-soak` is precisely the "duration / leak" line of §3.3** and the most
directly missing piece of the scale axis.

---

## 7. The B series

| ID | Scenario | Axis | What it verifies | Runtime |
|---|---|---|---|---|
| B01 | `acquire-payload-boundaries` | data | 13 rejections (status+errorCode), both sides of the 1 MiB cap, 4 unvalidated values observed | ~3 s |
| B02 | `lease-lifecycle-edges` | time | heartbeat/poll/release in the wrong state, double release, withdrawing a QUEUED entry, both sides of TERMINAL_TTL | ~2.5 min |
| B03 | `resource-name-boundaries` | data | spaces / multibyte / 244 characters / commas, round-tripped, and catalogue sanity | ~1 min |
| B04 | `catalog-cache-ttl` | time | held inside the TTL / follows past it / still renders while the server is down / recovers | ~1.5 min |
| B05 | `acquire-abort-races` | time | abort while QUEUED leaves no ghost lock; abort while ACQUIRED releases before STALE | ~1.5 min |
| B06 | `catalog-scale` | scale | response time, size and completeness at 100/500/2000; acquire latency under discovery load | ~2 min |
| B07 | `queue-depth-scale` | scale | promotion throughput and fairness (starvation) with 1/10/50 waiting on one resource | ~2 min |

Run with `./run-e2e.sh --only boundary` (the series column of `lib/scenarios.tsv`).

B01 runs 21 checkpoints in under three seconds. **A boundary test that calls the API directly is
orders of magnitude cheaper than a scenario driven through a pipeline, so the data axis is where
thickening the suite pays best.**

---

## 8. What to do next, in priority order

| # | Item | Axis | Why |
|---|---|---|---|
| 1 | Both sides of `MAX_CONSECUTIVE_POLL_FAILURES` (recover at 19 / fail closed at 20) | time | The client's only threshold for giving up. Zero tests |
| 2 | A client holding across a server restart | time | The most likely event in production. In-memory records against resources in XML |
| 3 | Release racing queue promotion | time | A known danger the implementation's own comment calls unrecoverable |
| 4 | Implement L03 `sustained-soak` | scale | Specified, unimplemented. Leak detection for the record map and the registry |
| 5 | Exposure when `exposeLabel` is empty | data | One setting with the largest blast radius |
| 6 | Escaping of `clientId` where the UI renders it | data | A path C2 newly created |

---

## References

- `dev/docs-e/E2E_TEST_SPECIFICATION.md` — scenario specification (S01–S22)
- `dev/docs-e/LOAD_TEST_SPECIFICATION.md` — load specification (G01 implemented / L01–L03 not)
- `dev/jenkins-env/lib/scenarios.tsv` — the scenario registry (id / series / controllers / axis)
- `dev/jenkins-env/lib/timings.sh` — timing constants and drift detection
- `dev/jenkins-env/lib/scenario.sh` — checkpoint recording and details generation
