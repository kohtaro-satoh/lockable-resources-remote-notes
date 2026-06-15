# lockable-resources-remote-notes

Design notes, specifications, and the development environment for the
**remote lockable resources** feature of the Jenkins
[lockable-resources-plugin](https://github.com/jenkinsci/lockable-resources-plugin)
(epic: [jenkinsci/lockable-resources-plugin#1025](https://github.com/jenkinsci/lockable-resources-plugin/issues/1025)).

Jenkins の [lockable-resources-plugin](https://github.com/jenkinsci/lockable-resources-plugin)
に対する **remote lockable resources** 機能の設計ノート・仕様書・開発環境のリポジトリです。

---

## Document Index / ドキュメント索引

Documents come in English (`docs-e` / `-e` suffix) and Japanese (`docs-j` / `-j`
suffix) pairs. The Japanese versions are the working originals.

### Concept documents / 構想ドキュメント（リポジトリ直下）

| English | 日本語 | Content |
|---|---|---|
| [remote-lock-background-e](docs-e/remote-lock-background-e.md) | [背景](docs-j/remote-lock-background-j.md) | Why: the problem and motivation |
| [remote-lock-usecase-e](docs-e/remote-lock-usecase-e.md) | [ユースケース](docs-j/remote-lock-usecase-j.md) | For whom: UC-1 (HW boards), UC-2 (licenses) |
| [remote-lock-design-notes-e](docs-e/remote-lock-design-notes-e.md) | [設計ノート](docs-j/remote-lock-design-notes-j.md) | Decision log with rationale |
| [lockable-resources-architecture-e](docs-e/lockable-resources-architecture-e.md) | [アーキテクチャ](docs-j/lockable-resources-architecture-j.md) | Upstream plugin architecture study |

### Development documents / 開発ドキュメント（`dev/`）

Per-milestone specs and progress trackers. **The newest milestone is the current
truth**; older milestone documents are historical snapshots (with banners where
M1B superseded them).

| Milestone | Design spec | Implementation steps |
|---|---|---|
| M1 (minimal peer mode) | [e](dev/docs-e/LRR_DESIGN_P1_M1.md) / [j](dev/docs-j/LRR_DESIGN_P1_M1.md) | [e](dev/docs-e/LRR_IMPLEMENTATION_STEPS_P1_M1.md) / [j](dev/docs-j/LRR_IMPLEMENTATION_STEPS_P1_M1.md) |
| M1A (transparent lockRequest) | [e](dev/docs-e/LRR_DESIGN_P1_M1A.md) / [j](dev/docs-j/LRR_DESIGN_P1_M1A.md) | [e](dev/docs-e/LRR_IMPLEMENTATION_STEPS_P1_M1A.md) / [j](dev/docs-j/LRR_IMPLEMENTATION_STEPS_P1_M1A.md) |
| M1B (transparent equivalence) | [e](dev/docs-e/LRR_DESIGN_P1_M1B.md) / [j](dev/docs-j/LRR_DESIGN_P1_M1B.md) | [e](dev/docs-e/LRR_IMPLEMENTATION_STEPS_P1_M1B.md) / [j](dev/docs-j/LRR_IMPLEMENTATION_STEPS_P1_M1B.md) |
| M1C (M1B review fixes) | [e](dev/docs-e/LRR_DESIGN_P1_M1C.md) / [j](dev/docs-j/LRR_DESIGN_P1_M1C.md) | [e](dev/docs-e/LRR_IMPLEMENTATION_STEPS_P1_M1C.md) / [j](dev/docs-j/LRR_IMPLEMENTATION_STEPS_P1_M1C.md) |
| M1D (true bridging) | [e](dev/docs-e/LRR_DESIGN_P1_M1D.md) / [j](dev/docs-j/LRR_DESIGN_P1_M1D.md) | [e](dev/docs-e/LRR_IMPLEMENTATION_STEPS_P1_M1D.md) / [j](dev/docs-j/LRR_IMPLEMENTATION_STEPS_P1_M1D.md) |
| M1E (404 admission + multi-label exposeLabel) | [e](dev/docs-e/LRR_DESIGN_P1_M1E.md) / [j](dev/docs-j/LRR_DESIGN_P1_M1E.md) | [e](dev/docs-e/LRR_IMPLEMENTATION_STEPS_P1_M1E.md) / [j](dev/docs-j/LRR_IMPLEMENTATION_STEPS_P1_M1E.md) |
| M1F (M1E review triage: bridge hardening) | [e](dev/docs-e/LRR_DESIGN_P1_M1F.md) / [j](dev/docs-j/LRR_DESIGN_P1_M1F.md) | [e](dev/docs-e/LRR_IMPLEMENTATION_STEPS_P1_M1F.md) / [j](dev/docs-j/LRR_IMPLEMENTATION_STEPS_P1_M1F.md) |
| **M1G (package the remote layer; no behaviour change)** | [e](dev/docs-e/LRR_DESIGN_P1_M1G.md) / [j](dev/docs-j/LRR_DESIGN_P1_M1G.md) | [e](dev/docs-e/LRR_IMPLEMENTATION_STEPS_P1_M1G.md) / [j](dev/docs-j/LRR_IMPLEMENTATION_STEPS_P1_M1G.md) |

Per-cycle result summaries: [LRR_RESULT_P1_M1C](dev/docs-e/LRR_RESULT_P1_M1C.md) ([j](dev/docs-j/LRR_RESULT_P1_M1C.md)),
[LRR_RESULT_P1_M1D](dev/docs-e/LRR_RESULT_P1_M1D.md) ([j](dev/docs-j/LRR_RESULT_P1_M1D.md)),
[LRR_RESULT_P1_M1E](dev/docs-e/LRR_RESULT_P1_M1E.md) ([j](dev/docs-j/LRR_RESULT_P1_M1E.md)),
[LRR_RESULT_P1_M1F](dev/docs-e/LRR_RESULT_P1_M1F.md) ([j](dev/docs-j/LRR_RESULT_P1_M1F.md)),
[LRR_RESULT_P1_M1G](dev/docs-e/LRR_RESULT_P1_M1G.md) ([j](dev/docs-j/LRR_RESULT_P1_M1G.md)).

E2E test specification (unified across milestones; each test item is tagged
P1M1 / P1M1A / P1M1B):

- [E2E_TEST_SPECIFICATION](dev/docs-e/E2E_TEST_SPECIFICATION.md) ([j](dev/docs-j/E2E_TEST_SPECIFICATION.md))

Reviews / レビュー:

- [LRR_REVIEW_P1_M1A](dev/docs-e/LRR_REVIEW_P1_M1A.md) ([j](dev/docs-j/LRR_REVIEW_P1_M1A.md)) —
  full review at M1A completion; the findings drove the M1B redesign
- [LRR_REVIEW_P1_M1B](dev/docs-e/LRR_REVIEW_P1_M1B.md) ([j](dev/docs-j/LRR_REVIEW_P1_M1B.md)) —
  full review at M1B completion; findings C-1 / C-2 drive the M1C cycle
- [LRR_REVIEW_P1_M1D](dev/docs-e/LRR_REVIEW_P1_M1D.md) ([j](dev/docs-j/LRR_REVIEW_P1_M1D.md)) —
  full review at M1D completion; findings H-1 / M-2 drive the M1E cycle
- [LRR_REVIEW_P1_M1E](dev/docs-e/LRR_REVIEW_P1_M1E.md) ([j](dev/docs-j/LRR_REVIEW_P1_M1E.md)) —
  full diff review (master..m1e); H-1 / M-2 resolved on the main path; one residual M1E-1
  (no promotion-path admission re-check → ephemeral re-creation of a deleted resource).
  Triaged into the M1F cycle (bridge hardening L-b/L-c/L-d implemented; M1E-1 intentionally retained)
- [LRR_REVIEW_P1_M1F](dev/docs-e/LRR_REVIEW_P1_M1F.md) ([j](dev/docs-j/LRR_REVIEW_P1_M1F.md)) —
  review at M1F completion (m1e..m1f delta); the three bridge hardenings honor the lens with no new
  fail-open and no canonical contamination. PR-quality within scope; findings Low/nit only
  (F-1 isHttpUrl/resolve whitespace asymmetry, F-2 L-d empty errorCode). M1E-1 re-confirmed as a
  known intentionally-deferred item

Early design drafts (Japanese only, historical): [dev/docs-j/design-00/](dev/docs-j/design-00/)

### Development environment / 開発環境（`dev/`）

| Path | Content |
|---|---|
| [dev/jenkins-env/](dev/jenkins-env/) | Docker-based 4-controller E2E environment (`start.sh` / `run-e2e.sh` / `scenarios/`). See its [README](dev/jenkins-env/README.md) |
| [dev/stabilize-build.sh](dev/stabilize-build.sh) | Stable `mvn test` runner (isolated worktree build; avoids VS Code jdt.ls conflicts) |
| `dev/reports/` | Saved `mvn test` logs and E2E run reports |

---

## Status / 現況

- **Phase 1 / M1G complete** (2026-06-15): behaviour-preserving refactor that coheres the remote
  feature into the `…lockableresources.remote` package so the diff to existing core files reads as a
  minimal feature addition. Extracted the client state machine (`RemoteLockSession` + `RemoteLockRouting`
  + `RemoteCredentials`) out of `LockStepExecution`, and the server admission/resolution
  (`RemoteResolver`) out of `LockableResourcesManager`. Core-file additions dropped **+1208 → +665**;
  the unified-queue hook, the `getAvailableResources(Predicate)` seam, the public DSL/resource state and
  global config are kept in core as unavoidable seams. mvn 382/0 (unchanged count), E2E 20/20. No
  behaviour change. See LRR_DESIGN_P1_M1G / LRR_RESULT_P1_M1G. plugin `57d2e6d` (branch
  `feature/1025-remote-lr-p1-m1g`, base `de54e90`).
- **Phase 1 / M1F complete** (2026-06-14): M1E-review triage by the lens "lean on lock()'s
  existing logic; only add network-bridge-derived judgement." Implemented bridge hardening
  only — L-b (reject non-http(s) remote URLs), L-c (cap POST body at 1 MiB → 413), L-d (map any
  terminal FAILED to 4xx, never 202). M1E-1 (promotion-path ephemeral re-creation, canonical
  `create=true`-derived) is intentionally retained and documented (design §4); M1E-2/M1E-3/L-a/L-e
  retained too. No lock()-semantic change. See LRR_DESIGN_P1_M1F.
- Phase 1 / M1E complete (2026-06-14): M1D review fixes + intentional simplification.
  Unknown/unexposed acquires are rejected up front with a uniform 404 (admission) and the
  server no longer creates ephemeral resources for them (H-1 fix); the exposure
  `ExtensionPoint` is removed in favour of a single `exposeLabel` filter, now a
  whitespace-separated set of labels (OR exposure, backward compatible). "exposed but busy"
  still QUEUEs. 378 unit tests; E2E 20/20 PASS (S17 added). See LRR_RESULT_P1_M1E.
- Phase 1 / M1D complete (2026-06-13): "true bridging" — the server delegates
  to lock()'s canonical resolution + shares env-var generation, so per-feature
  residue (property env vars, ephemeral, resourceSelectStrategy) is eliminated at
  once. 375 unit tests; E2E 19/19 PASS (S16 added). See LRR_RESULT_P1_M1D.
  (Note: M1D's `RemoteResourceExposurePolicy` ExtensionPoint was removed in M1E.)
- Phase 1 / M1C complete (2026-06-12): resolved the M1B-completion review findings
  (C-1/C-2/M-2/M-3; M-1 deferred) plus follow-up F-1 (label unspecified quantity =
  all). 375 unit tests; E2E 18/18 PASS (S14/S15). See LRR_RESULT_P1_M1C.
- Phase 1 / M1B complete, including follow-ups F-1–F-3 (2026-06-12): all 8 steps
  + 3 follow-up items, 360 unit tests, 16/16 E2E.
- Plugin branches (kept local; push/PR planned after final polishing):
  - `feature/1025-remote-lr-p1-m1g` — M1G work (current, HEAD `57d2e6d`); behaviour-preserving
    package refactor, branched from the squashed `feature/1025-remote-lr-p1` (`de54e90`).
  - `feature/1025-remote-lr-p1` — single-commit squash of the M1A–M1F series onto master, for review/PR.
  - `feature/1025-remote-lockable-resources-p1-m1f` — M1F work; branched from m1e.
  - `feature/1025-remote-lockable-resources-p1-m1e` — M1E work (HEAD `5d956de`); branched from m1d.
  - `feature/1025-remote-lockable-resources-p1-m1d` — M1D work (HEAD `819daa0`); branched from m1c.
  - `feature/1025-remote-lockable-resources-p1-m1c` — M1C work (HEAD `5296b50`); branched from m1b.
  - `feature/1025-remote-lockable-resources-p1-m1b` — M1B work (HEAD `02fcfae`)
  - `feature/1025-remote-lockable-resources-p1-m1a` — M1A only (HEAD `c782c28`); m1b is branched from here.
