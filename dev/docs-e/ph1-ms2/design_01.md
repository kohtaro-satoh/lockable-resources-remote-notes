# Remote LR design (Phase 1 / M2 + M3 combined, plus the M1 leftovers)

> **Position:** the design of the next PR, built from the point where PR
> [#1055](https://github.com/jenkinsci/lockable-resources-plugin/pull/1055) (Phase 1 / M1) merged
> into `master`. It **combines M2 and M3 of issue
> [#1025](https://github.com/jenkinsci/lockable-resources-plugin/issues/1025) into one** and picks up
> **what M1 left behind**.
> **Written:** 2026-07-26 / **Last updated:** 2026-08-05
> **Base commit:** #1055 **merged into `jenkinsci:master` on 2026-08-04** (merge commit `018e913`,
> merged by mPokornyETM). The implementation statements here were checked against
> `upstream/master` = `011c6a3` (which contains `018e913`).
> **Authoritative specification:** the "Configuration surface" … "Phase 1 scope" sections of the
> #1025 issue body.
> **Related:** the M1 design spec ([published on the 1055 branch](https://github.com/kohtaro-satoh/lockable-resources-remote-notes/blob/docs/remote-lr-pull-1055/dev/docs-j/LRR_DESIGN_P1_M1.md);
> its §4 already announces the API this document fills in as "M3 and later"), and
> `LRR_REVIEW_UPSTREAM_FOLLOWUP_UX.md` §13.3 (development branch only) for the list of leftovers and
> where each one goes.

---

## Contents

1. [Purpose and scope](#1-purpose-and-scope)
2. [The gap today: specification vs implementation](#2-the-gap-today-specification-vs-implementation)
3. [Design A: the server-side additions](#3-design-a-the-server-side-additions)
4. [Design B: the client side (connection settings and the LR page)](#4-design-b-the-client-side-connection-settings-and-the-lr-page)
5. [Design C: the delegated-mode display switch (M2 proper)](#5-design-c-the-delegated-mode-display-switch-m2-proper)
6. [Picking up the M1 leftovers](#6-picking-up-the-m1-leftovers)
7. [What to do about specification/implementation divergence](#7-what-to-do-about-specificationimplementation-divergence)
8. [Not included](#8-not-included)
9. [Test plan](#9-test-plan)
10. [Open items to settle before implementing](#10-open-items-to-settle-before-implementing)
11. [Change log](#11-change-log)

---

## 1. Purpose and scope

### 1.1 Why M2 and M3 become one PR

The milestones in issue #1025 are defined as:

```
Phase 1 — Remote lock via REST + transparent DSL + remote resource list view
  M1: Core REST API + explicit lock(..., serverId: 'X')   ← done in #1055
  M2: forcedServerId resolution and the LR page mode-switching behavior
  M3: GET /resources and the client-side LR page integration with the remote view
```

**The DSL half of M2 - delegated routing through `forcedServerId` - was implemented early, in M1**,
and E2E `delegated-mode` (S09) guards it. What is left of M2 is **only the LR page's mode-switching
display**, and that cannot be built without `GET /resources` (M3).

→ **The remainder of M2 and M3 are inseparable.** Splitting them would mean shipping one PR in a
state that does not work, so they are combined.

### 1.2 Scope

| Part | Contents |
|---|---|
| **A. Server-side API** | **`GET /resources` and nothing else** (narrowed on 2026-08-05). The first draft also listed `GET /lease/{lockId}` and `POST /acquire/{lockId}/cancel`, but the M1 design spec had already decided the former was "a candidate for after M1" and the latter "dropped, folded into release" - neither was unimplemented work ([§3.2](#32-get-leaselockid-is-not-added-decided-2026-08-05) / [§3.3](#33-the-queued-path-of-release-and-what-happens-to-cancel)). The **maintenance switch Martin asked for is also pulled forward into Phase 1** ([§3.4](#34-maintenance-switch-accept-new-acquires-onoff)) |
| **B. Client-side LR page** | Make "the remote locks this controller holds or waits for" visible on the initiating controller. The largest UX gap, named as a Known limitation in PR #1055 |
| **C. Delegated-mode display switch** | With `forcedServerId` set, the LR page shows the remote server's published resources **alongside** the local ones, with a delegated badge ([§5.0](#50-from-replacement-to-coexistence-a-change-of-direction) changed this from "replace") |
| **D. M1 leftovers** | [§6](#6-picking-up-the-m1-leftovers). No separate PR; they ride along with this one |

With this, **Phase 1 can be declared to satisfy the whole "Phase 1 scope" of the issue body.**

### 1.3 What it takes to tick the Phase 1 checkbox

The `- [ ] Phase 1` in the Phases section at the end of #1025 **still cannot be ticked after #1055
merged.** As judged on 2026-08-05:

| Item in the issue body | Verdict | Basis |
|---|---|---|
| M1: Core REST API + explicit `serverId` | ✅ | #1055 |
| M2: `forcedServerId` resolution **and the LR page mode-switching behavior** | ⚠️ half | Resolution logic only; the LR page side is unimplemented ([§5](#5-design-c-the-delegated-mode-display-switch-m2-proper)) |
| M3: `GET /resources` + client-side LR page integration | ❌ | Not started ([§3.1](#31-get-resources) / [§4](#4-design-b-the-client-side-connection-settings-and-the-lr-page)) |
| Phase 1 scope: "LR page integration on **both** sides" | ⚠️ half | Server side only |

→ **A through C in this document are what make it tickable.** Put the other way round, this PR is
the only work standing between here and declaring Phase 1 complete.

> **A note on naming:** earlier notes and some comments on PR #1055 called this work "Phase 2". By
> the definition in the issue body it is **M2 + M3 of Phase 1**. Phase 2 in the body means the
> operational features (maintenance switch / making the polling values configurable / client
> allow-list - [§8](#8-not-included)). In anything written for an outside audience, say "remaining
> Phase 1 work (M2+M3)".

---

## 2. The gap today: specification vs implementation

The difference measured from `master` after #1055 merged. **The rows marked "missing" are what this
document designs.**

### 2.1 REST endpoints

| Specification (#1025) | Implementation | Notes |
|---|---|---|
| `POST /acquire` | ✅ | `heartbeatIntervalSeconds` is accepted and ignored (deliberate, [§7.2](#72-heartbeatintervalseconds-is-ignored)) |
| `GET /acquire/{lockId}` | ✅ | Returns `RemoteLockState`. `CANCELLED` / `EXPIRED` never come back |
| `POST /acquire/{lockId}/cancel` | — | **Not added.** Dropped in M1, folded into release: [§3.3](#33-the-queued-path-of-release-and-what-happens-to-cancel) |
| `GET /lease/{lockId}` | — | **Not added.** M1 decided it was "a candidate for after M1": [§3.2](#32-get-leaselockid-is-not-added-decided-2026-08-05) |
| `POST /lease/{lockId}/heartbeat` | ✅ | |
| `POST /lease/{lockId}/release` | ⚠️ | For a QUEUED request it goes terminal and deletes the record immediately → the next GET is a 404. **Changed to hold for the TTL** ([§3.3](#33-the-queued-path-of-release-and-what-happens-to-cancel)) |
| `GET /resources` | **missing** | [§3.1](#31-get-resources) |
| *(not in the spec)* maintenance switch | **missing** | Martin's request, pulled into Phase 1: [§3.4](#34-maintenance-switch-accept-new-acquires-onoff) |

`RemoteApiV1Action#getDynamic` currently branches on `acquire` and `lease` only; `resources` has to
be added.

> **On terminology:** the table above uses the implementation's name (`lockId`). The issue body calls
> them `requestId` on the acquire side and `leaseId` on the lease side, **as two different ids**; the
> implementation settled on a single `lockId`
> ([§7.5](#75-requestid--leaseid-were-unified-into-lockid)).

### 2.2 Configuration and UI

| Specification (#1025) | Implementation | Notes |
|---|---|---|
| `remoteApiEnabled` / `exposeLabel` (server side) | ✅ | `exposeLabel` was **extended to an OR of several labels** (M1E, [§7.1](#71-exposelabel-was-extended-to-several-labels)) |
| `remotes[]` / `forcedServerId` (client side) | ✅ | Existence checking for `forcedServerId` is implemented too |
| Delegated routing through `forcedServerId` | ✅ | Implemented early in M1 (E2E S09) |
| clientId of a remote lease shown on the **server-side** LR page | ✅ | M1B Step 6, plus Martin's follow-up added the Held By column |
| The remote view on the **client-side** LR page | **missing** | [§4](#4-design-b-the-client-side-connection-settings-and-the-lr-page) |
| **Delegated-mode badge** | **missing** | [§5](#5-design-c-the-delegated-mode-display-switch-m2-proper) |

---

## 3. Design A: the server-side additions

**One new endpoint, `GET /resources`** (a `resources` branch in
`RemoteApiV1Action#getDynamic`). **Authorization and the enablement gate are exactly the same shape
as the existing four** (`Jenkins.get().checkPermission(REMOTE)` → `isRemoteApiEnabled()` → body).
On top of that, the server side has the `release` fix for the QUEUED path
([§3.3](#33-the-queued-path-of-release-and-what-happens-to-cancel)) and the maintenance switch
([§3.4](#34-maintenance-switch-accept-new-acquires-onoff)).

### 3.1 `GET /resources`

Returns the published resources and **the server's own acceptance state** in one snapshot.

```jsonc
// GET /lockable-resources/remote/v1/resources  -> 200
{
  "acceptNewAcquires": false,          // state of the maintenance switch (§3.4)
  "resources": [
    { "name": "plc-01", "labels": ["plc", "remote-enabled"], "description": "PLC 01",
      "state": "LOCKED", "heldByKind": "REMOTE_CLIENT", "heldByClientId": "jenkins-c",
      "since": 1785026807000, "queuedCount": 2 },
    { "name": "plc-02", "labels": ["plc", "remote-enabled"], "description": "",
      "state": "FREE" }
  ]
}
```

#### It returns state after all (direction changed 2026-08-08)

The first draft, and the issue body, said **state would not be included** (to keep the response cheap
and cacheable). **That is withdrawn.** The client-side LR page wants to show **local and remote
resources with comparable information** ([§5.1](#51-what-changes-in-the-display)), and without state
one half of the table is thin.

`state` uses the same four values as the local Resources tab: **`FREE` / `LOCKED` / `RESERVED` /
`QUEUED`** (matching `resource.status.*` in `table.properties`; `QUEUED` = somebody is waiting).

**The disclosure level takes the middle option (decided 2026-08-08).** The `Held By` column of the
local table really holds **that server's build name** (`job/foo #12`), and `Reason` and `note` are
free text. Returning those would mean **B's job names become visible to everyone who can view A's LR
page.** B's administrator opted in to *publishing resources*, not to publishing job names, and the
`RemoteUse` permission is separate from READ on B as a whole. So **no identifiers: only the kind of
holder and how long it has been held.**

| Field | Contents |
|---|---|
| `state` | `FREE` / `LOCKED` / `RESERVED` / `QUEUED` |
| `heldByKind` | `LOCAL_BUILD` / `REMOTE_CLIENT` / `ADMIN` (when `RESERVED`). Omitted when `FREE` |
| `heldByClientId` | Only when `heldByKind = REMOTE_CLIENT`. **This is a remote client's name, not one of B's job names.** A can compare it with its own `clientId` and tell "that one is mine" |
| `since` | When it was acquired or reserved (epoch ms). A number, so no disclosure risk, and it raises the perceived information a great deal |
| `queuedCount` | Number waiting (may be omitted when 0) |

**Not returned:** build name, build URL, `reason`, `note`. If they are ever needed, the way to do it
is an opt-in on B's side to publish detail as well.

#### Why `acceptNewAcquires` rides in the same response

During maintenance the page should say "the resources are visible but cannot be locked"
([§3.4](#34-maintenance-switch-accept-new-acquires-onoff)). Splitting that into a second endpoint
would give **two caches that can disagree**, making it possible to render "shown as FREE while
acquires are in fact paused". One snapshot returning both means the page can only ever draw a
consistent pair. Keeping the endpoint named `resources` is fine: server metadata in the envelope is
an ordinary shape.

> **Important:** during maintenance **resource state still tells the truth** (FREE means FREE).
> "FREE but you cannot have it right now" is expressed **by the page**. Not bending the data means a
> client that ignores `acceptNewAcquires` still gets the state right.

#### Other points

- **Reuse the existing `getExposeLabels()` for the publication filter.** No new remote-specific test
  (keeping M1F's principle: do not add remote-specific decisions that are not about the bridge)
- When `remoteApiEnabled=false` it behaves **exactly like the existing four**, i.e. **403
  `REMOTE_API_DISABLED`**. The issue body says it should respond "as if the API did not exist"
  (= 404), but the implementation chose 403 back in M1. **Using 404 here would split the behaviour
  inside one API**, so the implementation's 403 wins and the issue body is what gets corrected
  ([§7.7](#77-remoteapienabledfalse-answers-with-403))
- No paging (small-to-medium scale assumed; thousands would be Phase 3)

#### Consistency with the "single source of truth" principle

The original reason for not returning state was that a client would be tempted to use it to decide
whether to lock. That is about **preventing future drift**; a Phase 1 client makes no availability
decision at all, it just POSTs, so the decision path does not exist. Two safeguards: (1) say it is
display-only, in a code comment and in the page's "client-side cached view" label, and (2) keep
"no code consumes this state to decide anything" as a review point.

### 3.2 `GET /lease/{lockId}` is not added (decided 2026-08-05)

The first draft listed it as "unimplemented work from the issue body". **That was wrong.** The M1
design spec already records it under out-of-scope as "`GET /lease/{lockId}` (a diagnostic endpoint) -
**a candidate for after M1**".

Why it stays out:

1. M1 already decided to defer it. It is not an oversight.
2. **`GET /acquire/{lockId}` answers for the same `lockId`**, so checking a held lock's state
   (`ACQUIRED` / `STALE`) is already possible. What it would add is `clientId` / `acquiredAt` /
   `lastHeartbeatAt` / the heartbeat and stale values - all of which are on the server-side LR page.
3. The client-side LR page is designed around its own registry
   ([§4.2](#42-where-the-data-comes-from)), so **it does not depend on this endpoint**.

**When to introduce it:** at the same time as making heartbeat / poll / timeout configurable. Only
once the values are configurable does "a way to read back the effective value" genuinely matter. Q3
in [§10](#10-open-items-to-settle-before-implementing) (whether to echo the requested value) gets
revisited then.

### 3.3 The QUEUED path of `release`, and what happens to `cancel`

**`POST /acquire/{lockId}/cancel` is not added (decided 2026-08-05).** The M1 design spec states
plainly that the **cancel endpoint was dropped**, with both abort and normal completion folded into
`POST /lease/{lockId}/release`, and that a `CANCELLED` state produced by the server or an
administrator can be received for compatibility but is never issued by a client. Classifying it as
"unimplemented" in the first draft was a mistake. In the implementation
`RemoteLockManager#release()` works on a QUEUED record too, so **cancelling is already release**.

**One real problem does remain, and only that is fixed.** Today `release()` calls
`markFailed("RELEASED")` on a QUEUED record and then `records.remove()` immediately, so **the record
disappears and the very next `GET /acquire/{lockId}` is a 404.** If something polls just after an
abort it hits the same "a 404 that does not describe reality" problem as
[§6-1](#6-picking-up-the-m1-leftovers).

| | Today | After |
|---|---|---|
| State transition | `FAILED("RELEASED")` → **record deleted at once** | `FAILED("RELEASED")`, **held for the terminal TTL (120s)** |
| The next `GET /acquire/{lockId}` | **404 LOCK_NOT_FOUND** | **200 `state=FAILED, errorCode=RELEASED`** |

**Design decision:** **no new `CANCELLED` state.** `RemoteLockState` stays as it is -
QUEUED/ACQUIRED/SKIPPED/FAILED/STALE - and the change is only to fold `records.remove()` into the
terminal-TTL sweep. That is consistent with M1's "a client never issues `CANCELLED`" and is the
smallest possible change. (`RemoteAcquireState.CANCELLED` and the `case CANCELLED` in
`RemoteLockSession` stay, as compatibility for a future server-side or administrative cancel.)

### 3.4 Maintenance switch: "accept new acquires: ON/OFF"

**Moved from a Phase 2 candidate into Phase 1** (2026-08-05). Martin asked for it in
[this comment on #1025](https://github.com/jenkinsci/lockable-resources-plugin/issues/1025#issuecomment-4365352278)
§8; it is small and it is his request, so it ships here.

**Server side:** add `acceptNewAcquires` (`boolean`, default `true`) to `LockableResourcesManager`,
with config.jelly + help + Messages + JCasC, the same shape as `remoteApiEnabled`. When OFF, **only
`POST /acquire`** returns 503 `ACQUIRES_PAUSED`; `GET /acquire/{lockId}`, heartbeat and release pass
through untouched (= leases in flight are undisturbed). A paused banner goes on the server-side LR
page, so an administrator does not forget to switch it back.

**Undecided (not asked; build it and present it in the PR - see
[§9.4](#94-running-old-and-new-side-by-side-for-the-pr-screenshots)):**

| # | Question | Our proposal |
|---|---|---|
| a | What a client does with a 503 | **Retry.** Today a failed `POST /acquire` is fail-closed and aborts at once, which does not deliver the point of the request ("A should not suffer while B is in maintenance"). Retry at the polling interval within `timeoutForAllocateResource`, logging INFO once |
| b | Requests already queued when it goes OFF | **Keep promoting them** (honour what was accepted; let the queue drain). Freezing them would leave waiting clients hanging until their timeout |

Build it that way and present it in the PR as "here is what it looks like - thoughts?". If he sees it
differently, swap it then.

### 3.5 Server-side order of judgement (Wire → Admission → Canonical)

Which layer judges an incoming `POST /acquire`, in what order. The aim is to **confine
remote-specific judgement to two thin layers and hand everything else to canonical** (settled
2026-08-08).

| Order | Layer | What it judges | On failure | Remote-specific? |
|---|---|---|---|---|
| 0 | Authorization | `checkPermission(REMOTE)` | **403** | — (Jenkins standard) |
| 1 | Enablement | `remoteApiEnabled` | **403** `REMOTE_API_DISABLED` | yes |
| 2 | Pause | `acceptNewAcquires` ([§3.4](#34-maintenance-switch-accept-new-acquires-onoff)) | **503** `ACQUIRES_PAUSED` | yes |
| 3 | **Wire** | JSON validity, field shapes, `heartbeatIntervalSeconds` | **400**, or **413** for an oversized body | yes (wire format) |
| 4 | **Admission** | Exposure filter and name existence | **404**, uniformly | yes (the bridge boundary) |
| 5 | **Canonical** | Handed to `LockStepResource.validate()` | **400** `INVALID_REQUEST` | **no judgement of its own** |

0 and 1 apply to every endpoint. 2 applies only to `POST /acquire` (heartbeat / release / GET pass
through).

**What Admission is responsible for:**

1. **The exposure filter** — only resources carrying an `exposeLabel` are visible from remote
2. **Name existence** — an unknown name is a 404 immediately
3. **No remote-created ephemerals** — as a consequence of 1 and 2, an unknown name never reaches
   canonical's `create=true` (LRM:1586). On the immediate-acquire path admission and resolution are
   **inside the same `syncResources` block** (`RemoteLockManager.enqueue`), so the guarantee holds
   strictly. **The exception is the queue-promotion path**, a known residue described in
   [§8.1](#81-record-of-the-m1e-1-orphan-ephemeral-re-examination-2026-08-08)

**The five checks handed to canonical** (`LockStepResource.validate()`): no target (honouring
`allowEmptyOrNullValues`) / `priority != 0 && inversePrecedence` / `label` and `resource` together /
label existence / validity of `resourceSelectStrategy`.

**Code that disappears from the remote side:** the hand-written `MISSING_TARGET` and
`INVALID_SELECT_STRATEGY` checks at the boundary. They are **a partial copy of canonical, and a
divergent one** - `MISSING_TARGET` ignores `allowEmptyOrNullValues`, so with that setting on **local
accepts a request that remote rejects with 400** (an existing break in transparent equivalence).
Handing over makes the remote-specific code **smaller** on balance.

**Three behaviours change:**

| Case | Today | After |
|---|---|---|
| `allowEmptyOrNullValues=true` with no target | 400 `MISSING_TARGET` | **accepted** (as local does) = the break is fixed |
| `priority != 0 && inversePrecedence` | accepted | **400** ([§10.1](#101-the-alternative-answer-to-q4-inverseprecedence-as-transparent-equivalence)) |
| `resource` and `label` together | accepted (M1E-2 residue) | **400** (as local does) |

**Why M1E-2 can be closed:** it was left open because closing it would have meant *adding* a
remote-specific check. In this arrangement it closes **as a side effect of removing remote-specific
code**, so the premise the decision rested on has inverted.

**Why Admission goes before Canonical:** canonical also checks label existence, so running it first
would make **an unknown label 400 and an unexposed label 404**, leaking existence (M1E's "uniform
404" would break). With Admission first, secrecy is **kept for free** while still handing off to
canonical. Secrecy does cost diagnosability (a 404 is ambiguous); if that is to be solved, the way is
an explicit split - **unexposed = 403 `NOT_EXPOSED` / unknown = 404** - as its own decision. Leaking
it as a side effect of validation order is the wrong way to get there.

**Implementation note:** order `RemoteLockManager.enqueue` as admission → canonical, and let
canonical's `IllegalArgumentException` **propagate**. `RemoteApiV1Action` catches it and answers 400
`INVALID_REQUEST` with `ex.getMessage()` (no record created = the same refusal-at-the-door as the
existing 400s). The admission 404 path keeps creating a record as it does now, which stays consistent
with the "`UNKNOWN_*` → 404, any other FAILED → 400" wiring added by M1F's L-d. If `extra` is to go
through canonical too, build `LockStepResource` from `RemoteLockRequest.ExtraResource` and call the
list overload (the same idea as `RemoteResolver.toRemoteStructs` mirroring `LockStep.getResources()`).

**One small point left:** the granularity of errorCode. Handing over to canonical collapses the
fine-grained codes such as `INVALID_SELECT_STRATEGY` into a single `INVALID_REQUEST`. The split is
errorCode for machine-readable meaning and the (localised) message for detail; the error table in
`remote-api-curl.md` gets updated. Reverse-mapping a code out of a message is brittle and is not on
the table.

---

## 4. Design B: the client side (connection settings and the LR page)

### 4.0 Per-connection enable/disable (`enabled`) — B5 (added 2026-08-10)

**Motivation:** the client side has no way to say "do not use this peer right now". The only options
are deleting the configuration or breaking the URL, and deleting loses the `credentialsId` binding
too. It is **the missing counterpart to B3's maintenance switch**: B3 is the owner of a resource
stopping new loans, this is the borrower stopping its use of a particular peer.

Add **`enabled` (default `true`)** to `RemoteConnection`, as a checkbox inside the Remote Server card.

**Semantics, four points:**

| # | Situation | Decision |
|---|---|---|
| a | `lock(..., serverId:'X')` naming a disabled server | **Fail immediately.** No fallback to local (the same principle as M1's "no implicit local resolution": it prevents "meant to take a remote one, took a local one") |
| b | Leases already held | **Do not cut them.** Heartbeat and release continue; cutting them strands the resource on the far side. The same "only new requests stop" asymmetry as B3 |
| c | `forcedServerId` naming a disabled server | Every `lock()` fails. The existing `doCheckForcedServerId` (which warns about an id not in remotes) **gains a warning for "it is disabled"** |
| d | How it looks in the Remote tab | Entries held against a disabled server remain, so **say that the server is disabled**. Without that, "why are no new locks appearing" has no answer |

**Implementation notes:**

- **Add it with `@DataBoundSetter`.** Growing the `@DataBoundConstructor` argument list breaks
  existing JCasC yaml that has only `serverId` / `url` / `credentialsId`
- Default `true` as a field initialiser (the style of `acceptNewAcquires` / `allowEphemeralResources`)
- **The CasC export expectation `casc_expected_output.yml` must be updated** (a trap already hit
  in B3)

**Why before C3:** C3 fetches `/resources` from the `forcedServerId` peer and displays it cached.
Bolting "do not fetch from, or show, a disabled server" on afterwards means going back through the
fetch and display code that was just written.

**Outward communication (user's decision, 2026-08-10):** this is not the kind of setting that needs
agreement in advance, so **explain it in the PR description** rather than proposing it on #1025 -
see also [§7.12](#712-the-client-side-gained-an-enabled-setting).

### 4.1 What is missing

Today, **the initiating controller has no visibility of remote locks at all.** Short of reading the
build log, there is no way to know which remote resources this controller holds or is waiting for.
That contrasts with the owning (server) side, whose dashboard was filled out in M1B and the M1
follow-up, and PR #1055 names it as a Known limitation.

### 4.2 Where the data comes from

The client-side state of a remote lock exists only inside `RemoteLockSession`, per step. Something
has to aggregate it across the controller.

| Option | What it is | Assessment |
|---|---|---|
| **(a) An explicit registry** (recommended) | A new `RemoteClientRegistry` (`@Extension`, transient). `RemoteLockSession` registers on acquire and deregisters on release or failure | Can express both waiting (QUEUED) and held (ACQUIRED). O(1) lookup. Re-registers from `onResume` after a restart |
| (b) Scan running builds | Walk `LockedResourcesBuildAction` on every `Run` | Holds no new state, but **cannot see waiting** (the action is attached after acquisition). Scanning is expensive too |
| (c) Ask the servers | `GET /resources` on each remote plus a lease listing | There is no "leases by client" API on the server side, and adding one is out of Phase 1 scope |

→ **(a) is chosen**: a **lightweight client-side registry**, the counterpart of the server-side
`RemoteLockManager`.

```
RemoteClientRegistry (transient, in-memory)
  key   : lockId
  value : serverId / what was requested (resource | label+quantity) / state (QUEUED|ACQUIRED)
          / acquired resource names / enqueuedAt / acquiredAt / the initiating build (a Run reference)
```

- **Not persisted.** After a restart it is rebuilt from `RemoteLockSession.onResume` (which holds
  both the QUEUED and ACQUIRED cases, so reconstruction is possible)
- In case the build is gone, the `Run` is held weakly alongside a snapshot of
  `getFullDisplayName()` (this also resolves M-1, "onResume degrades displayTarget" →
  [§6-9](#6-picking-up-the-m1-leftovers))

### 4.3 The display

Add a **"Remote locks" tab** to the LR page (or a section inside an existing tab). Adding **one** to
the tab layout introduced by PR
[#1035](https://github.com/jenkinsci/lockable-resources-plugin/pull/1035)
(Overview / Resources / Labels / Queue) is what fits the existing UI.

| Column | Contents |
|---|---|
| Server | `serverId` (the client-side alias) |
| Request | `resource=…` / `label=… quantity=…` |
| State | QUEUED / ACQUIRED |
| Resources | Acquired resource names (ACQUIRED only) |
| Requested by | The initiating build (linked) |
| Since | Elapsed time |

- **Say permanently, inside the tab, that this is a client-side cached view and not the remote's
  authoritative state** (an explicit requirement of the specification)
- **No actions** (cancel / release) from this screen. Phase 1 stops at visibility, avoiding the risk
  of a mis-click putting the pipeline and the state out of step (settled as Q2 in
  [§10](#10-open-items-to-settle-before-implementing); note that the cancel button was proposed only
  in our own notes - a search of every comment on #1025 / #1055 confirms **nothing was promised
  externally**)

---

## 5. Design C: the delegated-mode display switch (M2 proper)

When `forcedServerId` is set, the meaning of the LR page changes. The specification asks for three
things.

1. **A delegated badge**, so an administrator is not surprised by the change in resolution semantics
2. **Show the remote's published resources** (the result of `GET /resources`)
3. ~~**Indicate that the local resource definitions are "not used in delegated mode"** (hide them or
   say so)~~
   → **Changed 2026-08-05: do not hide them; show both.** See
   [§5.0](#50-from-replacement-to-coexistence-a-change-of-direction)

### 5.0 From "replacement" to "coexistence" (a change of direction)

Comment `4365352278` said the delegated-mode LR page would show **only** the remote's published
resources. **The display changes to coexistence** (the resolution rules do not change). Two reasons.

1. **A role belongs to a relationship, not to an instance** (the "Mutual sharing via multiple
   independent one-way relations" section of the issue body). A controller with `forcedServerId` set
   still has its **own resources locked by other controllers as usual**, given `remoteApiEnabled` +
   `exposeLabel`. Hiding the local rows removes from the page the resources somebody else is holding
   right now. The current wording makes delegated and server roles effectively exclusive, which
   contradicts the design as a whole.
2. **#1035 turned the page into tabs**, so both can be shown without ambiguity and without replacing
   anything.

The original reasons `4365352278` chose replacement - eliminating name collisions, preventing "meant
remote, took local" - **continue to be guaranteed by the resolution rules**: in delegated mode every
`lock()` goes remote, there is no fallback to a local definition, and an unknown name fails at once
with `UNKNOWN_RESOURCE`. The UI compensates by showing, per row, which side a name resolves to.

### 5.1 What changes in the display

| Mode | Resources tab (local resources) | Remote tab |
|---|---|---|
| **peer** (no `forcedServerId`) | as before | the remote locks this controller holds or waits for |
| **delegated** (`forcedServerId` set) | **still shown**, but marked "not used to resolve this controller's `lock()`; still lockable by other controllers" | the above, plus the published resources of `forcedServerId` (`GET /resources`) |

In delegated mode a badge sits permanently at the top of the page:

```
[ Delegated mode ] All lock() calls are routed to serverId = "b" (http://jenkins-b:8080/jenkins)
                   Local resources below are still lockable by other controllers.
```

### 5.2 A short-lived cache for `GET /resources`

Do not call the remote on every page view. Keep a **short-lived cache with a TTL** (default **10s**)
on the client side.

> **TTL changed (2026-08-08):** the first draft said 60s, but since
> [§3.1](#31-get-resources) now **returns state and `acceptNewAcquires`**, 60s is long enough to show
> something false (a FREE from a minute ago). Splitting the endpoint into "static catalogue 60s +
> state 5s" runs against the decision to add only one endpoint, and reintroduces cache inconsistency,
> so it is not taken. **One endpoint, TTL shortened to 10s** - once per remote per ten seconds, not
> once per page view.

- HTTP only on a cache miss. On a failed fetch, fall back to **the last content that was fetched,
  labelled "stale (last fetched N minutes ago)"** (fail-closed is about acquiring a lock; **display
  may be best-effort**)
- Discard the cache when the remote configuration (`remotes` / `forcedServerId`) changes
- Fetch **asynchronously**, not on the page's request thread, so the UI is not blocked

---

## 6. Picking up the M1 leftovers

Includes the items marked "rides on the Phase 2 PR" in `LRR_REVIEW_UPSTREAM_FOLLOWUP_UX.md` §13.3
(development branch only).

| # | Item | Source | What happens |
|---|---|---|---|
| 1 | **The twisted 404/410 labels in `RemoteLockSession`** | REVIEW_UPSTREAM §12.2 | **(a) unify them** (settled as Q1 in [§10](#10-open-items-to-settle-before-implementing); blame confirms every line of that branch is our own code, so this is not editing somebody else's). Reword the reachable `!bodyStarted` side towards "the record does not exist (the server may have restarted)", and note in a comment that a legitimate allocate timeout is already funnelled through the server-side FAILED path. Together with holding the QUEUED path of `release` for the terminal TTL ([§3.3](#33-the-queued-path-of-release-and-what-happens-to-cancel)), this **reduces the conditions under which a 404 appears at all** |
| 2 | **The state table in `remote-api-curl.md`** | REVIEW_UPSTREAM §12-8 | Remove the mistaken `EXPIRED` (the server never returns it; note it as a future slot for `maxWaitSeconds`), add `STALE`, and note that `heartbeatIntervalSeconds` is ignored server-side. **`CANCELLED` becomes real in this PR, so document it properly** |
| 3 | **The Change Position button in the Queue tab** | REVIEW_UPSTREAM §12-3/4 | Do not render the button on remote rows (exclude `item.type === "remote"` in JS). Also make clear that the position range is based on the local queue count |
| 4 | **Where `X_SERVER_ID` / `X_LOCK_ID` stand** | REVIEW_UPSTREAM §12.1 | **Keep them**, writing into the design ([§7.3](#73-the-x_server_id--x_lock_id-asymmetry)) that bridge-specific metadata is outside transparent equivalence |
| 5 | **Queue index ordering** | REVIEW_UPSTREAM §12-5 | Merge local and remote, sort by descending priority, then number them, so the order matches actual promotion (`proceedNextContext`) |
| 6 | **The Queue free-text filter** | REVIEW_UPSTREAM §12-6 | Add `getRemoteRequest()` / `getRequestedBy()` to the filter branch so it works on remote rows |
| 7 | **`withRemoteMetadata` drops out on an empty `lockEnvVars`** | REVIEW_UPSTREAM §12-7 | Move it out of the condition so a `variable` is always injected when one was asked for |
| 8 | **`inversePrecedence` is not applied to remote queue order** | Martin's `remote-api-curl.md` | **Reversed (2026-08-05): apply it.** Mirror local's insertion rule in `queueRemote`, and reject it together with `priority` as 400. In terms of transparent equivalence the current state is the duplicated rule ([§10.1](#101-the-alternative-answer-to-q4-inverseprecedence-as-transparent-equivalence)). The corresponding text in his doc needs updating after the change |
| 9 | **M-1: onResume degrades displayTarget** | REVIEW_P1_M1B | The registry in [§4.2](#42-where-the-data-comes-from) keeps the request, so this **resolves as a by-product** |
| 10 | **`lockCause` does not consider a remote holder** | this document (verified on a live instance 2026-07-26) | [§6.1](#61-lockcause-does-not-handle-remote-holders-added-here) |
| 11 | **The README does not mention the remote feature at all** | this document (checked after the merge, 2026-08-05) | [§6.2](#62-the-readme-says-nothing-added-here) |

### 6.1 `lockCause` does not handle remote holders (added here)

Verified on a live instance (jenkins-env, on Martin's branch `8fd2193`). What he fixed was the Held By
column and the Queue tab; **the string built for `lockCause` was untouched.**

For a resource held remotely it embeds the build name (null) and the acquisition time (unset) as they
are:

```
# REST API (two resources on the same B)
demo-plc-board          : locked by null at <unknown>                      ← held remotely
s02-shared-1785026807   : locked by demo-local-holder-b#1 at Jul 26, 2026, 8:44 AM   ← held locally

# The console of a locally waiting job
The resource [demo-plc-board] is locked by remote lockId e8ec986d-... since <unknown>.
```

- **`locked by null`** — `getBuild()` is null (a remote hold has no Run)
- **`at <unknown>` / `since <unknown>`** — the acquisition time is unset, although `RemoteLockRecord`
  holds `acquiredAt` and **the value could be printed**

**What to do:** branch the `lockCause` construction on `remoteLockedBy != null` and use the clientId
and `RemoteLockRecord#getAcquiredAt()` - the same source the Held By column (his implementation)
already reads.

> Note how widely this is exposed: the string appears both in **the REST API's `lockCause`** and in
> **the console of a locally waiting job**. The second is where someone asking "why am I waiting?"
> looks first, and `by null` does not tell them.

### 6.2 The README says nothing (added here)

Checked on `master` after the merge: **the plugin's own `README.md` contains not one character about
the remote feature** (`grep -c -i remote README.md` → **0**). The documentation #1055 added is
`src/doc/examples/remote-api-curl.md` and `remote-lock-pipeline-pattern.md`, plus two lines in
`src/doc/examples/readme.md` (an index).

With no signpost in the README a user reads first, the feature is **effectively undiscoverable.**
Three of the gaps are also inconsistencies with what the README already says.

| Place | Today | What to add |
|---|---|---|
| **The Permissions table** (`### Permissions`) | Six rows: View / Configure / Unlock / Reserve / Steal / Queue | **The `RemoteUse` row (Implied by: Jenkins.ADMINISTER) is missing.** A permission added in M1B is absent from the table, which makes the table itself wrong |
| **Usage / Acquire lock** | No `serverId` among the `lock()` parameters | `lock(..., serverId: 'X')` for peer mode and `forcedServerId` for delegated mode |
| **Configuration as Code** | No remote keys in the example | `remoteApiEnabled` / `exposeLabel` / `clientId` / `forcedServerId` / `remotes[]`. The tests already have `configuration-as-code-remote.yml` to excerpt from |

**Approach:** ride along with this PR, because (1) the missing Permissions row is an inconsistency in
existing documentation and the sooner it is fixed the better, and (2) this PR is what puts the remote
view on the LR page, so what the README has to describe is settled here. If the volume grows, it can
be **split into a documentation-only PR** (Q7 in [§10](#10-open-items-to-settle-before-implementing)).

---

## 7. What to do about specification/implementation divergence

Places where the (authoritative) #1025 issue body and the implementation deliberately differ. Each
needs a decision: **update the issue body, or move the implementation.** All were settled during M1
and are not reopened.

### 7.1 `exposeLabel` was extended to several labels

The specification says "a single label name". The implementation, since M1E, takes **an OR of
whitespace-separated labels** (`getExposeLabels()`). A single value is backwards compatible.

→ **Keep the implementation and update the issue body** (this is an addition, not a regression).

### 7.2 `heartbeatIntervalSeconds` is ignored

The specification says: default to the server's 10s when omitted, 400 when out of range. The
implementation **accepts and validates it but ignores the value**, using a fixed
`STALE_THRESHOLD_MS = max(default 10s × 6, 60s) = 60s` (there is a comment in `RemoteApiV1Action`).

→ **Leave it for Phase 1.** The wire format is already in place, so making it configurable later
needs no API version bump. The original plan was to show the effective value through the `GET /lease`
of [§3.2](#32-get-leaselockid-is-not-added-decided-2026-08-05), but that endpoint is out of Phase 1,
so **Phase 1 gives an operator no way to read the effective value back from the API.** Compensate by
saying in the help and the docs that the requested value is unused in Phase 1.

> **A precision point about the validation.** The implementation's 400 `INVALID_HEARTBEAT_INTERVAL`
> covers exactly two conditions - **not readable as an integer, and ≤ 0**. It does not do the range
> check ("outside the server's accepted range") the specification describes. Since the value is not
> used, validating an upper bound would mean nothing, so **this stays as it is** and the issue body
> changes to "a positive integer (the value is unused in Phase 1)".

### 7.3 The `X_SERVER_ID` / `X_LOCK_ID` asymmetry

M1D §3-2 established that env vars are identical between local and remote (a shared function), but
his follow-up added two variables to the remote body only. The shared function `buildLockEnvVars`
itself is unchanged; they are added at the injection point.

→ **Keep it.** Those two values carry **nothing but bridge-derived information** (which server, which
lockId), so they do not conflict with M1F's principle of not adding remote-specific decisions **that
are not about the bridge**. Written into this document as "bridge-specific metadata is outside
transparent equivalence", and not reopened.

### 7.4 The `EXPIRED` state

The specification's `GET /acquire` lists `EXPIRED`, but the server never returns it. An allocate
timeout is `FAILED` + `errorCode=LOCK_WAIT_TIMEOUT` (the wording settled in M1I).

→ **`EXPIRED` is a future slot** (the specification itself says "future: when maxWaitSeconds is
set"). Remove the mistake from the doc and note in the issue body that it is reserved for later.

The client-side `RemoteAcquireState` also has an **`UNKNOWN`** that the specification does not list,
as a sentinel so an unrecognised string does not become an exception. Note it against the state list
in the issue body.

### 7.5 `requestId` / `leaseId` were unified into `lockId`

The specification uses `requestId` on the acquire side and `leaseId` on the lease side; the
implementation **uses the `lockId` returned by `POST /acquire` for the lease operations as well.**
Two ids serve no purpose and force the client to keep a mapping.

→ **Keep the implementation and unify the endpoint table, client loop and JSON examples in the issue
body on `lockId`.**

### 7.6 The acquire request body has a different shape from the specification

The specification's JSON example is three flat fields (`resource` / `skipIfLocked` /
`heartbeatIntervalSeconds`). Transparent equivalence (M1C–M1G) took the implementation here:

```jsonc
{
  "clientId": "jenkins-a",              // optional; the server shows "Remote API" without it
  "heartbeatIntervalSeconds": 10,       // optional, currently ignored (§7.2)
  "lockRequest": {                      // ← a wrapper appeared
    "resource": "plc-01",
    "label": "plc",
    "quantity": 0,                      // 0/absent = all matching the label (as local lock() does)
    "variable": "RESOURCE",
    "inversePrecedence": false,
    "resourceSelectStrategy": "SEQUENTIAL",
    "skipIfLocked": false,
    "priority": 0,
    "timeoutForAllocateResource": 0,
    "timeoutUnit": "MINUTES",
    "reason": "…",
    "extra": [ { "resource": "…", "label": "…", "quantity": 0 } ]
  }
}
```

→ **Keep the implementation and replace the JSON example in the issue body.** As it stands, anyone
writing a curl client from the body will miss the `lockRequest` wrapper and hit
`MISSING_LOCK_REQUEST` (400). `src/doc/examples/remote-api-curl.md` has the correct shape, so
pointing at it from the body is the practical move.

### 7.7 `remoteApiEnabled=false` answers with 403

The specification is written to mean "every endpoint responds **as if the API did not exist**" (=
404). The implementation answers **403 `REMOTE_API_DISABLED`** in all four (at the top of each method
in `RemoteApiV1Action`).

→ **Keep the implementation and change the issue body to "returns 403 `REMOTE_API_DISABLED`".**
Because (1) the authorization check (`checkPermission(REMOTE)`) runs first, so existence is not
revealed to anyone without the permission anyway, (2) for an operator who does have it, being able to
tell "disabled" from "wrong path" is easier to diagnose, and (3) making the new endpoint a 404 to
match the specification would **split the behaviour inside one API**.

### 7.8 The client side gained a `clientId` setting

The specification's Client-side settings table has only `remotes[]` and `forcedServerId`. The
implementation adds **`clientId`** - a self-declared name so the server-side LR page can show which
controller is holding something (falling back to something like the root URL when unset). It is
settable through JCasC (`configuration-as-code-remote.yml`).

→ **Keep the implementation and add a row to the Client-side settings table in the issue body.**

### 7.9 The `RemoteUse` permission was implemented early, in Phase 1

The specification's Non-goals say plainly that Phase 1 adds no plugin-specific allow-list and **no
dedicated remote-API permission**, relying on Jenkins' standard authentication and authorization. The
implementation added a dedicated `RemoteUse` permission (implied by ADMINISTER) while addressing the
Security Scan (M1H), and every endpoint requires it.

→ **Keep the implementation and correct the Non-goals and Phase 1 scope in the issue body.** This is
not the same thing as a client allow-list (an enumeration of which clients are permitted); it
**only makes the permission narrowable**. The allow-list itself remains Phase 2
([§8](#8-not-included)). Left in Non-goals, it reads to a reviewer as an implementation that
contradicts its specification.

### 7.10 Open questions that are now settled

The Open questions at the end of the issue body were largely decided in #1055. **Update the body and
shrink the list.**

| Open question | Settled value | Basis |
|---|---|---|
| Default polling interval | **3s** | `RemoteClientDefaults.DEFAULT_POLL_INTERVAL_SECONDS` |
| Default heartbeat / stale threshold | **10s** / `max(hb × 6, 60) = 60s` | `RemoteClientDefaults` / `RemoteLockManager.STALE_THRESHOLD_MS` (the formula matches the specification) |
| HTTP code for `UNKNOWN_RESOURCE` / `UNKNOWN_LABEL` | **404 for both** (the body only says "4xx") | `RemoteApiV1Action`. The same code for both so existence is not revealed |
| How the server shows a remote owner | **`clientId`** ("Remote API" when unset) in Held By / Queue | M1B plus his follow-up |
| UI integration detail (merged vs separate tab, badge) | Settled in [§4.3](#43-the-display) / [§5](#5-design-c-the-delegated-mode-display-switch-m2-proper) | Implemented in this PR |

The only one left open is the **client-side request timeout default of 5s**
(`DEFAULT_REQUEST_TIMEOUT_SECONDS`; the body's Open questions do not even list it). Making it
configurable is Phase 2.

---

### 7.12 The client side gained an `enabled` setting

The specification's Client-side settings table has only `remotes[]` (`serverId` / `url` /
`credentialsId`) and `forcedServerId`. The implementation adds **a per-connection `enabled` (default
`true`)** ([§4.0](#40-per-connection-enabledisable-enabled--b5-added-2026-08-10)).

→ **Keep the implementation and explain it in the PR description.** This is not a specification
change needing agreement in advance; it is the same kind of "a setting operations turned out to need"
as `clientId` ([§7.8](#78-the-client-side-gained-a-clientid-setting)).

### 7.11 Divergence goes in the PR description (2026-08-08)

The items in this section (§7.1–§7.10), where the implementation is right and the issue body is
stale, **are not resolved by rewriting the body.** Instead, **write them as a divergence section in
the new PR's description, and leave one short pointer comment on #1025 after the PR is up.**

**Why:** the body of #1025 has been rewritten many times as the design settled, and editing it to
match the implementation now would not restore "which part is current". For a reader, **the PR
description - presented together with the implementation - is the more trustworthy artefact.**

**What goes in the PR description (transcribed from §7):**

| # | Divergence | Reason |
|---|---|---|
| 1 | `requestId` / `leaseId` unified into `lockId` | Two ids serve no purpose and only force the client to keep a mapping (§7.5) |
| 2 | The `POST /acquire` body is a `lockRequest` wrapper plus `clientId` plus every `lock()` parameter | The result of transparent equivalence (M1C–M1G) (§7.6) |
| 3 | `remoteApiEnabled=false` is 403 `REMOTE_API_DISABLED` | Authorization runs first, so existence is already hidden; an operator is better served by telling "disabled" from "wrong path" (§7.7) |
| 4 | The client-side `clientId` setting | So the server-side LR page can name the holder (§7.8) |
| 5 | A dedicated `RemoteUse` permission implemented in Phase 1 | Security Scan work (M1H). Not the same as an allow-list (§7.9) |
| 6 | `exposeLabel` is an OR of several labels | An M1E extension; a single value is backwards compatible (§7.1) |
| 7 | Allocate timeout is `FAILED` + `LOCK_WAIT_TIMEOUT`; `EXPIRED` is a future slot | Settled in M1I (§7.4) |
| 8 | `heartbeatIntervalSeconds` is accepted but unused in Phase 1 | Configurability comes later; the wire format is ready (§7.2) |
| 9 | `cancel` folded into `release`; `GET /lease` deferred | Decided in M1 (§3.2 / §3.3) |
| 10 | `GET /resources` returns state and `acceptNewAcquires` | So local and remote carry comparable information on the page (§3.1) |
| 11 | Defaults settled (poll 3s / heartbeat 10s / stale 60s / `UNKNOWN_*` = 404) | Settled by the implementation (§7.10) |
| 12 | A per-connection `enabled` setting | There was no way to stop using a peer without deleting its configuration (§7.12 / §4.0) |

**A side effect accepted deliberately:** the body stays stale, so **a new reader reads it as the
specification.** A comment posted after submission scrolls away with time. The minimal mitigation -
one warning line at the top of the body - is **not taken** as of 2026-08-08 (user's decision).

---

## 8. Not included

Carried over from M1's design decisions and **left deliberately**. Not reopened.

| Item | Source | Reason |
|---|---|---|
| **M1E-1** ephemeral regeneration through `fromNames(create=true)` on the promotion path | DESIGN_P1_M1F §4 | **Re-examined 2026-08-08 and confirmed as left standing.** The root cause is that canonical has no mechanism for cleaning the queue, and the bridge layer can only suppress the symptom. Detail and the conditions for revisiting: [§8.1](#81-record-of-the-m1e-1-orphan-ephemeral-re-examination-2026-08-08) |
| **M1E-2** behaviour when resource and label are given together | same | Comes from local `lock()`. Not fail-open |
| **M1E-3** lease operations do not verify ownership of the lockId | same | Keeps the existing model where the trust boundary is the REMOTE permission. Phase 3, if multi-tenancy arrives |
| **L-e** `getExposeLabels` splitting on every call | same | Performance only, harmless |
| Adding `.gitattributes` | REVIEW_UPSTREAM §13.3 | A repository-wide convention change. The maintainer's call |
| Unifying the help URL form (`/descriptor/` vs `/descriptorByName/`) | same | Same. No behavioural difference |
| Server-side maintenance switch (accept new acquires ON/OFF) | issue #1025 | **Phase 2** |
| Making polling / heartbeat / timeout configurable | same | **Phase 2** |
| Client allow-list | same | **Phase 2** (the `RemoteUse` permission was implemented early, in M1B) |
| Multi-server routing / failover, `serverId:'any'` | same | **Phase 3** |
| cancel / release actions from the client LR page | [§4.3](#43-the-display) | Phase 1 stops at visibility |

### 8.1 Record of the M1E-1 (orphan ephemeral) re-examination (2026-08-08)

**This point resurfaces repeatedly**, so the mechanism and the reasoning are written down to save
tracing it from scratch each time.

**The mechanism (a time gap; Admission is a point-in-time check and does not protect an entry's
lifetime):**

```
t0  a remote lock(resource:'plc-01') passes Admission (it exists and is exposed)
    → QUEUED because somebody else holds it (the entry carries canonical structs = the name "plc-01")
t1  an administrator deletes plc-01 (removeResources takes syncResources, so it does not race the
    scan itself - but it happens quite normally *between* two scans)
t2  the promotion scan → Admission is not re-run
    → canonical's name branch calls fromNames("plc-01", create=true) (LRM:1586)
    → plc-01 comes back as an ephemeral (no labels, persisted with doSave=true)
```

**The same code path reproduces locally** (`fromNames(candidates, true)` in `proceedLocalEntry`,
LRM:1027). What differs is **the ending**, and that is where the remote-specific harm is:

| | local | remote |
|---|---|---|
| The resurrected resource at t2 | no exposure filter, so **it is simply locked** | it has no labels, so **the exposeLabel filter rejects it and it can never be locked** |
| On release | `freeResources` sees `isEphemeral()` and deletes it via `removeResources` | it is never locked, so it is never released, and **never enters the reclamation path** |
| Final state | **back to normal** (the lifecycle closes; self-healing) | **the orphan persists** (it survives a restart) |

→ canonical's `create=true` is **correct behaviour for local** (the design intent of an ephemeral:
if a name is requested, treat it as existing). What is broken is the remote combination, where
inserting a visibility filter stops the reclamation loop from closing.

**Ways of closing it that were considered, and why none is taken now:**

| Option | What it is | Verdict |
|---|---|---|
| (a) Pass `create=false` into canonical | A remote-only flag on the resolution seam | **No.** Against M1F's principle of not adding remote-specific decisions to canonical that are not about the bridge |
| (b) Re-run Admission on the promotion scan | Contained in the bridge layer; canonical unchanged | **Technically possible** (a few lines). But it only removes the remote symptom, not the cause |
| (c) Clean the queue when a resource is deleted | Add a mechanism in LR proper to drop QUEUED entries (local and remote) that reference a deleted resource | **The real fix. But a design change across upstream**, beyond what a drive-by contributor should bring |

**Why it is left standing (2026-08-08, user's decision):** triggering it requires a job to be waiting
to lock a resource *at the moment it is deleted*. **By the time you delete a resource it should
already be settled that nobody will ask for it**; if that is not so, the bug is in operations. It is
not a route real operation takes, so it is not worth the cost of (b).

**Conditions that should reopen it (material for the next time it comes up):**

- **An orphan is actually observed** in real operation or load testing (the assumption about
  frequency has then failed)
- (c) is implemented upstream (at which point (b) on the remote side is unnecessary)
- An operating model where **deleting resources is routine** - multi-tenancy, say (which should
  coincide with M1E-3's reopening conditions)
- A change that stops an orphan being "unlocked and harmless" (relaxing the exposure test, or
  auto-publishing ephemerals)

---

## 9. Test plan

The cycle's definition of done is unchanged (`run-mvn-verify.sh` plus a full `run-e2e.sh`).

### 9.1 Unit

| Subject | Contents |
|---|---|
| `GET /resources` | The exposeLabel filter applies / unpublished resources do not appear / **403 `REMOTE_API_DISABLED`** when `remoteApiEnabled=false` (the same shape as the existing three) / no state fields |
| The QUEUED path of `release` | Held for the terminal TTL, so **the next `GET /acquire/{lockId}` returns 200 `FAILED`/`RELEASED`** rather than 404. Back to 404 once the TTL passes |
| Maintenance switch | With it OFF, `POST /acquire` is 503 `ACQUIRES_PAUSED` / **heartbeat, release and `GET /acquire` still succeed in the same state** / turning it back ON accepts again / promotion of the existing queue does not stop |
| `inversePrecedence` (transparent equivalence) | A remote request with `inversePrecedence=true` goes to the head of the queue (the same insertion position as local) / giving it together with `priority != 0` is 400 |
| `RemoteClientRegistry` | Registration and removal on acquire/release / rebuilt after `onResume` / does not fall over when a build is deleted |
| Queue merge order | Local and remote sorted by descending priority, with the index matching promotion order |

### 9.2 E2E (new scenarios)

| ID | Name | What it verifies |
|---|---|---|
| S19 | `remote-resources-endpoint` | A fetches B's `GET /resources` and **only resources carrying the exposeLabel** come back. Unpublished ones do not leak |
| S20 | `client-side-remote-view` | While A holds a resource of B's, **A's LR page shows the held remote lock**. It disappears after release |
| S21 | `delegated-mode-page` | Set `forcedServerId=b` on A → A's LR page shows the **delegated badge** and **B's published resources**. Unsetting it restores the previous state |
| S22 | `remote-maintenance-switch` | Turning B OFF makes A's new `lock()` wait (the job does not fail) / **a lease already held survives, heartbeat and release both fine** / turning it back ON lets the waiting `lock()` proceed |

> S22 doubles as the regression guard for [§6-1](#6-picking-up-the-m1-leftovers) (the 404 label
> problem). The "server restart while QUEUED" scenario deferred in M1 **becomes writable here**, once
> the label direction is settled (after Q1 in
> [§10](#10-open-items-to-settle-before-implementing)).

### 9.3 Load

Measured with `run-load.sh` (G01 grid-storm). Because `GET /resources` **behaves differently with and
without the cache**, the load of "every controller pulls every other's `/resources` **every 10s**" is
**added to the measurement** (settled as Q5 in
[§10](#10-open-items-to-settle-before-implementing); returning state made the frequency six times
higher).

> **A condition settled 2026-08-05:** the load test must run **with the LR page updating in its
> production behaviour**. Do not disable the client-side remote view or bypass the cache to measure.
> Take the numbers with the cache working exactly as it does in production.

### 9.4 Running old and new side by side (for the PR screenshots)

**How to proceed (settled 2026-08-05):** do **not** ask Martin about the UI in advance. Build it,
settle the design, and **present before/after screenshots in the PR as "here is what it looks like -
thoughts?"**. #1035 changed the look substantially and a real artefact is easier to discuss than
prose.

**Method:** of the four `jenkins-env` controllers, put **the new build (as submitted) on a and the
old build (current master) on b**, then open both LR pages with the same resources and the same locks
held.

- `start.sh` distributes the same hpi to every controller, so **b has to be swapped by hand**:
  `docker compose stop` → replace the hpi in `jhb/plugins/` with a master build and delete the
  exploded directory → `docker compose start` (the same deployment trap as [[rlr-build-environment]])
- **Leave c and d on the new build**, so a↔c/d also exercises new-to-new locking at the same time
- A lock from a (new client) to b (old server) succeeding is also **a wire-compatibility check**
  (only `GET /resources` and the 503 were added; the contract of the existing four is unchanged)
- Do not run E2E or load in this state (both suites assume the same build everywhere). **A temporary
  arrangement purely for visual comparison**

**What this comparison decides:** Q6 in [§10](#10-open-items-to-settle-before-implementing) (a new
tab for the remote view, or a column in Resources). Provisionally build (a), a new tab, and rebuild
if it looks wrong side by side.

---

## 10. Open items to settle before implementing

**All settled by the user on 2026-08-05** (Q5 re-judged after implementation). These are decisions
and are not reopened.

| # | Question | Decision |
|---|---|---|
| Q1 | Wording of the 404/410 labels | **(a) unify.** On checking the facts, that branch (the 404/410 handling in `RemoteLockSession`, currently lines 249-290) is **entirely our own code**, from `73a2d3b` (first version) plus `7fd218b` (M1I). His `9ffade8` in the same file only added `serverUrl` to an acquire log and error output to the build log, and does not touch the poll branch. **Not editing somebody else's code**, so unification is adopted |
| Q2 | Actions from the client LR page | **(a) visibility only.** A search of every comment on #1025 / #1055 shows the cancel button was proposed **only in our own notes** (Martin never mentioned it). Nothing was promised externally, so it is out for Phase 1 |
| Q3 | ~~Whether `GET /lease` should echo the requested value~~ | **Moot.** `GET /lease/{lockId}` itself is out of Phase 1 scope ([§3.2](#32-get-leaselockid-is-not-added-decided-2026-08-05)). Revisit when it arrives alongside configurable heartbeat values |
| Q4 | Whether to apply `inversePrecedence` to the remote queue | **(c) the alternative: reflect local's rule on the remote path as transparent equivalence.** [§10.1](#101-the-alternative-answer-to-q4-inverseprecedence-as-transparent-equivalence) |
| Q5 | Whether `/resources` belongs in the load test | **Yes (settled 2026-08-08).** §3.1 made it return state and dropped the TTL from 60s to 10s, so the call frequency is six times higher. Add "every controller pulls every other's `/resources` every 10s" to grid-storm and measure. The condition is unchanged: run **with the LR page in its production behaviour** |
| Q6 | A new tab for Remote locks, or a section in an existing tab | **Provisionally (a) a new tab** (riding #1035's tab layout), **with the final decision made by comparing old and new side by side after implementation** ([§9.4](#94-running-old-and-new-side-by-side-for-the-pr-screenshots)). #1035 changed the look enough that this cannot be settled on paper. Do not ask Martin in advance; present something finished in the PR |
| Q7 | Whether the README additions ([§6.2](#62-the-readme-says-nothing-added-here)) belong in this PR | **(a) ride along. The missing Permissions row is included too**, not split out |
| Q8 | When to publish the issue-body updates | **Changed 2026-08-08: do not update the body.** #1025 has about a year of accumulated discussion and is hard to read for "which part is current"; fixing the body alone would not restore that. Instead **write "divergence from the #1025 specification, and why" into the new PR's description**, and add a short pointer comment on #1025 after submission. → [§7.11](#711-divergence-goes-in-the-pr-description-2026-08-08) |

### 10.1 The alternative answer to Q4 (`inversePrecedence` as transparent equivalence)

The question was never "should we add a remote-specific ordering rule". In fact **local's insertion
rule is simply not reflected on the remote path**, and reflecting it makes the rules *fewer*.

| Path | Today |
|---|---|
| local `queueContext` | With `inversePrecedence && priority == 0`, **insert at index 0** (jump the queue). Otherwise an ordered insert by `compare` |
| remote `queueRemote` | **Decides position from priority alone; never looks at `inversePrecedence`** (which is carried on the wire and held on `RemoteLockRequest`) |

**Change 1:** put local's branch into `queueRemote`. The value is available as
`entry.getLockRequest().isInversePrecedence()`.

**Change 2 (a related hole):** local rejects `priority != 0 && inversePrecedence` with an
`IllegalArgumentException` from `LockStepResource.validate()`, while **the remote POST accepts both
silently.** This is not a standalone hole; it is solved as part of handing validation to canonical.
Order of judgement, HTTP codes and where it lives are collected in
[§3.5](#35-server-side-order-of-judgement-wire--admission--canonical).

With this, item 8 of [§6](#6-picking-up-the-m1-leftovers) ("do not apply") is **reversed**. The text
in his `remote-api-curl.md`, which accurately describes today's behaviour, needs updating after the
change.

---

## 11. Change log

| Date | Contents |
|---|---|
| 2026-07-26 | First version. Combines Phase 1 M2/M3 of issue #1025 and becomes the destination for nine M1 leftovers |
| 2026-08-10 | **Added B5 (per-connection `enabled`).** Widened §4 to "the client side (connection settings and the LR page)" and added §4.0 (four semantic points, why `@DataBoundSetter`, why before C3). Added it to §7.12 and to the transcription table in §7.11. Externally: no prior agreement sought; explained in the PR description |
| 2026-08-08 (3) | **Dropped the plan to update the #1025 issue body** (Q8 reversed). Divergence is **written into the new PR's description as "divergence and why"**, with a pointer comment on #1025 after submission. Added §7.11 listing the eleven items to transcribe. Recorded the side effect of leaving the body stale, and the mitigation not taken (one warning line at the top) |
| 2026-08-08 (2) | Settled the `GET /resources` specification (§3.1 rewritten). **Withdrew the decision not to return state**: to give local and remote comparable information it returns `state` (FREE/LOCKED/RESERVED/QUEUED) + `heldByKind` + `heldByClientId` + `since` + `queuedCount`. **Disclosure takes the middle option** (no build name, reason or note = B's job names are not shown to A's viewers). **`acceptNewAcquires` rides in the same response** (two endpoints would allow a screen showing FREE while acquires are paused). Resource state stays truthful during maintenance; the page does the expressing. §5.2's cache TTL 60s → **10s**; §10 Q5 settled as **yes** |
| 2026-08-08 | Redesigned the validation logic. **Added §3.5 "Server-side order of judgement (Wire → Admission → Canonical)"**, confining remote-specific judgement to Wire and Admission and handing the rest to `LockStepResource.validate()` (the boundary's `MISSING_TARGET` / `INVALID_SELECT_STRATEGY` are deleted; the former was also an existing break in transparent equivalence, ignoring `allowEmptyOrNullValues`). **M1E-2 (resource+label together) is no longer left standing**, because removing remote-specific code closes it automatically. Secrecy (a uniform 404) is preserved for free by putting Admission first. **M1E-1 (orphan ephemeral) re-examined and left standing**, with the mechanism, the difference from local, three ways of closing it and the reopening conditions recorded in §8.1 |
| 2026-08-05 (3) | Changed the approach: **do not ask him about UI questions in advance; build it and present screenshots in the PR**, reflected in §3.4 / §10 Q6, and **added §9.4 "running old and new side by side"** (a=new, b=old; no E2E/load; doubles as a wire-compatibility check). Q6 becomes "provisionally (a) a new tab, decided for real by comparison". **Added §5.0, changing delegated display from "replacement" to "coexistence"** (roles belong to relationships; #1035's tabs make both possible; resolution rules unchanged). Settled where change 2 of §10.1 lives (400 at the remote API boundary, with the reason for not calling canonical validation wholesale) |
| 2026-08-05 (2) | The eight open items of §10 settled by the user (Q5 re-judged after implementation). **Narrowed the server-side API from three endpoints to `GET /resources` alone** (`GET /lease` and `cancel` had already been decided in M1; the first draft misclassified them as unimplemented - §3.2 / §3.3 replaced). **Pulled the maintenance switch into Phase 1** (§3.4 added; two questions for him pending). Q4 becomes **(c) the alternative** = `inversePrecedence` as transparent equivalence, with §10.1 added and §6-8's direction reversed. Replaced the test plan in §9 (three unit rows, S22) and added the "measure with the LR page in production behaviour" condition to §9.3 |
| 2026-08-05 | Compared against `master` after #1055 merged (`018e913`, 2026-08-04). Added §1.3 "can the Phase 1 checkbox be ticked" and the naming clarification. **Corrected §3.1's `remoteApiEnabled=false` response to 403** (it contradicted the implementation; the matching test row in §9.1 fixed at the same time). Added **11: the README says nothing** (§6.2) to §6. Added **7.5 lockId unification / 7.6 acquire body shape / 7.7 403 / 7.8 the `clientId` setting / 7.9 the early `RemoteUse` permission / 7.10 settled Open questions** to §7. Added Q7 and Q8 to §10 |
