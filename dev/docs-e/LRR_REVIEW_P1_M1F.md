# Remote LR Development Review (Phase 1 / M1F completion)

> **Review date:** 2026-06-14
> **plugin diff under review:** `feature/1025-remote-lockable-resources-p1-m1e` (`5d956de`)..`feature/1025-remote-lockable-resources-p1-m1f`
>   (HEAD `6319f12`), the **M1F delta** (4 files / +109 -2). M1F is a cleanup cycle on top of M1E, so the review primarily targets the
>   **M1E→M1F diff** (the full `master` diff is already covered by `LRR_REVIEW_P1_M1E.md`; M1F adds no new code there, only the selected
>   handling of M1E findings).
> **Documents:** `dev/docs-e/` (LRR_DESIGN_P1_M1F / LRR_IMPLEMENTATION_STEPS_P1_M1F / LRR_RESULT_P1_M1F),
>   `LRR_REVIEW_P1_M1E.md` (origin of the findings + M1F-handling banner).
> **Lens:** whether M1F faithfully honors its core goal — "**triage M1E findings under a single lens: ride the existing lock() logic and
>   add no remote-specific decisions that are not network-bridge-derived**"; whether the three implemented items (L-b/L-c/L-d) stay
>   **confined to the HTTP boundary, add no new fail-open, and leave canonical delegation and transparent-equivalence semantics untouched**;
>   whether the five deferred items (M1E-1/M1E-2/M1E-3/L-a/L-e) are documented well enough to prevent re-litigation; and any new regressions.
> **Method:** static read of the `6319f12` diff and code. Test count (382) / E2E (20/20) trusted from records whose existence was verified
>   (`dev/reports/20260614104134-mvn-test.log` = `Tests run: 382, Failures: 0, Errors: 0, Skipped: 1` / `BUILD SUCCESS`;
>   `dev/reports/20260614105955-e2e-test.md` = pass:20 / fail:0; working tree clean at `6319f12`).

---

## Table of contents

