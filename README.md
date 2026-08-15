# lockable-resources-remote-notes

Design notes, specifications, and the development environment for the
**remote lockable resources** feature of the Jenkins
[lockable-resources-plugin](https://github.com/jenkinsci/lockable-resources-plugin)
(epic: [jenkinsci/lockable-resources-plugin#1025](https://github.com/jenkinsci/lockable-resources-plugin/issues/1025)).

Jenkins の [lockable-resources-plugin](https://github.com/jenkinsci/lockable-resources-plugin)
に対する **remote lockable resources** 機能の設計ノート・仕様書・開発環境のリポジトリです。

> This is the **public reference branch** for PR #1077: it carries the design specs, the architecture
> analyses, the test specifications, the test environment, and the verification reports for the
> submitted commit. Internal working files (per-cycle implementation steps, result/review logs, early
> drafts) are kept on the development branch only.

---

## Document Index / ドキュメント索引

Documents come in English (`docs-e` / `-e` suffix) and Japanese (`docs-j` / `-j`
suffix) pairs. The Japanese versions are the working originals.

### Concept & architecture documents / 構想・アーキテクチャ（リポジトリ直下）

| English | 日本語 | Content |
|---|---|---|
| [remote-lock-background-e](docs-e/remote-lock-background-e.md) | [背景](docs-j/remote-lock-background-j.md) | Why: the problem and motivation |
| [remote-lock-usecase-e](docs-e/remote-lock-usecase-e.md) | [ユースケース](docs-j/remote-lock-usecase-j.md) | For whom: UC-1 (HW boards), UC-2 (licenses) |
| [remote-lock-design-notes-e](docs-e/remote-lock-design-notes-e.md) | [設計ノート](docs-j/remote-lock-design-notes-j.md) | Decision log with rationale |
| [lockable-resources-architecture-e](docs-e/lockable-resources-architecture-e.md) | [アーキテクチャ](docs-j/lockable-resources-architecture-j.md) | Upstream plugin architecture study |
| [architecture (baseline `8f03dbf`)](docs-e/lockable-resources-architecture-8f03dbf-e.md) | [baseline `8f03dbf`](docs-j/lockable-resources-architecture-8f03dbf-j.md) | Upstream master pinned as the diff baseline |
| [architecture (remote `65d8415`)](docs-e/lockable-resources-architecture-65d8415-e.md) | [remote `65d8415`](docs-j/lockable-resources-architecture-65d8415-j.md) | PR #1055 code: changes vs upstream, design rationale, review material |

### Design specifications / 設計書（`dev/docs-*/`）

Per-milestone design specs. **The newest milestone is the current truth**; older milestone documents
are historical snapshots.

PR #1077 (M2 + M3):

| Milestone | Design spec |
|---|---|
| **M2 + M3 (client-side view, discovery, operations)** | [j](dev/docs-j/ph1-ms2/design_01.md) — Japanese only; the English mirror follows once its §10 open questions are settled |

PR #1055 (M1 .. M1J), for reference:

| Milestone | Design spec |
|---|---|
| M1 (minimal peer mode) | [e](dev/docs-e/ph1-ms1/LRR_DESIGN_P1_M1.md) / [j](dev/docs-j/ph1-ms1/LRR_DESIGN_P1_M1.md) |
| M1A (transparent lockRequest) | [e](dev/docs-e/ph1-ms1/LRR_DESIGN_P1_M1A.md) / [j](dev/docs-j/ph1-ms1/LRR_DESIGN_P1_M1A.md) |
| M1B (transparent equivalence) | [e](dev/docs-e/ph1-ms1/LRR_DESIGN_P1_M1B.md) / [j](dev/docs-j/ph1-ms1/LRR_DESIGN_P1_M1B.md) |
| M1C (M1B review fixes) | [e](dev/docs-e/ph1-ms1/LRR_DESIGN_P1_M1C.md) / [j](dev/docs-j/ph1-ms1/LRR_DESIGN_P1_M1C.md) |
| M1D (true bridging) | [e](dev/docs-e/ph1-ms1/LRR_DESIGN_P1_M1D.md) / [j](dev/docs-j/ph1-ms1/LRR_DESIGN_P1_M1D.md) |
| M1E (404 admission + multi-label exposeLabel) | [e](dev/docs-e/ph1-ms1/LRR_DESIGN_P1_M1E.md) / [j](dev/docs-j/ph1-ms1/LRR_DESIGN_P1_M1E.md) |
| M1F (M1E review triage: bridge hardening) | [e](dev/docs-e/ph1-ms1/LRR_DESIGN_P1_M1F.md) / [j](dev/docs-j/ph1-ms1/LRR_DESIGN_P1_M1F.md) |
| M1G (package the remote layer; no behaviour change) | [e](dev/docs-e/ph1-ms1/LRR_DESIGN_P1_M1G.md) / [j](dev/docs-j/ph1-ms1/LRR_DESIGN_P1_M1G.md) |
| M1H (PR #1055 CI follow-up: security hardening + B2) | [e](dev/docs-e/ph1-ms1/LRR_DESIGN_P1_M1H.md) / [j](dev/docs-j/ph1-ms1/LRR_DESIGN_P1_M1H.md) |
| M1I (queued-expiry-poll-404 regression fix; found by load testing) | [e](dev/docs-e/ph1-ms1/LRR_DESIGN_P1_M1I.md) / [j](dev/docs-j/ph1-ms1/LRR_DESIGN_P1_M1I.md) |
| M1J (remote config help links 404 fix; found in PR review) | [e](dev/docs-e/ph1-ms1/LRR_DESIGN_P1_M1J.md) / [j](dev/docs-j/ph1-ms1/LRR_DESIGN_P1_M1J.md) |

### Test specifications / テスト仕様

- [E2E_TEST_SPECIFICATION](dev/docs-e/E2E_TEST_SPECIFICATION.md) ([j](dev/docs-j/E2E_TEST_SPECIFICATION.md)) —
  32 scenarios, each tagged with the axis it covers (function / data / time / scale)
- [LOAD_TEST_SPECIFICATION](dev/docs-e/LOAD_TEST_SPECIFICATION.md) ([j](dev/docs-j/LOAD_TEST_SPECIFICATION.md)) —
  a separate suite driving the remote lock at production scale; this is how the M1I regression was found
- [BOUNDARY_COVERAGE_ANALYSIS](dev/docs-j/BOUNDARY_COVERAGE_ANALYSIS.md) (Japanese) — what the E2E suite
  covers on the data / time / scale axes, what it does not, and the findings that came out of closing
  the gaps. This is how the A6 defect (a queued remote request never timing out on its own deadline)
  was found

---

## Verification / 検証結果

All four suites on the submitted commit `bdca858`:

| Suite | Result |
|---|---|
| `mvn verify` | [20260814192837-mvn-verify.md](dev/reports/20260814192837-mvn-verify.md) — BUILD SUCCESS, 463 run / 0 failures / 1 skip, all gates clean |
| E2E | [20260814195206-e2e-test.md](dev/reports/20260814195206-e2e-test.md) — 32/32 PASS (20 function / 4 data / 6 time / 2 scale) |
| Load `stress` | [20260814122345-load-test-stress.md](dev/reports/20260814122345-load-test-stress.md) — 190 SUCCESS / 10 FAILURE, every failure a clean `LOCK_WAIT_TIMEOUT`, overlaps 0, HUNG 0 |
| Load `timeout-race` | [20260814123643-load-test-timeout-race.md](dev/reports/20260814123643-load-test-timeout-race.md) — 92 SUCCESS / 108 FAILURE, all 108 a clean `LOCK_WAIT_TIMEOUT`, overlaps 0, HUNG 0 |

The two load presets ask different questions. `stress` is about contention, throughput and the shape of
the queue; `timeout-race` puts the deadlines *inside* the window rather than beyond it, so the code that
runs when an allocate timeout expires is exercised in bulk rather than a handful of times. Read its
failure count against that intent: timeouts there are the point, not a regression.

Mutual exclusion is judged from the servers' own audit trail, not from what the clients believed they
held. A build logs its acquisition after taking the lock and its release before giving it up, so its
interval lies inside the true one — an overlap seen from the clients is real, but a real one can escape
them. The reports carry both counts and say which one the verdict came from.

### UI capture / 画面キャプチャ

- [20260814114953-ui-capture.md](dev/reports/20260814114953-ui-capture.md) — the same states photographed
  on upstream and on this branch, because a tab, a badge and a banner are not reviewable from a diff.
  The hand-taken tour linked from the PR is in [dev/pr-assets/ph1-ms2-ui/](dev/pr-assets/ph1-ms2-ui/)

---

## Development environment / 開発環境（`dev/`）

| Path | Content |
|---|---|
| [dev/jenkins-env/](dev/jenkins-env/) | Docker-based 4-controller E2E environment (`start.sh` / `run-e2e.sh` / `run-load.sh` / `scenarios/`). See its [README](dev/jenkins-env/README.md) |
| [dev/jenkins-env/capture/](dev/jenkins-env/capture/) | Scripted browser that photographs the UI; runs both plugin versions through the same script |
| [dev/run-mvn-verify.sh](dev/run-mvn-verify.sh) | Canonical `mvn clean verify` runner (isolated worktree build; runs all static gates) |
| `dev/reports/` | Latest report of each kind for the submitted commit |

---

## Status / 現況

- **PR [#1077](https://github.com/jenkinsci/lockable-resources-plugin/pull/1077) submitted** (2026-08-14):
  closes the required items of #1025. 26 commits on `upstream/master` `148d8eb` — seven fixes to the
  remote path (A1–A7), the queue and validation semantics `lock()` already had (B1–B2), the maintenance
  switch, discovery endpoint, client-side disable and audit trail (B3–B7), the lockable resources page's
  view of remote locks (C1–C4), test coverage (T1–T6; remote-related 78.7% line / 63.3% branch →
  88.4% / 72.5%), and documentation (D1–D2).
- **PR [#1055](https://github.com/jenkinsci/lockable-resources-plugin/pull/1055) merged** (2026-08-04):
  the bridge itself — a Pipeline `lock()` acquiring a resource owned by a different controller over a
  versioned REST API, with the same `lock()` semantics as a local lock. #1077 is the follow-up it named.

> Further phases of #1025 are not planned work. They will be raised as new issues if there is demand.
