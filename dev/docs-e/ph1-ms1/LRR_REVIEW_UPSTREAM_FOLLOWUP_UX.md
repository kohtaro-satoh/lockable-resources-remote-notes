# Remote LR review — mPokornyETM's follow-up branch `feature/1025-remote-lr-followup-ux`

> **Context:** while PR [#1055](https://github.com/jenkinsci/lockable-resources-plugin/pull/1055) was under
> review, the maintainer Martin Pokorny (`mPokornyETM`) pushed the promised "UX/docs improvements based on
> this branch" as a branch in `jenkinsci` (an additional proposal on top of our PR).
> This document is the **detailed analysis of its content and the record of the behavioural differences
> measured against our previous head `e83534b`**.
> **Review date:** 2026-07-25 – 2026-07-26
> **Subject:** `jenkinsci/lockable-resources-plugin` branch `feature/1025-remote-lr-followup-ux` (HEAD `8fd2193`)
>   = [kohtaro-satoh/lockable-resources-plugin#1](https://github.com/kohtaro-satoh/lockable-resources-plugin/pull/1)
> **Baseline:** `e83534bff02bf096097e01e8c04795e13dd70bfe` (our last commit; PR #1055's current head is
>   `3a555fe`, which the maintainer pushed — see [§2.2](#22-how-the-prs-relate-and-why-the-crlf-is-already-in-pr-1055))
> **Method:** (a) full static reading of the diff, (b) `run-mvn-verify.sh` (equivalent to the CI gates),
>   (c) `run-e2e.sh --clean-start`, all 21 scenarios, (d) `run-load.sh --preset stress`,
>   (e) before/after measurements on the real 4-container `dev/jenkins-env`, and
>   (f) porting his new test onto an `e83534b` worktree to check **whether it fails on the old code**.

---

## Table of contents

1. [Overall assessment](#1-overall-assessment)
2. [Branch layout and commits](#2-branch-layout-and-commits)
3. [The change at a glance](#3-the-change-at-a-glance)
4. [Analysis 1: a real bug fix — the swallowed HTTP status](#4-analysis-1-a-real-bug-fix--the-swallowed-http-status)
5. [Analysis 2: UI — the Held By column and the Queue tab](#5-analysis-2-ui--the-held-by-column-and-the-queue-tab)
6. [Analysis 3: configuration UI — credentials selector and help links](#6-analysis-3-configuration-ui--credentials-selector-and-help-links)
7. [Analysis 4: the `X_SERVER_ID` / `X_LOCK_ID` env vars](#7-analysis-4-the-x_server_id--x_lock_id-env-vars)
8. [Analysis 5: JCasC `@Symbol` and the `flushPendingSave` guard](#8-analysis-5-jcasc-symbol-and-the-flushpendingsave-guard)
9. [Analysis 6: the two new documents](#9-analysis-6-the-two-new-documents)
10. [Analysis 7: the new tests](#10-analysis-7-the-new-tests)
11. [Measurement log (before / after)](#11-measurement-log-before--after)
12. [Findings](#12-findings)
13. [Integration plan and current state](#13-integration-plan-and-current-state)
14. [Appendix: reproduction commands](#14-appendix-reproduction-commands)

---

## 1. Overall assessment

**The content is good overall and should be taken.** In particular the `RemoteApiClient` change is not a
cosmetic improvement but **a fix for a real bug we had introduced**; it would be worth taking on its own.
The two UI additions (Held By column, Queue tab) precisely fill the "remote locks are invisible on the
dashboard" gap that Phase 1 deliberately deferred.

**There are no behavioural regressions.** Running our full verification suite against his branch `8fd2193`:

| Verification | Result |
|---|---|
| `run-mvn-verify.sh` (equivalent to the CI gates) | tests **394/0/1skip**, spotbugs/checkstyle/pmd **ok**, **only spotless FAILs** |
| `run-e2e.sh --clean-start` | **21/21 PASS, 0 fail** |
| `run-load.sh --preset stress` (200 concurrent, 2 runs) | **0 mutual-exclusion overlaps / 0 HUNG**; every failure is a clean `LOCK_WAIT_TIMEOUT` |

That said, **it cannot be merged as is**. His `22c7b2b "spotles"`, which is part of the branch's base,
converted `LockableResource.java` wholesale to CRLF, so `spotless:check` alone fails the build
(i.e. ci.jenkins.io's `buildPlugin` goes red). The same cause inflates a 13-line change into a 1739-line
diff. **Worse, that CRLF already reached PR #1055 through the merge `3a555fe` that he pushed, so #1055's
CI is currently red** ([§2.2](#22-how-the-prs-relate-and-why-the-crlf-is-already-in-pr-1055)).
Restoring the line endings to LF resolves it — a small problem, but **it must be cleared before the branch
lands on master**.

| Verdict | Count | Detail |
|---|---|---|
| ✅ Real bug fix (must take) | 1 | Swallowed HTTP status (`RemoteApiClient.send`) |
| ✅ Feature / improvement (recommended) | 6 | Held By column / Queue tab / credentials selector / 2 env vars / diagnostics / JCasC `@Symbol` |
| ✅ Documentation (recommended) | 2 | `remote-api-curl.md` / `remote-lock-pipeline-pattern.md` |
| ✅ Tests (recommended) | 4 groups | CasC 3 / EnvVars 3 / LockStepRemote 1 / RemoteApiClient 1 |
| ⛔ Blocker | 1 | CRLF -> `spotless:check` fails |
| ⚠️ To discuss / to fix | 7 | Split help-URL spelling, Change Position button on queue rows, etc. ([§12](#12-findings) #2-#8) |
| ℹ️ Informational / future | 4 | Credentials domain consistency, tests relying on reflection, etc. ([§12](#12-findings) #9-#12) |

---

## 2. Branch layout and commits

```
*   8fd2193 Merge branch 'feature/1025-remote-lr-p1-m1' into feature/1025-remote-lr-followup-ux
|\                                                                  <- his PR #1 head
| *   3a555fe Merge branch 'feature/1025-remote-lr-p1-m1' of kohtaro-satoh/...
| |\                                                                <- * current PR #1055 head (he pushed it)
| | * e83534b Fix remote config help links returning 404 (Not Found)   <- former PR #1055 head
* | c8162cf other findings
* | bd48b1e more things
* | 77d36a8 more docs
* | 64b0e14 docs: add Remote Lock REST API curl examples
* | 9ffade8 Remote LR UX follow-up: credentials selector, better diagnostics, heldBy column
|/
* 22c7b2b spotles                                                      <- * where the CRLF came from
* 7fd218b Report a remote acquire timeout as LOCK_WAIT_TIMEOUT ...      <- our M1I
```

| commit | Date | Subject | Change |
|---|---|---|---|
| `22c7b2b` | 07-16 | `spotles` | Converts `LockableResource.java` to CRLF only (`-w` diff is **empty**, 863+/863-) |
| `9ffade8` | 07-19 | UX follow-up | Credentials selector / better diagnostics / heldBy column (9 files) |
| `64b0e14` | 07-19 | docs | New `remote-api-curl.md` (+248) |
| `77d36a8` | 07-21 | more docs | Adds a priority/inversePrecedence section to the curl doc (+47/-1) |
| `bd48b1e` | 07-22 | more things | Queue tab remote rows / env vars / pipeline pattern doc (8 files, +388/-13) |
| `c8162cf` | 07-22 | other findings | JCasC `@Symbol` + tests / `flushPendingSave` guard (5 files, +78/-13) |

> The commit messages `more things` / `other findings` are coarse. **It would be worth asking for a squash
> or a message cleanup before this goes upstream** ([§13](#13-integration-plan-and-current-state)).

### 2.1 Who introduced the CRLF — settled from history

To rule out the suspicion "maybe it was CRLF originally, our PR converted it to LF, and he restored it",
the line endings of `LockableResource.java` were counted across every revision.
**The answer is no. We never touched the line endings.**

| Revision | CR count | Content |
|---|---|---|
| `origin/master` (`4dbbfc1`) | **0** | Upstream master |
| All 40 commits in master's history that touched this file | **all 0** | Upstream has always been LF |
| `73a2d3b` | **0** | Our first commit (Remote Lockable Resources phase 1) |
| `a267ad5` / `3fdef28` / `6ea49f6` / `7fd218b` | **0** | All of our subsequent commits |
| `e83534b` | **0** | Our last commit (former PR #1055 head) |
| **`22c7b2b`** (Martin, 2026-07-16, "spotles") | **863** | * first appearance |
| **`3a555fe`** | **863** | * the merge he pushed onto our branch = **current PR #1055 head** |
| `8fd2193` | 876 | His PR #1 head |

A scan of **every file in upstream master** finds CRLF only in
`src/test/resources/plugins/jobConfigHistory.hpi` (a binary `.hpi`). **LF for text files is an established
convention in this repository**, so the CRLF conversion is not a restoration but the introduction of a
convention violation.

**In addition, `mvn spotless:check` is BUILD SUCCESS on `22c7b2b`'s parent `7fd218b`** (measured).
So there was not a single formatting violation at the moment he tried to format.

**`22c7b2b` changes nothing of substance**, confirmed byte for byte. The only modified file is
`LockableResource.java`, and removing the CRs from it makes it identical to the `7fd218b` version:

```
before (7fd218b)          : 29620 bytes  sha256=8af6723cb487cae6...
after  (22c7b2b, LF-ised) : 29620 bytes  sha256=8af6723cb487cae6...  -> identical
```

Not only `git diff -w` (ignore all whitespace) but also a byte comparison after normalizing line endings
matches, so code, indentation, trailing whitespace, import order and the final newline are all unchanged.
**Restoring LF loses nothing** — useful reassurance when raising this with him.

> **Presumed mechanism (not certain)**: the well-known trap of running `mvn spotless:apply` on Windows.
> Spotless defaults `lineEndings` to `GIT_ATTRIBUTES`, which without a `.gitattributes` in the repository
> delegates to git's `core.autocrlf` / `core.eol`. On Windows with `core.autocrlf=false` (or unset),
> spotless writes CRLF back into the working tree and git commits it verbatim.
> A `.gitattributes` with `*.java text eol=lf` would make this impossible regardless of environment
> ([§12-1](#12-findings)).

### 2.2 How the PRs relate, and why the CRLF is already in PR #1055

His changes were submitted to our fork as
**[kohtaro-satoh/lockable-resources-plugin#1](https://github.com/kohtaro-satoh/lockable-resources-plugin/pull/1)**,
"Enhance Remote LR UX with credentials selector and diagnostics".

| Item | Value |
|---|---|
| base | `feature/1025-remote-lr-p1-m1` (= PR #1055's head branch) |
| head | `feature/1025-remote-lr-followup-ux` (`8fd2193`) |
| mergeable | `MERGEABLE` / `CLEAN` |
| Commits in PR #1 | `9ffade8` `64b0e14` `77d36a8` `bd48b1e` `c8162cf` `8fd2193` — six |

**Important: `22c7b2b` is not part of PR #1's diff.** On 2026-07-22 he pushed the merge `3a555fe`
(= `22c7b2b` + `e83534b`) **directly onto our branch**, so the CRLF is already on the base side
(maintainer edit permission — the same permission he used for the force-push rebase on 2026-07-16).

Consequently:

- **PR #1055's head is `3a555fe`, not `e83534b`**, and **the CRLF is already inside PR #1055**
- **PR #1055's CI is currently red** (ci.jenkins.io PR-1055 #10, `linux-25 / Build` exits 1;
  the `mvn spotless:check` BUILD FAILURE on `3a555fe` was reproduced locally)
- This is why PR #1's Files changed shows `LockableResource.java` as only `13+ 0-`
  (both sides are CRLF, so it does not appear in the diff)

**The integration order is constrained** (verified with real merges):

| Order | Result |
|---|---|
| We fix LF first -> then merge his PR #1 | ❌ `LockableResource.java` **CONFLICTs** (changing line endings makes all 876 lines "modified") |
| Merge his PR #1 -> then fix LF | ✅ No conflict. After LF-ising, `spotless:check` is **BUILD SUCCESS** and `git diff -w 8fd2193` is empty |
| He fixes LF on followup-ux first -> then merge | ✅ No conflict (our branch side is unchanged) |

-> **We cannot fix it first.** It has to be either "after merging PR #1" or "by him, on his branch first".
Since he stated "review it and then we can merge it together and go live", the chosen approach is to
**ask him to restore LF on the `feature/1025-remote-lr-p1-m1` side** (approved 2026-07-26).

---

## 3. The change at a glance

`git diff --stat -w e83534b..8fd2193` (whitespace-only differences excluded) = **20 files / +907, -26**.

| Area | Files | Delta (`-w`) |
|---|---|---|
| **Bug fix** | `remote/RemoteApiClient.java` | +40 / -5 |
| **Diagnostic logging** | `remote/RemoteLockSession.java` | +20 / -2 |
| **UI (resource table)** | `LockableResource.java` / `tableResources/table.jelly` / `table.properties` | +13 / +20 / +1 |
| **UI (queue)** | `actions/LockableResourcesRootAction.java` / `webapp/js/lockable-resources.js` | +100 / -12, +4 |
| **Configuration UI** | `RemoteConnection.java` / `RemoteConnection/config.jelly` / `help-credentialsId.html` | +27, ±4, +5 / -1 |
| **Env vars** | `LockStepExecution.java` | +26 / -1 |
| **JCasC / hardening** | `LockableResourcesManager.java` | +17 / -1 (of which the queue getter is +11) |
| **Documentation** | `src/doc/examples/{readme,remote-api-curl,remote-lock-pipeline-pattern}.md` | +425 |
| **Tests** | 4 test files + a CasC yml | +205 |

`git diff --stat` (including whitespace) reports 1739 lines for `LockableResource.java`, but **the substance
is a 13-line addition**. The remaining 1726 lines come from `22c7b2b`'s CRLF conversion.

---

## 4. Analysis 1: a real bug fix — the swallowed HTTP status

### 4.1 What was broken

`RemoteApiException extends IOException`. But in `e83534b`, `RemoteApiClient.send()` **threw the
`RemoteApiException` for HTTP 4xx/5xx inside a `try` whose own `catch (IOException)` then caught and
re-wrapped it**.

```java
// e83534b (ours) - RemoteApiClient.java:242-265
try {
    HttpResponse<String> response = httpClient.send(request, ...);
    if (status >= 400) {
        throw new RemoteApiException(msg, status, serverId, remoteCode);  // <- thrown inside the try
    }
    return response;
} catch (InterruptedException ex) { ... }
catch (IOException ex) {                       // <- RemoteApiException IS-A IOException
    LOGGER.log(WARNING, "Remote API communication failure (fail-closed): ...");
    throw new RemoteApiException("Remote API communication failure: " + method + " " + path, ex, serverId);
    //                                       ^ this 3-arg constructor sets httpStatus = -1, remoteCode = null
}
```

As a result, **every 400/403/404/410 the remote returned turned into a "communication failure" with
`httpStatus=-1` and `remoteCode=null`**.

### 4.2 Confirmed by measurement

Porting his new test `testHttp404PreservesRemoteDetailsWithoutCommunicationFailureWrap` onto an `e83534b`
worktree and running it:

```
[ERROR] RemoteApiClientTest.testHttp404PreservesRemoteDetailsWithoutCommunicationFailureWrap:156
        expected: <404> but was: <-1>
[ERROR] Tests run: 6, Failures: 1, Errors: 0, Skipped: 0
```

**It reliably fails on the old code — confirming this is a real bug fix.**

### 4.3 Blast radius — M1I's "safety net" was dead

`RemoteLockSession.pollOnce()` branches on `getHttpStatus()` for 404/410:

```java
// RemoteLockSession.java:253
int httpStatus = ((RemoteApiException) ex).getHttpStatus();
if (httpStatus == 404 || httpStatus == 410) {
    // (a) body not started -> normalize to LOCK_WAIT_TIMEOUT (M1I's safety net)
    // (b) body already started -> fail immediately as "lease vanished; server restarted"
}
```

Because `httpStatus` was always `-1`, **this branch never once fired**. In reality the flow fell to the
"transient network failure" side that counts `consecutivePollFailures`, retrying until it reached the
`MAX_CONSECUTIVE_POLL_FAILURES` threshold before failing.

> **Why M1I still passed its E2E** (important): M1I's primary fix was on the server —
> the `terminalAt`-based TTL that retains the terminal record so the client's poll receives
> `state=FAILED, errorCode=LOCK_WAIT_TIMEOUT`. S18 was green because of that, and the client-side 404
> normalization was the secondary defence that `LRR_RESULT_P1_M1I.md` itself describes as a "safety net".
> In other words **M1I's conclusion was correct, but the defence we thought was doubled was running on one
> lung.** His fix restores the second one.

### 4.4 The fix

```java
    return response;
+} catch (RemoteApiException ex) {
+    throw ex;                       // <- let our own exception pass through
 } catch (InterruptedException ex) { ...
```

He also enriched the message considerably (`serverId` / `errorCode` / the remote's `message` / a hint for
404) and added `extractRemoteMessage()` (clamped via `abbreviateForLog`).

### 4.5 Before / after on real controllers

**before (`e83534b`, E2E report `20260719092233-e2e-test/remote-unknown-rejected/console.txt`)**
```
Trying to acquire remote lock on [Resource: s17-unknown-1784421183] (serverId=b)
org.jenkins...RemoteApiException: Remote API request failed: POST /acquire/ returned HTTP 404
Caused: org.jenkins...RemoteApiException: Remote API communication failure: POST /acquire/
```
-> The outer exception (the one programs see) is "communication failure". The 404 survives only as the
cause in the stack trace.

**after (`8fd2193` deployed to the 4 containers)**
```
Trying to acquire remote lock on [Resource: definitely-not-there] (serverId=b, serverUrl=http://jenkins-b:8080/jenkins)
Remote lock request failed (serverId=b, serverUrl=http://jenkins-b:8080/jenkins):
  Remote API request failed: POST /acquire/ returned HTTP 404
  (serverId=b, errorCode=UNKNOWN_RESOURCE, message=No lockable resource matches the request).
  Verify the remote base URL/context path and that the target resource or label exists and is exposed by exposeLabel.
```

**E2E compatibility**: the matchers in `scenarios/fail-closed.sh` are
`auth-error` = `HTTP 401|HTTP 403|returned HTTP 401|returned HTTP 403|Sign in to access` and
`remote-down` = `Remote API communication failure|Connection refused|...`.
The new message matches the former via `returned HTTP 403`, and the latter still produces
"communication failure" for genuine I/O failures, so **the existing E2E assertions should pass unmodified**
(confirmed by the 21/21 run in [§11.5](#115-e2e-regression-run-e2esh---clean-start--8fd2193)).

---

## 5. Analysis 2: UI — the Held By column and the Queue tab

### 5.1 Held By column in the resource table (`9ffade8`)

In `e83534b`, `table.jelly` evaluates the Held By column in the order `reservedBy` -> `locked` -> `queued`.
A remotely locked resource has `remoteLockedBy != null` and `locked == true` but `build == null`, so
`${resource.build.url}` evaluated to empty and produced **`<a href="/jenkins/"></a>` — an empty, broken link**.

Measured (before, `e83534b`):
```html
<td class="jenkins-!-warning-color"><strong>LOCKED</strong> by Remote: doc-verify-label</td>
<td><a href="/jenkins/" class="jenkins-table__link"></a></td>   <- Held By empty + broken link
```

He inserted a `remoteLockedBy != null` branch **before** `locked`, and displays the clientId and the request
details through the new `LockableResource#getRemoteLockRecord()` (which looks up
`RemoteLockManager.get().find(...)`).

Measured (after, `8fd2193`):
```html
<td class="jenkins-!-warning-color"><strong>LOCKED</strong> by Remote: martin-demo-holder</td>
<td><span class="jenkins-table__cell__text"><strong>martin-demo-holder</strong>
    <br><span class="jenkins-!-color-secondary">s01-a-resource-1784417904</span></span></td>
```

When the record cannot be resolved it falls back to
`resource.heldBy.remoteUnknown = (remote, details unavailable)`.
`access-modifier-checker` passes (referencing the `@Restricted(NoExternalUse)` `RemoteLockRecord` from
within the same plugin is fine).

### 5.2 Showing remote waiters on the Queue tab (`bd48b1e`)

In `e83534b`, remote waiters (`RemoteQueueEntry`) **never appear in the dashboard queue at all**.
He added:

- `LockableResourcesManager#getCurrentRemoteQueueEntries()` (read-only snapshot taken under `syncResources`)
- `Queue#add(RemoteQueueEntry)` and a `QueueStruct(RemoteQueueEntry)` constructor
- `remote` / `requestedBy` / `requestedByUrl` / `remoteReason` / `remoteRequest` fields on `QueueStruct`
- `buildRemoteRequestText()` (composes `resource=` / `label=` + `quantity=` / `extra=N`)
- `type: "remote"` in the `getQueuePage` JSON, and a `Remote API` row in the JS `renderRow()`
- Consolidated `requestedBy` retrieval from the direct `item.getBuild().getFullDisplayName()` into
  `item.getRequestedBy()` (handles both local and remote; local values are unchanged)

Measured (before / after, with the same QUEUED remote waiter present, via
`POST /lockable-resources/getQueuePage`):

| | before (`e83534b`) | after (`8fd2193`) |
|---|---|---|
| `total` | `0` | `1` |
| items | `[]` | `type: "remote"`, `id: <lockId>`, `priority: 7`, `requestedBy: "martin-demo-waiter"`, `request: "resource=s01-a-resource-1784417904"`, `reason: "doc verification wait"` |

When no clientId is supplied the implementation falls back to `"Remote API"`.

---

## 6. Analysis 3: configuration UI — credentials selector and help links

### 6.1 Credentials: from a text box to a dropdown (`9ffade8`)

`credentialsId` in `RemoteConnection/config.jelly` changed from `<f:textbox/>` to `<f:select/>`, with a new
`DescriptorImpl#doFillCredentialsIdItems(credentialsId, url)`.

- `@POST` plus a `Jenkins.ADMINISTER` check. Without the permission it returns only
  `includeCurrentValue` (no information disclosure)
- Filters on `StandardUsernamePasswordCredentials`, which **matches** the type that
  `RemoteCredentials.basicAuthHeader()` actually looks up when building the auth header — consistent
- Builds domain requirements with `URIRequirementBuilder.fromUri(Util.fixEmptyAndTrim(url))`.
  `fromUri(null)` is null-safe on the credentials-plugin side (`withUri` ignores null)

The fill endpoint was exercised directly on a real controller (`8fd2193`):
```
POST /jenkins/descriptorByName/....RemoteConnection/fillCredentialsIdItems  -> HTTP 200
{"_class":"...StandardListBoxModel","values":[{"name":"- none -","value":""},
 {"name":"admin/****** (E2E generated ...)","value":"s01-a-for-b"}, ... {"value":"load-d-token"}]}
GET (no crumb) -> HTTP 404 (the @POST is correctly enforced)
```
The global configuration page rendering was also checked:
`<select fillUrl=".../fillCredentialsIdItems" fillDependsOn="credentialsId url" name="_.credentialsId">`.

**The help-text improvement is equally on point**, documenting the trap he actually hit:
> Using username + account password may fail with HTTP 403 due to CSRF/crumb handling on the remote server.

This was **reproduced on a real controller** ([§11.1](#111-authentication-api-token-vs-password)).
Our help text said nothing about it.

### 6.2 Help links `/descriptor/` -> `/descriptorByName/`

Three places in `RemoteConnection/config.jelly` changed from `/descriptor/...` to `/descriptorByName/...`.

**This is not a 404 fix.** In Jenkins core's `jenkins.model.Jenkins`, `getDescriptorByName(String)` is an
**alias** for `getDescriptor(String)` (stated in the core source comment), so both resolve through the same
route. On a real controller running our `e83534b` build, all 6 URLs in both spellings returned **HTTP 200**.

Furthermore, the URL that Jenkins core's `Descriptor#getHelpFile(Klass, String)` generates is the
`"/descriptor/" + getId() + "/help"` form. **Our `e83534b` spelling is therefore the one that follows core's
default.** His change is harmless in itself, but has a side effect:

- `LockableResourcesManager/config.jelly` in the same plugin still uses `/descriptor/` in 5 places, so
  **the spelling is now split within the plugin**

One of the two should be chosen ([§12-2](#12-findings)).

---

## 7. Analysis 4: the `X_SERVER_ID` / `X_LOCK_ID` env vars

A new `LockStepExecution#withRemoteMetadata()` injects `X_SERVER_ID` and `X_LOCK_ID` for a `variable` named
`X`, **only inside the body of a remote lock** (`bd48b1e`).

```groovy
lock(label: 'plc', quantity: 2, serverId: 'remote-server-1', variable: 'PLC') {
  echo "${env.PLC}"            // plc-a,plc-b     (unchanged)
  echo "${env.PLC0_ip}"        // 10.0.0.11       (unchanged)
  echo "${env.PLC_SERVER_ID}"  // remote-server-1 (new)
  echo "${env.PLC_LOCK_ID}"    // lock-1          (new)
}
```

**Assessment:**
- Nothing is added for a local `lock()` (early return when `remoteSession == null`), so the "transparent
  equivalence" we have held since M1A is not broken at the local call site. Reasonable as a design.
- No collision with the existing env naming (`X`, `X0`, `X0_<prop>`). `X_SERVER_ID` has no index, so its
  namespace never crosses the property-derived `X0_ip` form.
- However, the call sits inside `if (lockEnvVars != null && !lockEnvVars.isEmpty())`, so
  **if the remote returns empty `lockEnvVars`, `X_SERVER_ID` / `X_LOCK_ID` are not injected either**.
  There is currently no path where the server returns empty while `variable` is set, but the contract is
  weak ([§12-6](#12-findings)).
- `@edu.umd.cs.findbugs.annotations.CheckForNull` is written inline as an FQCN instead of being imported.
  The same file already imports `NonNull` from that package, so stylistically it should use an import.

---

## 8. Analysis 5: JCasC `@Symbol` and the `flushPendingSave` guard

### 8.1 `@Symbol("lockableResourcesManager")` (`c8162cf`)

`@Symbol` was added to `LockableResourcesManager` — a change that **pins the JCasC key explicitly**.

**Verification:** porting his three new CasC tests onto an `e83534b` worktree (which has no `@Symbol`)
yields **7/7 PASS**. In other words JCasC already resolved it as `lockableResourcesManager` without the
annotation (`GlobalConfiguration`'s default is the decapitalized class name, which happens to be identical).

-> **Not a bug fix, but hardening** that prevents the JCasC key from breaking implicitly if the class is
ever renamed. It also becomes explicit in the JCasC schema/export, so it is worth taking.

### 8.2 Null tolerance in `flushPendingSave()` (`c8162cf`)

```java
-LockableResourcesManager lrm = LockableResourcesManager.get();
+LockableResourcesManager lrm = GlobalConfiguration.all().get(LockableResourcesManager.class);
+if (lrm == null) { return; }
```

`LockableResourcesManager.get()` throws `IllegalStateException` when it cannot resolve. `@Terminator` runs
during Jenkins shutdown (a point where the ExtensionList may already be tearing down), so this is a
defensive change to avoid throwing there. Neither this run's `mvn verify` nor the CasC test logs contain
`LockableResourcesManager is not registered`, so **no actual failure was reproduced** — it is pure
prevention.

> A subtle difference: the `Jenkins.get().getDescriptorByType(...)` fallback that `get()` had is dropped.
> In a situation where the descriptor is alive but cannot be found through `GlobalConfiguration.all()`,
> **a pending save would be silently skipped instead of flushed**. That path is hard to imagine in
> practice, but it is a narrowing of the contract.

---

## 9. Analysis 6: the two new documents

### 9.1 `src/doc/examples/remote-api-curl.md` (293 lines)

A curl recipe collection for external scripts that do not use Pipeline: a complete shell script for
acquire -> poll -> heartbeat -> release, examples for label / skipIfLocked / timeout / priority, and an API
reference table.

**Every item was cross-checked against a real controller (jenkins-a with `8fd2193` deployed).**

| What the doc says | Measured | Verdict |
|---|---|---|
| `POST /acquire/` -> 202 `{lockId, state}` | 202 `{"lockId":"...","state":"ACQUIRED"}` | ✅ |
| `GET /acquire/{lockId}/` -> 200 + `lockEnvVars` | 200; returns `RES`/`RES0`/... when `variable` is set | ✅ |
| `POST /lease/{id}/heartbeat` -> 204 / 410 Gone | 204; 410 `LOCK_NOT_FOUND` after release | ✅ |
| `POST /lease/{id}/release` -> 204, idempotent | 204; a second call is also 204 | ✅ |
| 400 `MISSING_TARGET` | 400 `{"errorCode":"MISSING_TARGET",...}` | ✅ |
| 404 `UNKNOWN_RESOURCE` / `UNKNOWN_LABEL` | both 404 with matching errorCode | ✅ |
| `quantity: 0` (or omitted) = all | acquired all 44 label matches, `RES0`–`RES43` | ✅ |
| `skipIfLocked: true` -> `SKIPPED` | 202 `{"state":"SKIPPED"}` | ✅ |
| Timeout expiry is `FAILED` + `LOCK_WAIT_TIMEOUT` | matches the code (`RemoteQueueEntry#onTimeout`) | ✅ |
| `inversePrecedence` is accepted but not applied to queue ordering | only stored in `RemoteLockRequest`; ordering uses `priority` alone | ✅ |
| API token required (a password gives 403 via CSRF) | password = 403 "No valid crumb"; token = 202 | ✅ |
| State table lists `EXPIRED` ("Allocation timeout elapsed") | **the server never returns `EXPIRED`** (`RemoteLockState` is QUEUED/ACQUIRED/SKIPPED/FAILED/STALE). An allocation timeout is `FAILED` + `LOCK_WAIT_TIMEOUT` | ❌ needs fixing |
| State table omits `STALE` | `GET` can return `STALE` (when heartbeats stop) | ❌ needs adding |
| "send a heartbeat every `heartbeatIntervalSeconds`" | the server accepts the value but **ignores it**, using a fixed `STALE_THRESHOLD_MS = max(default 10s x 6, 60s) = 60s` | ⚠️ needs a note |
| Example lockId `lr-abc123` | actually a UUID (`70ee8eee-353f-...`) | ⚠️ cosmetic |

> `EXPIRED` / `CANCELLED` / `UNKNOWN` do exist in the **client-side** `RemoteAcquireState` enum, but what
> the server's `GET /acquire/{lockId}` returns is `RemoteLockRecord#getState()` (i.e. `RemoteLockState`).
> The doc's state table conflates the two.

### 9.2 `src/doc/examples/remote-lock-pipeline-pattern.md` (130 lines)

The "local gate + remote lock" double-lock pattern: acquire local then remote, release in reverse order,
and namespace the gate name as `serverId::resource`. The closing "Single source of truth" section (local
gate order is only for fairness; the actual resource allocation is always decided by the remote) precisely
defuses the misunderstanding that arises with label + quantity, and is **a high-quality explanation of the
design intent**.

Both documents are also added to the `readme.md` index.

---

## 10. Analysis 7: the new tests

| Test | Count | Content | Result on `e83534b` |
|---|---|---|---|
| `RemoteApiClientTest#testHttp404Preserves...` | 1 | 404 preserves `httpStatus` / `remoteCode` / message / hint | **FAIL** (`expected: <404> but was: <-1>`) — an effective regression guard |
| `ConfigurationAsCodeTest` (3 remote cases) | 3 | JCasC can configure the server side / client side / resources | PASS (`@Symbol` not required) |
| `LockStepExecutionEnvVarsTest` | 3 | `buildLockEnvVars` indexing / properties, plus `withRemoteMetadata` | n/a (depends on the new method) |
| `LockStepRemoteTest#lockWithLabelPropagates...` | 1 | property env vars for multiple resources plus remote metadata env vars under label+quantity | new functionality |

The new CasC fixture `configuration-as-code-remote.yml` covers both the server side
(`remoteApiEnabled`, `exposeLabel`) and the client side (`clientId`, `forcedServerId`, `remotes[]`),
filling **a JCasC contract test we never wrote**.

`LockStepExecutionEnvVarsTest` reaches `withRemoteMetadata` (private) and `RemoteLockSession.serverId`
(private) via reflection. That is fragile under refactoring, so where possible the method should be raised
to package-private and the reflection removed (minor).

---

## 11. Measurement log (before / after)

Environment: `dev/jenkins-env` (jenkins-a/b/c/d on 8081-8084), reusing the resources and remote
configuration left by earlier E2E runs.

> **Environment trap (re-confirmed)**: `start.sh` only places the hpi under
> `/usr/share/jenkins/ref/plugins/`, so **a new build is not picked up** when
> `jhX/plugins/lockable-resources.hpi` already exists. This was hit again during this review.
> To swap the build while keeping the configuration: `docker compose stop` -> replace
> `lockable-resources.hpi` in each `jhX/plugins/` and delete the exploded directory ->
> `docker compose start`.

### 11.1 Authentication: API token vs password

```
# password (admin:admin)
POST /lockable-resources/remote/v1/acquire/  -> HTTP 403
  <title>Error 403 No valid crumb was included in the request</title>

# API token (admin:110a009e...)
POST /lockable-resources/remote/v1/acquire/  -> HTTP 202  {"lockId":"...","state":"ACQUIRED"}
```
-> Exactly as his help text and doc state. **A good catch that plugs a hole in our own help/docs.**

### 11.2 Both help URL spellings (against the `e83534b` build)

```
200  /descriptor/org.jenkins.plugins.lockableresources.RemoteConnection/help/{serverId,url,credentialsId}
200  /descriptorByName/org.jenkins.plugins.lockableresources.RemoteConnection/help/{serverId,url,credentialsId}
```
-> 6/6 return 200. The move to `/descriptorByName/` is not a 404 fix.

### 11.3 Held By column / Queue tab

See [§5](#5-analysis-2-ui--the-held-by-column-and-the-queue-tab) (before: an empty broken link and an empty
queue; after: the clientId is shown and the queue has one row).

### 11.4 CI gates (`mvn clean verify` @ `8fd2193`)

```
[INFO] Tests run: 394, Failures: 0, Errors: 0, Skipped: 1
[INFO] --- spotbugs:4.9.8.3:check (spotbugs) @ lockable-resources ---        <- PASS
[INFO] --- access-modifier-checker:1.35:enforce (default-enforce) ---        <- PASS
[INFO] --- spotless:3.5.1:check (default) @ lockable-resources ---
[ERROR] The following files had format violations:
[ERROR]     src/main/java/org/jenkins/plugins/lockableresources/LockableResource.java
[ERROR]         @@ -1,876 +1,876 @@
[ERROR]         -/*\r\n
[ERROR]     ... (1704 more lines that didn't fit)
[ERROR] Run 'mvn spotless:apply' to fix these violations.
[INFO] BUILD FAILURE
[INFO] Total time:  19:52 min
```

**Summary**: tests **394 run / 0 failures / 0 errors / 1 skipped** (including the 8 new tests); spotbugs
(effort=Max, threshold=Low) and access-modifier-checker pass. **The only failure is spotless:check, caused
by the CRLF.** That is 8 more tests than the 386 at `e83534b` (`LRR_RESULT_P1_M1I.md`), all green.

Canonical report: **`dev/reports/20260726084233-mvn-verify.md`** (generated by `run-mvn-verify.sh`, 18:37).

```
| spotless:check                            | FAIL |
| spotbugs:check (effort=Max, threshold=Low)| ok   |
| checkstyle:check                          | ok   |
| pmd:check                                 | ok   |
| tests | Tests run: 394, Failures: 0, Errors: 0, Skipped: 1 |
```

> During this cycle, **`PLUGIN_DIR` support was added to `run-mvn-verify.sh`** (the same convention as
> `start.sh` / `run-e2e.sh`). The target repository used to be hardcoded to
> `../../lockable-resources-plugin`, so his clone could not be verified at all and — worse — running it
> unaware **silently verified our own `e83534b` and reported SUCCESS**. A display bug was fixed at the same
> time: the warning line printed "(tests skipped)" even without `--skip-tests`
> (`${SKIP_TESTS:+...}` is truthy even for the string `false`).
>
> ```bash
> PLUGIN_DIR=../../jenkinsci/lockable-resources-plugin ./run-mvn-verify.sh
> ```

### 11.5 E2E regression (`run-e2e.sh --clean-start` @ `8fd2193`)

```
PLUGIN_DIR=../../../jenkinsci/lockable-resources-plugin ./run-e2e.sh --clean-start
Scenario summary: pass=21 fail=0 skip=0
```

**All 21 scenarios PASS, 0 fail** (`dev/reports/20260726094517-e2e-test.md`, 09:45-10:00).
S01-S18 (`s-series` / `m1i-series`) and D01-D03 (`d-series`), no regressions.

The places where his change could plausibly have altered behaviour were also green:

| Scenario | Concern | Result |
|---|---|---|
| `remote-unknown-rejected` (S17) | The enriched 404 message might no longer match CP02's matcher | PASS (the regex `HTTP 404\|UNKNOWN_RESOURCE` also matches the new message) |
| `fail-closed` (S07) | `auth-error` changes from "communication failure" to "returned HTTP 403" | PASS (the matcher already includes `returned HTTP 403`) |
| `remote-acquire-timeout` (S18) | M1I's regression guard; effect of the revived 404 branch | PASS (the server-side path that emits `LOCK_WAIT_TIMEOUT` is unchanged) |
| `heartbeat-resilience` (S11) | Changed heartbeat exception messages | PASS |

### 11.6 Pressing "Change Position" on a remote queue row

Measured with exactly one remote waiter in the queue (and zero local queue entries), calling
`changeQueueOrder`:

```
POST /lockable-resources/changeQueueOrder  id=<lockId>  index=1
-> HTTP 423
   Error 423 The queue position 1 is out of range (1 - 0)!
```

One row is visible on screen, yet the answer is "the range is 1-0". Since the button is rendered for remote
rows too, users will inevitably hit this ([§12-3/4](#12-findings)).

### 11.7 Load test (`run-load.sh --preset stress` @ `8fd2193`)

G01 grid-storm (all 4 controllers act as both server and client, 50 jobs each = **200 concurrent**,
3 iterations, 60s hold, 3-minute remote allocate timeout) was run **twice**.

| run | plugin | SUCCESS | FAILURE | Failure breakdown | Overlap violations | HUNG / UNKNOWN | queue wait p95 |
|---|---|---|---|---|---|---|---|
| baseline `20260719115008` | `e83534b` | 182 | 18 | all clean `LOCK_WAIT_TIMEOUT` | **0** | **0** | — |
| run 1 `20260726100200` | `8fd2193` | 186 | 14 | all clean `LOCK_WAIT_TIMEOUT` | **0** | **0** | 171.5 s |
| run 2 `20260726101522` | `8fd2193` | 181 | 19 | all clean `LOCK_WAIT_TIMEOUT` | **0** | **0** | 148.9 s |

**No regression.** The swing in the SUCCESS/FAILURE ratio (186/14 vs 181/19 vs the baseline's 182/18) is
variance caused by the p95 wait (149-171 s) sitting just under the allocate timeout (180 s); **every failure
is a clean, fail-closed allocation timeout**, not a locking inconsistency.

**The invariants that matter passed in all three runs:**

- **0 mutual-exclusion overlap violations** — no instant where a resource was held beyond its capacity
- **0 HUNG / UNKNOWN** — no deadlock and no lost wakeup

Only the latest artifact `dev/reports/20260726101522-load-test.md` is retained (run 1 was removed under the
"keep only the newest" policy; its numbers are transcribed in the table above).

> **`run-load.sh` fix**: run 1's report mislabelled `plugin under test` as **`4dbbfc1` (our repo's master)`**,
> because `run-load.sh:326` — like `run-mvn-verify.sh` — hardcoded the plugin repository path and read the
> default path's HEAD rather than the jenkinsci clone that was actually deployed. It now honours
> `PLUGIN_DIR`, and run 2 correctly records `8fd2193`.

---

## 12. Findings

| # | Severity | Finding | Action |
|---|---|---|---|
| 1 | ⛔ **Blocker (in progress)** | `22c7b2b "spotles"` converted `LockableResource.java` to CRLF. **It already reached PR #1055 via `3a555fe`, and #1055's CI is red** ([§2.2](#22-how-the-prs-relate-and-why-the-crlf-is-already-in-pr-1055)). It also inflates a 13-line diff to 1739 lines. **Not caused by us** (upstream master and all of our commits are consistently LF; `spotless:check` is SUCCESS on the parent `7fd218b`, and the commit changes nothing byte-wise) -> [§2.1](#21-who-introduced-the-crlf--settled-from-history) | **Asked him to restore LF on the `feature/1025-remote-lr-p1-m1` side** (2026-07-26, together with the PR #1 approval). We cannot fix it first because that would make merging PR #1 conflict wholesale. Restore the line endings directly rather than via `spotless:apply`, which can produce the same result on Windows. Prevention is `.gitattributes` with `*.java text eol=lf` (best as a separate PR after #1055 lands) |
| 2 | ⚠️ Medium | The help-URL spelling is now split within the plugin (`RemoteConnection` uses `/descriptorByName/` in 3 places, `LockableResourcesManager` uses `/descriptor/` in 5). Core's own generator emits the `/descriptor/` form | Unify on one. Reverting to `/descriptor/` follows core |
| 3 | ⚠️ Medium | The Queue tab now lists remote rows, but the **"Change Position" button is rendered for them as well** (the JS only checks `hasQueuePermission`, never `type`). `changeQueueOrder` only handles `queuedContexts`, so **pressing it always errors**. **Measured: `HTTP 423 The queue position 1 is out of range (1 - 0)!`** | Either hide the button on remote rows (exclude `item.type === "remote"` in the JS) or make `changeQueueOrder` remote-aware |
| 4 | ⚠️ Medium | The same button validates the position against `newPosition < queuedContexts.size()`, while the screen shows local + remote combined. **Even a local row can be wrongly rejected as out of range** (the measurement above is exactly this path: one row displayed, zero local queue entries) | Needs design work together with #3 |
| 5 | ⚠️ Low | The display order is a plain concatenation of "all local, then all remote" and does not reflect the actual promotion order (`proceedNextContext` compares priorities across both and favours local on ties). The index column is misleading | Sort the merged list by descending priority before assigning the index |
| 6 | ⚠️ Low | The queue's free-text `filter` only matches `lockId` for remote rows (`resourcesMatch()`/`labelsMatch()` are false and `getBuild()` is null). The `request` column filter does work | Add `item.getRemoteRequest()` / `getRequestedBy()` to the `filter` branch |
| 7 | ⚠️ Low | `withRemoteMetadata` is only called when `lockEnvVars` is non-empty, so `X_SERVER_ID`/`X_LOCK_ID` are dropped on an empty response | Move it outside the condition, or state the precondition in the docs |
| 8 | ⚠️ Low | In `remote-api-curl.md`, the state table **wrongly lists `EXPIRED`** and **omits `STALE`**; it also does not mention that the server ignores `heartbeatIntervalSeconds` and uses a fixed 60s threshold | Fix the doc (evidence in the table in [§9.1](#91-srcdocexamplesremote-api-curlmd-293-lines)) |
| 9 | ℹ️ Info | The credentials selector filters by URI domain requirements, while `RemoteCredentials.basicAuthHeader()`'s fallback only scans `Domain.global()`. A credential in a non-global domain may be **selectable but unresolvable** (outside a Run context) | Unlikely in practice. A future tidy-up |
| 10 | ℹ️ Info | `LockStepExecutionEnvVarsTest` depends on reflection into private members | Raise visibility to package-private and drop the reflection |
| 11 | ℹ️ Info | The commit messages `more things` / `other findings` / `spotles` are not descriptive | Squash or reword before it goes upstream |
| 12 | ℹ️ Info | The new message key `resource.heldBy.remoteUnknown` exists only in `table.properties` (English); `table_{cs,de,fr,sk}.properties` are not updated | Fine to leave to the Crowdin sync (undefined keys fall back to the base bundle) |

### 12.1 Consistency with the design principles (transparent equivalence)

Checking for deviations against the principles established across M1A-M1G.

#### One deviation (needs a decision)

**`X_SERVER_ID` / `X_LOCK_ID` go against an explicit M1D decision.**

`LRR_DESIGN_P1_M1D.md` §3-2 ("env vars: extract into a shared function") states that the inline env-var
generation in `proceed()` was extracted into a shared function so that **local and remote call the same
function**. The code says so too: `RemoteResolver.remoteLockEnvVars`'s javadoc reads
"identical to local, including resource-property env vars".

His implementation **does not touch** `buildLockEnvVars` (the shared function). It adds two keys to the
return value at the injection site (`LockStepExecution.runBody`, remote path only), so **the shared
function's contract is preserved**. But **the env observed inside the lock body is no longer identical
between local and remote**. The asymmetry runs in this direction:

| | local `lock()` | remote `lock(serverId:)` |
|---|---|---|
| `X`, `X0`, `X0_<prop>` | yes | yes (identical) |
| `X_SERVER_ID`, `X_LOCK_ID` | **no** | yes |

-> A pipeline written for remote breaks when moved to local, because `X_SERVER_ID` becomes null. That is a
step back from the goal of transparent equivalence, "the same pipeline code works either way".

**There is a defence, though**: these two values carry **nothing but bridge-derived information** (which
server, which lockId). They do not violate the letter of the M1F lens, "do not add remote-specific
judgements **that are not bridge-derived**". A **design decision is needed**: either accept it and record in
the design docs that "bridge-specific metadata is out of scope for transparent equivalence", or drop it as
unnecessary. Leaving it undecided would repeat the M1E-1 pattern of an "intentionally retained" item that
was never written down.

#### No deviation (reassurance)

| Principle | Verdict |
|---|---|
| Do not contaminate the canonical path (`getAvailableResources` / `proceedNextContext` / `buildLockEnvVars`) | ✅ unchanged |
| The exposure filter is exposeLabel alone (the ExtensionPoint was removed in M1E) | ✅ unchanged |
| Admission: unknown/unexposed is a 404 (M1E's intentional non-equivalence) | ✅ unchanged |
| `GET /acquire/{lockId}` is a pure read (the M1H B2 decision) | ✅ the new `getCurrentRemoteQueueEntries` is also a read-only snapshot |
| QUEUED expiry is folded onto `timeoutForAllocateResource` (M1H) | ✅ unchanged |
| Phase 1 scope = locking + **server-side ops UI** | ✅ Held By and Queue are both server-side ops UI, i.e. in scope |
| Permission boundary | ✅ `clientId` is already exposed to VIEW holders via `resource.status.remoteLockedBy`; nothing newly exposed |

#### Sources of future drift (documentation, not code)

1. **The `EXPIRED` error** ([§12-8](#12-findings)) is the most dangerous. It **documents a state the server
   never emits as if it were the contract**, so a successor "implementing what the doc says" would be pulled
   towards adding `EXPIRED` to `RemoteLockState`. The reality is `FAILED` + `errorCode=LOCK_WAIT_TIMEOUT`
   (the wording settled in M1I).
2. **`heartbeatIntervalSeconds`**: the doc reads as "send at this interval", but Phase 1 explicitly decided —
   with a comment in `RemoteApiV1Action` — to "accept the value but ignore it and use the server's fixed
   `STALE_THRESHOLD_MS` (=60s)". The doc contradicts the decision.
3. **The prescriptive tone of `remote-lock-pipeline-pattern.md` about the local gate**: written imperatively
   as "Always acquire in this order", it reads as though **`lock(serverId:)` alone were insufficient**. The
   design intent is that it is sufficient and safe on its own; the gate is an optional operational pattern.
   It also omits the side effect that **the gate stays locked for the entire remote wait** (our default
   `timeoutForAllocateResource` is unbounded); used inside `node {}` it occupies an executor as well.
   It should be labelled an "optional pattern".

### 12.2 A design issue on our side that this PR surfaced (deferred to a later cycle)

His `RemoteApiClient` fix made `RemoteLockSession.pollOnce()`'s 404/410 branch **actually execute for the
first time**, which exposed a twist left in our own (M1I) code. **This is not a problem with his PR**, so it
is only recorded here and not addressed in this PR (confirmed with the user, 2026-07-26).

#### The polling lifecycle

```java
case ACQUIRED:
    bodyStarted = true;
    cancelPollTask();      // <- polling stops the moment the lock is acquired
    startHeartbeat(...);   // <- from here only heartbeats run (failures only log a warning; the job continues)
    host.runBody(...);
```

`onResume` likewise does not resume polling when `bodyStarted == true`; it releases best-effort and fails.

#### Reachability of the two branches, and the twisted labels

| Branch | Reachability | Current message |
|---|---|---|
| `!bodyStarted` (record vanishes while QUEUED) | **reachable** | normalized to `LOCK_WAIT_TIMEOUT` |
| `bodyStarted` (lease vanishes) | **essentially unreachable by design** (polling stops at acquisition; only a one-iteration in-flight race window) | `server may have restarted` |

Moreover, M1I's server-side fix (the `terminalAt`-based TTL) means a **legitimate allocation timeout returns
`200 + FAILED + errorCode=LOCK_WAIT_TIMEOUT`, not a 404**. The main remaining trigger on the `!bodyStarted`
side is therefore **"the peer server restarted while we were QUEUED"**, and reporting that as
`LOCK_WAIT_TIMEOUT` is semantically inaccurate.

-> **The two labels are swapped relative to reality** (the reachable branch carries the timeout label; the
unreachable one carries the restart label). A fix would reword the `!bodyStarted` message towards "the
record no longer exists (the server may have restarted)" and state explicitly that genuine allocation
timeouts are now funnelled through the server-side FAILED path — but this is **deferred to a later cycle**.

#### Decision on E2E coverage

Adding an E2E scenario that exercises this path ("restart the peer while the client is QUEUED") was
considered but **will not be added** (confirmed with the user, 2026-07-26). Reasons:

- For the purpose of deciding whether to merge his PR, the existing 21-scenario regression run
  ([§11.5](#115-e2e-regression-run-e2esh---clean-start--8fd2193)) is sufficient. The UI changes are
  display-only and the env vars are unit-tested by him
- The current label is under review as described above, and **we do not want to cement it in a test**
- Once the labelling is decided, writing the scenario against that specification avoids rework

> Note that the `bodyStarted` branch cannot be exercised by an E2E even if one were written: after
> acquisition polling has stopped, so killing the server mid-hold lands on the heartbeat path — the
> territory of the existing S11. This corrects our initial assumption.

---

## 13. Integration plan and current state

### 13.1 Done (2026-07-26)

1. **Approved PR #1**
   ([review 4780503811](https://github.com/kohtaro-satoh/lockable-resources-plugin/pull/1#pullrequestreview-4780503811)),
   after running the full verification suite (verify 394/0/1skip, E2E 21/21, load stress).
2. **Inline comment on the `RemoteApiClient` fix**
   ([review 4780427470](https://github.com/kohtaro-satoh/lockable-resources-plugin/pull/1#pullrequestreview-4780427470)),
   noting that `RemoteApiException extends IOException` made it get swallowed by its own
   `catch (IOException)`, and confirming that `pollOnce()`'s 404/410 branch is now reachable.
3. **Asked him to restore the CRLF to LF** (PR #1 review plus a PR #1055 comment).
   **Having him do it is the only safe order**, because fixing it on our side first makes merging PR #1
   conflict wholesale ([§2.2](#22-how-the-prs-relate-and-why-the-crlf-is-already-in-pr-1055)).

### 13.2 Waiting for his merge

He has stated "review it and then we can merge it together and go live", so the flow to wait for is
**merge PR #1 -> restore LF -> land PR #1055 on master**.

### 13.3 Where the residual items go

**Involvement with this project is planned to end after three PRs: Phase 1 (#1055), Phase 2 and Phase 3**
(decided 2026-07-26). Residual items therefore do not get their own PRs; they **ride along with the
Phase 2 PR**.

#### To be fixed together in the Phase 2 PR

| Item | Source | Content |
|---|---|---|
| **The 404/410 label twist in `RemoteLockSession`** | [§12.2](#122-a-design-issue-on-our-side-that-this-pr-surfaced-deferred-to-a-later-cycle) | The reachable `!bodyStarted` side carries the timeout label while the unreachable side carries the restart label. Ours (from M1I) |
| **The state table in `remote-api-curl.md`** | [§12-8](#12-findings) | `EXPIRED` is wrong (the server never returns it), `STALE` is missing, and the server-side handling of `heartbeatIntervalSeconds` is undocumented |
| **The Queue tab's Change Position button** | [§12-3/4](#12-findings) | Rendered on remote rows, always 423 when pressed. To be cleared while touching the client UI in Phase 2 |
| **Documenting the status of `X_SERVER_ID` / `X_LOCK_ID`** | [§12.1](#121-consistency-with-the-design-principles-transparent-equivalence) | Decide whether to record "bridge-specific metadata is out of scope for transparent equivalence" in the design docs, or drop the vars |

#### Deliberately not doing

| Item | Reason |
|---|---|
| **Adding `.gitattributes` (`*.java text eol=lf`)** | It would durably prevent the environment-dependent CRLF recurrence, but it is a **repository-wide convention change**, which looks like overreach from a contributor who leaves after Phase 1-3. The need is left to the maintainer's judgement |
| **Unifying the help URL spelling** ([§6.2](#62-help-links-descriptor---descriptorbyname)) | Same as above. The split between `/descriptor/` (5 places) and `/descriptorByName/` (3) is cosmetic, with no behavioural difference (both spellings measured at 200) |

> **Timing note**: the Change Position 423 and the `EXPIRED` doc error **ship in released code the moment
> #1055 lands on master**, and users may hit them until Phase 2. He may fix them himself before merging
> #1055, so **a heads-up before the merge** reduces rework (there is no need for us to own them).

---

## 14. Appendix: reproduction commands

```bash
# Substantive diff (CRLF excluded)
git -C jenkinsci/lockable-resources-plugin diff --stat -w e83534b..8fd2193

# Locating where the CRLF came from
for r in 7fd218b 22c7b2b e83534b HEAD; do
  echo -n "$r CR="; git show "$r:src/main/java/org/jenkins/plugins/lockableresources/LockableResource.java" | tr -cd '\r' | wc -c
done

# CI gates
mvn -B -ntp clean verify
mvn -B -ntp spotless:check

# Proving it fails on the old code (evidence that this is a real bug fix)
git worktree add --detach /tmp/wt-e83534b e83534b
cp .../RemoteApiClientTest.java /tmp/wt-e83534b/src/test/java/.../RemoteApiClientTest.java
cd /tmp/wt-e83534b && mvn -o -Dtest=RemoteApiClientTest -Dspotless.check.skip=true -Dspotbugs.skip=true test

# Deploying a new build to the real environment (keeping the configuration)
cd dev/jenkins-env
PLUGIN_DIR=../../../jenkinsci/lockable-resources-plugin ./start.sh
docker compose stop
for jh in jha jhb jhc jhd; do rm -rf $jh/plugins/lockable-resources; cp docker/lockable-resources.hpi $jh/plugins/; done
docker compose start

# Full verification against another clone
PLUGIN_DIR=../../jenkinsci/lockable-resources-plugin ./run-mvn-verify.sh
PLUGIN_DIR=../../../jenkinsci/lockable-resources-plugin ./run-e2e.sh --clean-start
PLUGIN_DIR=../../../jenkinsci/lockable-resources-plugin ./run-load.sh --preset stress

# Issuing an API token (required: password auth is rejected by the CSRF crumb check)
CR=$(curl -s -u admin:admin -c cj "$J/crumbIssuer/api/json" \
     | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['crumbRequestField']+': '+d['crumb'])")
curl -s -u admin:admin -b cj -H "$CR" --data-urlencode 'script=
  import jenkins.security.ApiTokenProperty
  def u = jenkins.model.Jenkins.get().getUser("admin")
  println("TOKEN=" + u.getProperty(ApiTokenProperty).tokenStore.generateNewToken("x").plainValue)
  u.save()' "$J/scriptText"

# Queue tab JSON (POST required since PR #1048)
curl -s -u admin:$TOKEN -b cj -H "$CR" -X POST "$J/lockable-resources/getQueuePage?page=1&size=25"
```

---

## Related documents

- `LRR_RESULT_P1_M1I.md` — the origin of the "safety net" referred to in §4.3
- `LRR_ISSUE_P1_M1H_queued_expiry_poll_404.md` — the original investigation of the mislabelled 404
- `LRR_REVIEW_P1_M1H.md` — the previous review of maintainer feedback
- `../E2E_TEST_SPECIFICATION.md` — the matchers of the `fail-closed` scenario (the basis for the
  compatibility judgement in §4.5)
