# lockable-resources-remote-notes

Design notes, specifications, and the development environment for the
**remote lockable resources** feature of the Jenkins
[lockable-resources-plugin](https://github.com/jenkinsci/lockable-resources-plugin)
(epic: [jenkinsci/lockable-resources-plugin#1025](https://github.com/jenkinsci/lockable-resources-plugin/issues/1025)).

Jenkins の [lockable-resources-plugin](https://github.com/jenkinsci/lockable-resources-plugin)
に対する **remote lockable resources** 機能の設計ノート・仕様書・開発環境のリポジトリです。

> This is the **public reference branch** for PR #1055: it carries the design specs, the architecture
> analyses, the E2E test specification, the test environment, and the latest verification report. Internal
> working files (per-cycle implementation steps, result/review logs, early drafts) are kept on the
> development branch only.

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
| [architecture (remote `65d8415`)](docs-e/lockable-resources-architecture-65d8415-e.md) | [remote `65d8415`](docs-j/lockable-resources-architecture-65d8415-j.md) | The submitted PR code: changes vs upstream, design rationale, review material |

### Development documents / 開発ドキュメント（`dev/`）

Per-milestone design specs. **The newest milestone is the current truth**; older milestone documents are
historical snapshots.

| Milestone | Design spec |
|---|---|
| M1 (minimal peer mode) | [e](dev/docs-e/LRR_DESIGN_P1_M1.md) / [j](dev/docs-j/LRR_DESIGN_P1_M1.md) |
| M1A (transparent lockRequest) | [e](dev/docs-e/LRR_DESIGN_P1_M1A.md) / [j](dev/docs-j/LRR_DESIGN_P1_M1A.md) |
| M1B (transparent equivalence) | [e](dev/docs-e/LRR_DESIGN_P1_M1B.md) / [j](dev/docs-j/LRR_DESIGN_P1_M1B.md) |
| M1C (M1B review fixes) | [e](dev/docs-e/LRR_DESIGN_P1_M1C.md) / [j](dev/docs-j/LRR_DESIGN_P1_M1C.md) |
| M1D (true bridging) | [e](dev/docs-e/LRR_DESIGN_P1_M1D.md) / [j](dev/docs-j/LRR_DESIGN_P1_M1D.md) |
| M1E (404 admission + multi-label exposeLabel) | [e](dev/docs-e/LRR_DESIGN_P1_M1E.md) / [j](dev/docs-j/LRR_DESIGN_P1_M1E.md) |
| M1F (M1E review triage: bridge hardening) | [e](dev/docs-e/LRR_DESIGN_P1_M1F.md) / [j](dev/docs-j/LRR_DESIGN_P1_M1F.md) |
| M1G (package the remote layer; no behaviour change) | [e](dev/docs-e/LRR_DESIGN_P1_M1G.md) / [j](dev/docs-j/LRR_DESIGN_P1_M1G.md) |
| **M1H (PR #1055 CI follow-up: security hardening + B2)** | [e](dev/docs-e/LRR_DESIGN_P1_M1H.md) / [j](dev/docs-j/LRR_DESIGN_P1_M1H.md) |

E2E test specification (unified across milestones; each test item is tagged
P1M1 / P1M1A / P1M1B):

- [E2E_TEST_SPECIFICATION](dev/docs-e/E2E_TEST_SPECIFICATION.md) ([j](dev/docs-j/E2E_TEST_SPECIFICATION.md))

### Development environment / 開発環境（`dev/`）

| Path | Content |
|---|---|
| [dev/jenkins-env/](dev/jenkins-env/) | Docker-based 4-controller E2E environment (`start.sh` / `run-e2e.sh` / `scenarios/`). See its [README](dev/jenkins-env/README.md) |
| [dev/run-mvn-verify.sh](dev/run-mvn-verify.sh) | Canonical `mvn clean verify` runner (isolated worktree build; runs all static gates) |
| `dev/reports/` | Latest `mvn verify` log and E2E run report |

---

## Status / 現況

- **Phase 1 / M1H complete** (2026-06-21): PR #1055 CI follow-up. Addressed the 4 Jenkins Security Scan alerts
  (#49–52) on the remote API and re-synced upstream master. #49/#50/#51: `doCheckUrl` / `doCheckForcedServerId`
  now require POST (+ ADMINISTER on `doCheckUrl`) with `checkMethod="post"` on the form fields. #52 = **B2**:
  `GET /acquire/{lockId}` is now a pure read — the poll-keepalive (`touchPoll`) is removed and QUEUED liveness
  is folded onto the unified queue timeout (`RemoteQueueEntry` deadline). Re-synced onto `upstream/master`
  `8f03dbf` (#1056 crowdin, #1057 BOM bump). Verified: `mvn verify` BUILD SUCCESS 383/0/1skip (all gates ok),
  E2E 20/20. See LRR_DESIGN_P1_M1H.
- **Phase 1 / M1G complete** (2026-06-15): behaviour-preserving refactor that coheres the remote feature into
  the `…lockableresources.remote` package so the diff to existing core files reads as a minimal feature
  addition. The client state machine (`RemoteLockSession` + `RemoteLockRouting` + `RemoteCredentials`) was
  extracted from `LockStepExecution`, and the server admission/resolution (`RemoteResolver`) from
  `LockableResourcesManager`; core-file additions dropped +1208 → +665. No behaviour change. See LRR_DESIGN_P1_M1G.
- **Phase 1 / M1A–M1F** (2026-06-12 .. 2026-06-14): transparent-equivalence bridging built up over the cycles —
  the server delegates to `lock()`'s canonical resolution (M1D), unknown/unexposed acquires get a uniform 404
  with no ephemeral creation and `exposeLabel` became a whitespace-separated OR set (M1E), and network-bridge
  hardening (non-http(s) rejection, 1 MiB body cap, terminal-FAILED→4xx) was added (M1F). See the per-milestone
  design specs above.

> Phase 2 (client-side UI / read-only mirror of remote resources) is not started; see issue #1025.
</content>
