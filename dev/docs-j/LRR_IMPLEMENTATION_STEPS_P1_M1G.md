# M1G Implementation Steps (Remote lock - Phase 1 / M1G)

このファイルは M1G の進捗トラッカーです（設計は `LRR_DESIGN_P1_M1G.md`）。
**挙動を変えない純リファクタ** — remote 固有ロジックを `remote` パッケージへ凝集し、既存コアの差分を最小化。
回帰網 = 既存 mvn 382 ＋ E2E 20/20 グリーン維持（新規 E2E は追加しない）。

---

## ステップ一覧

### 0. 事前準備

- [x] m1g ブランチ作成（squash ベース `de54e90` = `feature/1025-remote-lr-p1`）= `feature/1025-remote-lr-p1-m1g`
- [x] 移動対象の実コード精読（`LockStepExecution` 状態機械 / LRM 解決・キュー / `RemoteLockManager.enqueue` / `RemoteQueueEntry`）
- [x] `LRR_DESIGN_P1_M1G` / 本書（j）整備

### Step 1: 抽出② サーバ解決ロジック → `remote.RemoteResolver`（先に・低リスク）

- [x] `RemoteResolver`（remote パッケージ）新設。LRM 参照を保持し公開アクセサのみ使用。
  - [x] 移動: `validateRemoteSelectors` / `validateSelector` / `isExposed` / `hasExposedCandidate` / `toRemoteStructs` /
    `addRemoteStruct` / `availableForRemote` / `remoteLockEnvVars` / `parseSelectStrategy`
- [x] 呼び出し元付け替え: `RemoteLockManager.enqueue` / `LRM.getNextRemoteEntry` / `RemoteQueueEntry.onAcquired`
- [x] LRM から上記メソッドを削除（シーム `getAvailableResources(Predicate)`・キューブリッジ・設定は残す）
- [x] test-compile グリーン
- [ ] 配置固定: 既存 `RemoteLockManagerTest` ＋ `RemoteApiV1ActionTest` が回帰カバー（ターゲット実行グリーン。専用テストは追加せず）

### Step 2: 抽出① クライアント状態機械 → `remote.RemoteLockSession` ＋ helpers

- [x] `RemoteLockRouting`（static）: `isRemoteRequest` / `effectiveServerId` / `findConnection` / `displayTarget`
- [x] `RemoteCredentials`（static）: `basicAuthHeader(remote, run)`
- [x] `RemoteLockSession`（Serializable）＋ `Host` インタフェース: acquire/poll/heartbeat/release 状態機械を移動
- [x] `LockStepExecution` を薄い統合シムに: `start()` 分岐 / `runBody`（旧 proceedRemote）/ `RemoteCallback` / `onResume`・`stop` 委譲
- [x] 共有 static `buildLockEnvVars` は `LockStepExecution` 据え置き
- [x] test-compile グリーン

### Step 3: 仕上げ・整合

- [x] `LockableResourcesRootAction.doReleaseRemoteLock` は据え置き（主目的外）
- [x] import 整理・未使用除去
- [x] 差分 before/after を記録: コア5ファイル **+1208 → +665**。状態機械＋解決は新規 `remote/` 4 クラスへ

### Step 4: ビルド・E2E・コミット

- [ ] `dev/stabilize-build.sh`（worktree、コミット済み HEAD `57d2e6d`）で mvn フル成功（382 / 0 失敗）
- [ ] `dev/jenkins-env/run-e2e.sh --clean-start` 全 20 件 PASS（特に S09/S11/S13/S16/S17）
- [ ] docs-e 同期（DESIGN/STEPS/RESULT）、README 索引/Status 更新
- [ ] plugin commit（Co-Authored-By なし）、notes commit。push しない

---

## 変更ファイル一覧（plugin・予定）

| ファイル | 変更 |
|---|---|
| `remote/RemoteResolver.java` | 新規（LRM から解決ロジック移動） |
| `remote/RemoteLockSession.java` | 新規（LockStepExecution から状態機械移動） |
| `remote/RemoteLockRouting.java` | 新規（ルーティング helper） |
| `remote/RemoteCredentials.java` | 新規（認証ヘッダ helper） |
| `LockStepExecution.java` | 状態機械を撤去し Host シムへ（+553 → 目標 +80〜100） |
| `LockableResourcesManager.java` | 解決ロジック撤去（+575 → 目標 +430）。シーム・キュー・設定は残置 |
| `remote/RemoteLockManager.java` / `remote/RemoteQueueEntry.java` | 呼び出し先を RemoteResolver に付け替え |
| `remote/RemoteResolverTest.java` ほか | 新クラスの配置固定ユニット |

## E2E 方針

挙動不変のため**新規 E2E なし**。既存 20/20 の回帰維持で十分（状態機械・解決・キューの移動は既存シナリオが実環境で踏む）。