1. [Overall assessment](#1-overall-assessment)
2. [Lens compliance — was the triage actually honored?](#2-lens-compliance--was-the-triage-actually-honored)
3. [Validity of the three implemented items](#3-validity-of-the-three-implemented-items)
   - [L-b (URL scheme validation)](#l-b)
   - [L-c (POST body cap)](#l-c)
   - [L-d (FAILED→4xx mapping)](#l-d)
4. [Findings (all Low / nit)](#4-findings-all-low--nit)
5. [Assessment of the deferred items](#5-assessment-of-the-deferred-items)
6. [Test / verification layer](#6-test--verification-layer)
7. [Recommended actions (prioritized)](#7-recommended-actions-prioritized)

---

## 1. Overall assessment

**M1F is an exemplary cleanup cycle in which the code does not betray the lens declared in the design.** It is not a feature cycle but a
selective handling of M1E review findings; the only things implemented are three hardenings of the HTTP transport/boundary layer
(L-b/L-c/L-d). None of them touches lock() semantics, canonical delegation, transparent equivalence, or the exposeLabel exposure policy.
The five deferred items are written up in design §4 as "intentionally deferred concerns (to prevent re-litigation)," and a handling banner
was added to the M1E review itself.

- Diff is minimal: **+109 -2 / 4 files** (two of them tests). Zero new public API, zero new state, zero new remote-specific decisions.
- **No new fail-open whatsoever.** All three changes move in the "reject more strictly" direction; none creates a path to an erroneous
  lock grant. L-d in fact **closes** a path where a future FAILED could leak through as a 202 success.
- Build 382/0/1-skip and E2E 20/20 confirmed against existing reports. The policy of **adding no new E2E and keeping the existing 20/20
  regression** is appropriate here, where the change is confined to the HTTP boundary and directly covered by unit tests.

**Conclusion: PR-quality within this scope. No blockers.** All findings below are Low / nit and do not impede merge.

---

## 2. Lens compliance — was the triage actually honored?

Against design §1's lens ("ride the existing lock() logic and add no remote-specific decisions that are not network-bridge-derived"), I
confirmed there is **no lens violation in the code** (i.e., no non-bridge remote-specific decision crept in).

| Implemented item | Layer touched | Interference with lock()/canonical/exposure semantics | Verdict |
|---|---|---|---|
| L-b | `RemoteConnection.validate()` = the gate before config persistence (a transport config value) | None (the URL feeds the HTTP transport only; it does not participate in lock decisions) | Compliant |
| L-c | `parseJsonBody` (HTTP request-body read) | None (an I/O boundary before parsing) | Compliant |
| L-d | HTTP status mapping in the POST handler (the `enqueue` return value is unchanged) | None (it merely maps `enqueue`'s decision onto a 4xx) | Compliant |

All three act either before (config entry) or after (HTTP response mapping) the decision that `enqueue`/`lock()` already made, without
introducing any new remote-specific allow/deny decision. **The triage holds at the code level.**

---

## 3. Validity of the three implemented items

<a id="l-b"></a>
### L-b — remote base URL scheme validation (`RemoteConnection`)

- `validate()` gains an `isHttpUrl` check, rejecting non-http(s) (`file:` / `ftp:` / no scheme) with `IllegalArgumentException`.
  I confirmed **`validate()` is the sole pre-persistence gate**, called from `LockableResourcesManager.setRemotes()`
  ([LockableResourcesManager.java:332](../../lockable-resources-plugin/src/main/java/org/jenkins/plugins/lockableresources/LockableResourcesManager.java#L332)),
  reached by both the form `configure` path and the CasC path. Design §3-1's "effective enforcement point" claim is accurate.
- `DescriptorImpl` is made an `@Extension` with a `doCheckUrl` (`FormValidation`).
  **Verification note:** the parent form includes the jelly directly via `<st:include class="…RemoteConnection" page="config.jelly"/>`
  inside `<f:repeatable field="remotes">` (`LockableResourcesManager/config.jelly:51-53`), so **form rendering was not broken** before
  M1F even without `@Extension`. However, auto-wiring `doCheckUrl` for the `url` field, and resolving the `/descriptor/…RemoteConnection/help-*`
  help links referenced by config.jelly, both require a registered descriptor. So adding `@Extension` is a **net-positive** change that makes
  `doCheckUrl` work and incidentally fixes the help-link 404s, without regressing existing behavior.
- The `isHttpUrl` helper does trim + `Locale.ENGLISH` lowercasing before the prefix check — good, the explicit locale avoids the turkish-i pitfall.

**Valid.** No new fail-open; misconfiguration is caught at config time rather than as an opaque failure at lock() time. Design §3-1 also
states the non-goals (no reachability / FQDN / port validation), so it does not over-validate.

<a id="l-c"></a>
### L-c — POST body size cap (`RemoteApiV1Action`)

- Introduces `MAX_BODY_CHARS = 1 MiB`; `parseJsonBody`'s read loop throws `PayloadTooLargeException` (private, `IOException` subclass) the
  moment the accumulated char count exceeds the cap. The check is **before** `sb.append`, so the buffer never grows past the cap. The POST
  handler catches `PayloadTooLargeException` **before** the generic `Exception`, mapping to 413 `PAYLOAD_TOO_LARGE` (the existing malformed-JSON
  path 400 `INVALID_JSON` is preserved). The catch ordering is correct.
- **Verification note:** `parseJsonBody` has exactly **one call site** in `RemoteApiV1Action` (POST `/acquire`, line 84). release/heartbeat read
  no body — they carry the lockId in the URL path (the `URLEncoder.encode(lockId, …)` path in `RemoteApiClient`). So **the cap covers the only
  body-reading terminal**; there is no gap.
- `total` is an `int`, but it throws at 1 MiB+1, never reaching int overflow (~2 GiB). Safe.

**Valid.** It closes the OOM vector a large body could trigger even for an authenticated client, at the pre-parse I/O boundary — consistent
with the lens (transport hardening).

<a id="l-d"></a>
### L-d — generalizing POST FAILED → 4xx (`RemoteApiV1Action`)

- Before, only `UNKNOWN_RESOURCE`/`UNKNOWN_LABEL` returned 404 and `return`ed; **any other `FAILED` fell through to the 202 success response**
  below. After, the `else` returns 400 (preferring `errorCode`, else `ACQUIRE_FAILED`), and `return;` is moved outside the if/else so **every
  FAILED terminates**. The logic is correct and reliably closes the 202-leak path.
- Design §3-3's defensive framing — "the only non-`UNKNOWN_*` FAILED `enqueue` currently produces is `MISSING_TARGET`, which is already
  unreachable thanks to the boundary MISSING_TARGET check" — matches the code (the existing 404 tests stay green, i.e., observed behavior is unchanged).

**Valid.** A worthwhile "currently unreachable but future-proof" defense, with zero risk (it only tightens the mapping of an unreachable path).

---

## 4. Findings (all Low / nit)

> None block merge. Recorded for the record. May be addressed this cycle or deferred without real harm.

- **F-1 (nit / Low) `isHttpUrl` vs `resolve()` whitespace normalization is asymmetric.**
  `isHttpUrl` does `value.trim()` before the prefix check, so `"  http://x  "` **passes** `validate()`, but the stored `url` is the raw,
  un-trimmed value (`@DataBoundConstructor` stores it verbatim). At send time `RemoteApiClient.resolve()`
  ([RemoteApiClient.java:286-304](../../lockable-resources-plugin/src/main/java/org/jenkins/plugins/lockableresources/remote/RemoteApiClient.java#L286-L304))
  only `trim()`s for the emptiness check and passes the raw value to `URI.create`, so a URL with surrounding whitespace can throw
  `IllegalArgumentException`→`INVALID_CONFIGURATION`. **Not fail-open** (it is rejected at lock time), but it leaves a "said OK at config
  time, errors at runtime" inconsistency. To fix, normalize/store the trimmed value when `validate()` passes, or apply `trim()` in `resolve()`.
  Low priority.
- **F-2 (nit / Low) empty-string errorCode in L-d.**
  `ec != null ? ec : "ACQUIRE_FAILED"` would **emit an empty errorCode** if `ec` is `""`. No real impact today (FAILED records always set a
  non-empty code), but to fully honor the defensive intent, fold empty to `ACQUIRE_FAILED` via a `Util.fixEmpty(ec)`-style guard. Low priority.
- **F-3 (observation / minor) L-c caps characters, not bytes.**
  For OOM prevention (bounding heap occupancy) the character cap is correct and intentional. Just note that a multibyte body's actual byte
  size can modestly exceed 1 MiB (not an attack-surface issue). Recording only; no action needed.

---

## 5. Assessment of the deferred items

For the five "intentionally deferred concerns" in design §4 (M1E-1 / M1E-2 / M1E-3 / L-a / L-e), I confirmed that **the deferral decision
itself is consistent with the lens** and that the documentation is sufficient to prevent re-litigation.

- Deferring **M1E-1 (promotion-path `fromNames(create=true)` ephemeral re-creation)** is consistent with the lens (making remote alone use
  `create=false` would be adding a non-bridge-derived decision). The acceptance rationale also holds: the trigger is narrow (exposed, busy,
  admin deletion while QUEUED), it is **not fail-open** (no erroneous lock is granted), and orphans converge to one per name. Design §4 even
  spells out the concrete future fix (thread a `create` flag through the canonical seam), so the ground for resuming is preserved. **The
  "do not fix" decision is user-confirmed and matches memory [[remote-lock-project-state]].**
- M1E-2 / M1E-3 / L-a / L-e likewise have their category (local-derived / by-design / harmless / perf-only) and deferral rationale recorded;
  none contradicts the lens.

> Carry-over note for the next cycle: M1E-1 is an **intentional deferral, not "resolved."** When promotion-path admission re-validation or
> multi-tenancy comes up in P1+, resume from the `create`-flag proposal in design §4. This review **re-confirms it as a known open item.**

---

## 6. Test / verification layer

- **L-b: 3 tests, sufficient.** `testValidateAcceptsHttpsUrl` (accept), `testValidateRejectsNonHttpUrl` (reject `file:`/`ftp:`/no-scheme),
  `testDoCheckUrl` (http/https=OK, file/empty/null=ERROR). Accept side, reject side, and UI side are all covered. It also follows the
  [[rlr-equivalence-test-defaults]] lesson of poking empty/null (`doCheckUrl(null)`/`("")` are explicit).
- **L-c: 1 test (`acquireWithOversizedBodyReturns413`).** Directly verifies >1 MiB → 413. No exact-boundary (=MAX_BODY_CHARS) test, but the
  `> MAX_BODY_CHARS` condition is unambiguous in code; over-testing is unnecessary. Acceptable.
- **L-d: no direct positive test, and that is legitimate.** The generalized `else` (400 for non-`UNKNOWN_*`) is, by design, **currently
  unreachable from `enqueue`**, so there is no seam to drive it through a test. The existing `UNKNOWN_RESOURCE`/`UNKNOWN_LABEL` 404 tests
  regression-cover the if side and guarantee the `return`-position change did not break the 404 path. Adequate coverage for a defensive change.
- E2E: no new scenarios per policy, existing 20/20 regression maintained — consistent, since the HTTP-boundary change is directly unit-covered.

---

## 7. Recommended actions (prioritized)

1. **(Optional; fine this cycle) Resolve the F-1 whitespace asymmetry.** Either normalize/store the trimmed value when `validate()` passes,
   or apply `trim()` in `resolve()`. One line buys "config OK = runtime OK" consistency. Low cost, low risk.
2. **(Optional) Fold the F-2 empty-string errorCode to `ACQUIRE_FAILED`** (to carry the defensive intent all the way through).
3. **Carry-over (mandatory, record only):** keep M1E-1 under active tracking as an **intentionally deferred known item.** When P1+ takes up
   promotion-path admission re-validation or multi-tenancy, resume from the `create`-flag proposal in design §4 (already registered in
   [[remote-lock-project-state]]).
4. Everything else (M1E-2 / M1E-3 / L-a / L-e) can be deferred per design §4 without issue.

> **Summary:** M1F executes the ideal shape of a cleanup cycle — instead of blindly burning down review findings, it triages them under a
> single user-confirmed lens, confines the implemented items to the HTTP boundary, and documents the deferred items down to re-litigation
> prevention. The three implemented items add no new fail-open and do not contaminate canonical, backed by tests and the build/E2E records.
> Findings are Low / nit only — **PR-quality within this scope.** The one caveat is that M1E-1 is a "known, intentionally deferred item," not
> "resolved," which is correctly recorded in the design and in memory.

---

## Change log

- 2026-06-14: Initial version. Static read of the M1E(`5d956de`)..M1F(`6319f12`) delta (4 files / +109 -2). Confirmed the three implemented
  items (L-b URL scheme validation / L-c body cap 413 / L-d FAILED→4xx) honor the lens ("bridge hardening only; add no remote-specific
  decisions") at the code level, adding no new fail-open and leaving canonical delegation / transparent equivalence untouched. Assessed the
  `@Extension` addition as net-positive (doCheckUrl wiring + descriptor help-link resolution; existing rendering uses `st:include`, so no
  regression). Confirmed the L-c cap covers the only body-reading terminal (POST /acquire). Findings limited to Low/nit: F-1 (isHttpUrl vs
  resolve whitespace asymmetry), F-2 (L-d empty-string errorCode), F-3 (char vs byte cap, observation). Judged the five deferred items
  adequately documented in design §4 and re-confirmed M1E-1 as an intentionally deferred known item. Build 382/0/1-skip and E2E 20/20 verified
  against existing reports. PR-quality within this scope.
