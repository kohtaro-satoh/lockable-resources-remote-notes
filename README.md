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
| **M1B (transparent equivalence)** | [e](dev/docs-e/LRR_DESIGN_P1_M1B.md) / [j](dev/docs-j/LRR_DESIGN_P1_M1B.md) | [e](dev/docs-e/LRR_IMPLEMENTATION_STEPS_P1_M1B.md) / [j](dev/docs-j/LRR_IMPLEMENTATION_STEPS_P1_M1B.md) |

E2E test specification (unified across milestones; each test item is tagged
P1M1 / P1M1A / P1M1B):

- [E2E_TEST_SPECIFICATION](dev/docs-e/E2E_TEST_SPECIFICATION.md) ([j](dev/docs-j/E2E_TEST_SPECIFICATION.md))

Reviews / レビュー:

- [LRR_REVIEW_P1_M1A](dev/docs-e/LRR_REVIEW_P1_M1A.md) ([j](dev/docs-j/LRR_REVIEW_P1_M1A.md)) —
  full review at M1A completion; the findings drove the M1B redesign
- [LRR_REVIEW_P1_M1B](dev/docs-e/LRR_REVIEW_P1_M1B.md) ([j](dev/docs-j/LRR_REVIEW_P1_M1B.md)) —
  full review at M1B completion; findings C-1 / C-2 drive the M1C cycle

Early design drafts (Japanese only, historical): [dev/docs-j/design-00/](dev/docs-j/design-00/)

### Development environment / 開発環境（`dev/`）

| Path | Content |
|---|---|
| [dev/jenkins-env/](dev/jenkins-env/) | Docker-based 4-controller E2E environment (`start.sh` / `run-e2e.sh` / `scenarios/`). See its [README](dev/jenkins-env/README.md) |
| [dev/stabilize-build.sh](dev/stabilize-build.sh) | Stable `mvn test` runner (isolated worktree build; avoids VS Code jdt.ls conflicts) |
| `dev/reports/` | Saved `mvn test` logs and E2E run reports |

---

## Status / 現況

- **Phase 1 / M1B complete, including follow-ups F-1–F-3** (2026-06-12):
  all 8 steps + 3 follow-up items implemented,
  360 unit tests passing, 16/16 E2E scenarios passing.
- Plugin branches (kept local; push/PR planned after final polishing):
  - `feature/1025-remote-lockable-resources-p1-m1b` — M1B work (current, HEAD `02fcfae`)
  - `feature/1025-remote-lockable-resources-p1-m1a` — M1A only (HEAD `c782c28`); m1b is branched from here.
