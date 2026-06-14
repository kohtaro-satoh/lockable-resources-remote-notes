# Remote Lockable Resources Specification (Phase 1 / M1F)

> **Source:** [jenkinsci/lockable-resources-plugin #1025](https://github.com/jenkinsci/lockable-resources-plugin/issues/1025)
> **Prerequisite docs:** `LRR_DESIGN_P1_M1E.md` (M1E spec) / `LRR_REVIEW_P1_M1E.md` (M1E completion review)
> **Scope:** Phase 1 M1F (**triage of the M1E-review findings** — implement only network-bridge transport/boundary hardening.
>   Lock()-logic-derived gaps and any growth of remote-specific judgement are intentionally deferred and recorded as
>   "intentionally retained concerns" in this design doc.)

---

## 1. What M1F is — triaging review findings by a single lens

M1F is not a feature cycle. It triages the findings of `LRR_REVIEW_P1_M1E.md` by **one lens** settled with the user, and
implements only those that match.

> **Lens (settled with the user, 2026-06-14):** "**Lean maximally on lock()'s existing logic; do not add remote-specific
> judgement that is not network-bridge-derived.**" Therefore —
> - **A lock()-logic-derived gap → leave as is** (do not add code that treats remote specially). Record it as a concern in the design doc.
> - **Network-bridge (transport / HTTP boundary) hardening → implement** (no interference with lock() semantics or canonical delegation).

## 2. Triage result

| Review finding | Class | M1F decision | Rationale |
|---|---|---|---|
| **M1E-1** (a named resource deleted while QUEUED is re-materialised as an ephemeral by the promotion scan's `fromNames(create=true)` and orphaned) | **lock()-logic-derived** | **Leave code; document** | `create=true` is canonical name resolution itself (local's on-demand ephemeral feature). Making remote alone `create=false` is "adding remote-specific judgement," against the lens. Narrow, not fail-open, converges to one orphan → accepted |
| **admission** (unknown/unexposed → immediate 404) | remote terminal policy | **Keep** | Settled 2026-06-13 (existence hiding + no infinite QUEUE). Single source at enqueue. Not re-litigated |
| **M1E-2** (with resource and label both set, admission inspects resource but resolution uses label) | local-derived ambiguity, not fail-open | **Leave (document)** | local lock() itself prefers label and ignores resource. candidateFilter enforces exposure so no bypass. No remote-specific judgement added |
| **M1E-3** (lease ops authorize on REMOTE permission only, not lockId ownership) | by-design trust model | **Leave (document)** | An ownership check is new remote judgement. Unneeded for the small-scale, mutually-trusting premise. P1+ when multi-tenant |
| **L-b** (`RemoteConnection.url` scheme unvalidated — `file:` etc. pass) | **bridge hardening** | **Implement** | The url is for the HTTP transport (`RemoteApiClient`) only. Reject non-http(s) up front |
| **L-c** (POST body read unbounded) | **bridge hardening** | **Implement** | Even authenticated, a huge body can induce OOM. Cap at the HTTP boundary |
| **L-d** (POST falls through `FAILED` (non-`UNKNOWN_*`) to 202) | **bridge hardening** | **Implement** | HTTP status-mapping defense. `FAILED` must always be 4xx (hardens future code even if unreachable today) |
| **L-a** (only `setRemotes` calls `save()` mid-binding) | bridge-config cosmetic, harmless | **Leave** | `configure()` wraps binding in `BulkChange` and persists once at `bc.commit()`, so on the form path the eager save is already suppressed and atomic. No robustness impact |
| **L-e** (`getExposeLabels()` re-splits each call) | perf nano-optimisation | **Leave** | Perf, not robustness. Negligible at small scale. Not worth the added state |

> **Only L-b / L-c / L-d are implemented.** All are confined to remote transport / HTTP boundary and touch neither lock() logic,
> canonical delegation, nor the transparent-equivalence semantics.

## 3. Detail of the implemented items

### 3-1. L-b: scheme validation of the remote base URL

- Add to `RemoteConnection.validate()`: `url` must start with `http://` or `https://` (non-http(s) → `IllegalArgumentException`).
  `validate()` is called by `setRemotes` (both via the form `configure` and via CasC), so it is the **only pre-persist gate** and thus the real enforcement point.
- Also register `RemoteConnection.DescriptorImpl` with `@Extension` and add `doCheckUrl` (`FormValidation`) for live feedback in the config UI.
- The check is the shared helper `isHttpUrl` (trim + lowercase + prefix test), consistent with `RemoteApiClient.resolve`'s `URI.create`.
- **Out-of-scope concern (retained):** url reachability / FQDN validity / port are not validated (operational, network-dependent). Only the scheme class is rejected.

### 3-2. L-c: POST body size cap

- Introduce a **character cap `MAX_BODY_CHARS` (1 MiB)** in `RemoteApiV1Action.parseJsonBody`. When the cumulative read exceeds it,
  throw `PayloadTooLargeException` (private, `IOException` subclass), which the POST handler maps to **413 `PAYLOAD_TOO_LARGE`**.
- The existing invalid-JSON path (`400 INVALID_JSON`) is kept; catch 413 first to distinguish.
- **Why 1 MiB:** a legitimate lockRequest (short resource/label/extra/reason strings) is typically KBs. 1 MiB is ample headroom.

### 3-3. L-d: generalise POST's FAILED → 4xx mapping

- In POST `/acquire`, when `enqueue` returns `FAILED`: `UNKNOWN_RESOURCE`/`UNKNOWN_LABEL` map to **404** as before, and **any other
  `FAILED` maps to 400** (errorCode as-is, or `ACQUIRE_FAILED`). Closes the path where `FAILED` falls through to a 202 success.
- **Defensive change:** today the only non-`UNKNOWN_*` `FAILED` inside `enqueue` is `MISSING_TARGET`, unreachable due to the boundary
  `MISSING_TARGET` check. So this hardens future code and does not change observed behaviour (existing 404 tests stay green).

## 4. Intentionally retained concerns (documented to prevent re-litigation)

The following are confirmed as **intentionally untouched** in M1F. Recorded so they are not re-opened as "shouldn't we fix this?".

- **M1E-1 [retained, known] ephemeral re-creation via the promotion path's `fromNames(create=true)`.**
  If an admin deletes a named resource while it is QUEUED, the promotion scan re-creates that name as an ephemeral (immediately
  rejected by the exposeLabel filter → unlocked, orphaned) and persists it to `config`. **This stems from canonical name-resolution
  logic itself** (the same code path as local lock()'s on-demand ephemeral feature). Making remote alone `create=false` = adding a
  remote-specific, non-bridge-derived judgement, which violates the "lean on lock()'s existing logic" lens, so it is **not done**. The
  trigger is narrow (exposed, busy, admin delete while QUEUED), it is not fail-open (no incorrect lock is granted), the orphan converges
  to one per name, and it is admin-initiated. Retained as an accepted cost.
  - Only if this lens is ever changed (allowing a remote-specific no-create) would we revisit threading a `create` flag through the
    canonical seam (local `true` / remote `false`, the same additive pattern as `candidateFilter`). Until then, untouched.
- **M1E-2 [retained, not fail-open] resource and label both supplied.** Inherits local lock()'s "prefer label, ignore resource."
  Exposure is enforced by `candidateFilter`, so there is no bypass. No remote-specific rejection is added.
- **M1E-3 [retained, by design] lease ops do not check ownership.** Keeps the existing model (trust boundary = the REMOTE permission).
  Multi-tenant is P1+.
- **L-a / L-e [retained, harmless]** as in §2 (BulkChange makes the eager save harmless / getExposeLabels's split is perf only).

## 5. Scope summary

### In scope (M1F)

| Item | Content |
|---|---|
| L-b | `RemoteConnection` url scheme validation (`validate` enforcement + `doCheckUrl` UI) |
| L-c | POST body cap 1 MiB → 413 `PAYLOAD_TOO_LARGE` |
| L-d | POST `FAILED` (non-`UNKNOWN_*`) → 400 `ACQUIRE_FAILED` (close the 202 fall-through) |
| Docs | Document M1E-1/M1E-2/M1E-3/L-a/L-e as "intentionally retained concerns" (prevent re-litigation) |

### Out of scope (M1F)

| Item | Note |
|---|---|
| Code fix for M1E-1 | lock()-logic-derived. Retained per the lens (§4) |
| Code fix for M1E-2 / M1E-3 | Retained (§4) |
| L-a / L-e | Retained (harmless / perf only) |
| Removing/altering admission | Kept as the remote terminal policy |

## Change log

- 2026-06-14: Initial version. Triaged the M1E-review findings by "leave lock()-logic-derived gaps; implement network-bridge
  hardening." Implemented L-b (url scheme validation) / L-c (body cap 413) / L-d (FAILED→4xx). M1E-1 (promotion-path ephemeral
  re-creation) is **intentionally retained** as canonical `create=true`-derived and documented in §4 (prevent re-litigation).
  M1E-2/M1E-3/L-a/L-e retention rationale recorded too.
