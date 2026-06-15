# M1G 結果（Remote lock - Phase 1 / M1G）

> 設計: `LRR_DESIGN_P1_M1G.md` / 手順: `LRR_IMPLEMENTATION_STEPS_P1_M1G.md`
> ブランチ: `feature/1025-remote-lr-p1-m1g`（ベース `feature/1025-remote-lr-p1` = `de54e90`）

## 概要

**挙動を変えない純リファクタ。** M1F までに既存コアファイルへインライン展開されていた remote 固有ロジックを
`org.jenkins.plugins.lockableresources.remote` パッケージへ凝集し、**既存コアファイルの差分を「最小限の機能追加」に見える**
よう縮小した。機能・タイミング・ログ・直列化跨ぎ挙動は不変。

## 実施した抽出

### ① クライアント状態機械（`LockStepExecution` → remote 層）

- 新規 `RemoteLockSession`（`Serializable`）に acquire→poll→heartbeat→release の状態機械を移動。
  step 統合点（body 起動・onSuccess/onFailure）だけを `Host` インタフェース経由で `LockStepExecution` に残す。
- 補助 helper を新設: `RemoteLockRouting`（peer/delegated ルーティング・接続解決・表示名）、
  `RemoteCredentials`（Basic 認証ヘッダ解決）。
- `LockStepExecution` に残るのは: `start()` の分岐、`runBody`（旧 `proceedRemote`、body 起動）、
  `RemoteCallback`（body 終了時の解放委譲）、`onResume`/`stop` の委譲。

### ② サーバ解決ロジック（`LockableResourcesManager` → remote 層）

- 新規 `RemoteResolver`（stateless コラボレータ）に admission ＋ canonical 解決を移動:
  `validateRemoteSelectors` / `toRemoteStructs` / `availableForRemote` / `remoteLockEnvVars` ほか。
- LRM の **public アクセサのみ**（`getExposeLabels`/`fromName`/`getResources`/`getAvailableResources(Predicate)`）を使用。
  新たな内部公開はなし。`syncResources` 契約は呼び出し元（`RemoteLockManager.enqueue`/`getNextRemoteEntry`）のまま。
- 呼び出し元を `RemoteResolver` に付け替え。

### 意図的にコアへ残したシーム（設計 §2）

`getAvailableResources(Predicate)` オーバーロード／統一キューの `proceedNextContext` 交錯フック＋remote キュー操作／
`LockStep.serverId`／`LockableResource` の remote ロック状態／グローバル設定（Q2 据え置き）。

## 差分縮小（コア5ファイルの追加行 vs master）

| ファイル | M1F | M1G | 移動先 |
|---|---|---|---|
| `LockStepExecution.java` | +553 | **+167** | `RemoteLockSession` ＋ `RemoteLockRouting` ＋ `RemoteCredentials` |
| `LockableResourcesManager.java` | +575 | **+419** | `RemoteResolver` |
| `LockableResource.java` | +44 | +44 | （remote ロック状態・据え置き） |
| `LockStep.java` | +14 | +14 | （serverId・据え置き） |
| `actions/LockableResourcesRootAction.java` | +61 | +61 | （管理 force-release・据え置き） |
| **合計** | **+1208** | **+665** | 新規 `remote/` 4 クラスへ凝集 |

> 「レビュアーが恐れる」状態機械・解決ロジックがコアから消え、新規 remote パッケージに独立追加された形になった。

## 検証

- **mvn フル: 382 件 / 0 失敗 / 1 skip / BUILD SUCCESS**（`dev/reports/20260615082746-mvn-test.log`、worktree、
  コミット済み HEAD `57d2e6d`）。M1F と同一件数＝**テスト不変・挙動保存の裏付け**（新規ユニットは追加せず、既存が回帰網）。
- **E2E `--clean-start`: 20/20 PASS / fail 0**（`dev/reports/20260615084634-e2e-test.md`）。移動コードを実環境で踏む
  S09 delegated-mode・S11 heartbeat-resilience・S13 stale-admin-release・S16 remote-resource-properties・
  S17 remote-unknown-rejected すべて緑。
- 事前にサーバ側ターゲットテスト（`RemoteLockManagerTest` 34＋`RemoteApiV1ActionTest`）を in-place で先行確認（緑）。

## コミット

- plugin `57d2e6d`（m1g ブランチ、単一コミット）。push なし。
- notes は本ステップでコミット（DESIGN/STEPS/RESULT j+e、README 索引/Status、レポート最新ひとつずつ整理）。

## 残課題・次

- M1G はパッケージ化のみ。**M1E-1（昇格経路 ephemeral 再生成）は意図的残置の既知課題のまま**（設計 P1_M1F §4）。
- クライアント UI / read-only ミラー（Phase 2 相当）は別サイクル。
- 初回 PR は no-op コアシームの分割や #1025 合意取りなど、別途検討（[[remote-lock-project-state]] 参照）。
