# Remote Lockable Resources 仕様書（Phase 1 / M1G）

> **出典:** [jenkinsci/lockable-resources-plugin #1025](https://github.com/jenkinsci/lockable-resources-plugin/issues/1025)
> **前提文書:** `LRR_DESIGN_P1_M1F.md`（M1F 仕様）/ `LRR_REVIEW_P1_M1F.md`（M1F 完了レビュー）
> **対象スコープ:** Phase 1 M1G（**挙動を変えない純リファクタ** — remote 機能を `remote` パッケージへ凝集し、
>   既存コアファイルへの改変がレビュアー目線で「最小限の機能追加」に見えるようにする）

---

## 1. M1G の位置づけ — 「コア改変を最小に見せる」ためのパッケージ化

M1G は機能追加でも仕様変更でもない。**外部から観測可能な挙動を一切変えず**、M1F までに既存コアファイル
（`LockStepExecution` / `LockableResourcesManager` ほか）へインライン展開された remote 固有ロジックを、
`org.jenkins.plugins.lockableresources.remote` パッケージへ移動する整理サイクルである。

> **動機（2026-06-15 ユーザー確定）:** 初回 PR を upstream に出す際、レビュアーから見て
> 「既存コードは最小限の差分で、remote 機能は独立パッケージに足されただけ」に見える状態にする。
> master..M1F の全体差分のうち **約 1,208 行が既存コア5ファイルに織り込まれている**（[[LRR_REVIEW_P1_M1F]] 後の分析）。
> その大半は「コアファイルの中に書かれているだけで、コア内部に依存しない remote ロジック」であり、`remote` 層へ出せる。

### 不変条件（最重要）

- **挙動完全保存。** ロック意味論・透過等価・公開ポリシー・HTTP API・タイミング・ログ・直列化（serialize）跨ぎの
  onResume/stop 挙動を変えない。すべて「メソッドの引っ越し」と「呼び出し先の付け替え」に限る。ロジックは書き換えない。
- **回帰網は既存テスト。** mvn 382 件 ＋ E2E 20/20 がそのまま回帰検証。M1G で**新規 E2E シナリオは追加しない**
  （挙動を変えないため）。移動した新クラスには配置を固定する**ユニットテストを必要に応じ追加**するが、既存テストの
  グリーン維持が合否。
- **スコープ確定（2026-06-15 ユーザー確定）:** 両抽出（① クライアント状態機械 / ② サーバ解決ロジック）を **M1G 1 サイクル**で実施。
  グローバル設定（`remoteApiEnabled`/`exposeLabel`/`clientId`/`forcedServerId`/`remotes`）は **LRM に据え置き**（ロジックのみ移動）。

---

## 2. コアに残す「不可避シーム」（移動しない）と理由

以下は remote 機能のためにコアへ入れざるを得ない最小の接点で、M1G でも**意図的にコアに残す**。

| コアの接点 | 規模 | 残す理由 |
|---|---|---|
| `LRM.getAvailableResources(..., Predicate<LockableResource> candidateFilter)` オーバーロード（旧シグネチャは `r -> true` で委譲） | ~5 行 | canonical 委譲の本丸。「remote が local lock() に乗る」唯一のシーム。local 挙動は不変 |
| `LRM.proceedNextContext` の local/remote 交錯フック ＋ remote キュー操作（`queueRemote`/`unqueueRemote`/`lockForRemote`/`unlockRemoteResources`/`getNextRemoteEntry`/`proceedRemoteEntry`/`remoteQueueEntries`） | ~120 行 | **統一優先度キュー**（remote が local と同じドレインで公平競合）の正当なコア統合。別キューに分けると統一公平性を失う。資源状態（`resources`）を直接ミューテートするため LRM に属するのが正しい |
| `LockStep.serverId` 引数 | +14 | 公開 DSL 表面。不可避 |
| `LockableResource.remoteLockedBy` / アクセサ | +44 | リソースの remote ロック状態。ダッシュボード表示と local ロック除外に必要 |
| グローバル設定フィールド＋getter/setter/doCheck（LRM） | ~180 | LRM は既に `GlobalConfiguration`。設定保持は idiomatic。getter/setter はレビュアーが恐れる差分ではない（Q2 据え置き） |

> これら以外の remote ロジック（クライアント状態機械・サーバ解決）は**コアファイルに同居しているだけ**であり、§3/§4 で `remote` 層へ出す。

---

## 3. 抽出① クライアント状態機械 → `remote.RemoteLockSession`（`LockStepExecution` から）

### 現状（M1F）

`LockStepExecution`（+553 行）に、リモート取得の acquire→poll→heartbeat→release 状態機械が丸ごとインライン:
フィールド（`remotePollTask`/`remoteHeartbeatTask`/`remoteServerId`/`remoteLockId`/`remoteLastState`/`remoteBodyStarted`/
`consecutivePollFailures`/`remoteCompletionSignaled`/`MAX_CONSECUTIVE_POLL_FAILURES`）＋メソッド（`startRemoteFlow`/
`startRemotePolling`/`pollRemoteStatus`/`startRemoteHeartbeat`/`releaseRemoteLockBestEffort`/`cancelRemotePollTask`/
`cancelRemoteHeartbeatTask`/`finishRemoteFailure`/`proceedRemote`/`buildRemoteFailureMessage`/`resolveRemoteDisplayTarget`/
`findRemoteConnectionOrFail`/`resolveAuthorizationHeader`/`resolveEffectiveServerId`/`isRemoteLockRequest`/`RemoteCallback`）。

### 移動先と分担

| 新クラス（remote パッケージ） | 内容 |
|---|---|
| **`RemoteLockSession`**（`Serializable`） | acquire/poll/heartbeat/release 状態機械。永続フィールド（serverId/lockId/lastState/bodyStarted/completionSignaled）＋ transient（pollTask/heartbeatTask/consecutivePollFailures）。`Host` インタフェース経由で step 統合点へコールバック |
| **`RemoteLockRouting`**（static helpers） | `isRemoteRequest(step, lrm)` / `effectiveServerId(step, lrm, logger)` / `findConnection(lrm, serverId)` / `displayTarget(step)` |
| **`RemoteCredentials`**（static helper） | `basicAuthHeader(remote, run)`（資格情報→Authorization ヘッダ解決。`Run` を引数で受ける） |

### `Host` シーム（`LockStepExecution` が実装）

`RemoteLockSession` は StepExecution 内部（`StepContext` / body 起動 / serialize 跨ぎ）に依存する点だけを
`Host` 経由でホストへ委譲する。ホストに残るのは**薄い統合シムのみ**:

```
interface Host extends Serializable {
    StepContext context();                       // get(Run/FlowNode/TaskListener), onFailure/onSuccess, newBodyInvoker
    void runBody(String displayTarget, Map<String,String> lockEnvVars, String lockId);  // proceedRemote 相当（body 起動）
}
```

- `RemoteLockSession` が ACQUIRED を観測 → `host.runBody(...)` を呼ぶ。body 起動（`newBodyInvoker` ＋ release 用 `RemoteCallback`）は
  `StepContext` 依存のため `LockStepExecution` 側に残す（`runBody` 実装）。
- SKIPPED → `host.context().onSuccess(null)`、FAILED/EXPIRED/CANCELLED/UNKNOWN → セッションが `finishFailure`（`host.context().onFailure`）。
- `LockStepExecution.start()` は `if (RemoteLockRouting.isRemoteRequest(step, lrm)) { remoteSession = new RemoteLockSession(...); return remoteSession.start(host); }` の分岐のみ。
- `onResume()` / `stop()` は `remoteSession` があれば委譲。

### 抽出後の `LockStepExecution`

remote 関連で残るのは: `start()` の分岐数行、`runBody`（body 起動＝旧 `proceedRemote`）、`RemoteCallback`（body 終了時 release・
`releaseRemoteLockBestEffort` はセッションに移動しコールバックは薄く）、`onResume`/`stop` の委譲。**+553 → 目標 +80〜100 行**。

---

## 4. 抽出② サーバ解決ロジック → `remote.RemoteResolver`（`LockableResourcesManager` から）

### 移動するメソッド（LRM → `RemoteResolver`）

admission ＋ canonical 解決の**純ロジック**: `validateRemoteSelectors` / `validateSelector` / `isExposed` /
`hasExposedCandidate` / `toRemoteStructs` / `addRemoteStruct` / `availableForRemote` / `remoteLockEnvVars` /
`parseSelectStrategy`（~140 行）。

### コラボレータ設計

`RemoteResolver` は `LockableResourcesManager` への参照を保持し、その**公開アクセサのみ**を使う:
- `lrm.getExposeLabels()`（設定・据え置き） / `lrm.fromName(name)` / `lrm.getResources()` /
  `lrm.getAvailableResources(structs, logger, strategy, predicate)`（§2 のシーム）。
- いずれも既存 public。新規に LRM 内部を晒さない（**カプセル化は悪化させない**）。
- `remoteLockEnvVars` は `LockStepExecution.buildLockEnvVars`（local と共有の static）を引き続き利用。

### 呼び出し元の付け替え

- `RemoteLockManager.enqueue`: `lrm.validateRemoteSelectors/toRemoteStructs/availableForRemote` → `resolver.…`、
  `LockableResourcesManager.remoteLockEnvVars` → `resolver.remoteLockEnvVars`（`new RemoteResolver(lrm)` を enqueue で生成）。
- `LRM.getNextRemoteEntry`（キュー昇格・コアに残る）: `availableForRemote(...)` → `new RemoteResolver(this).availableForRemote(...)`。
- `RemoteQueueEntry.onAcquired`: `LockableResourcesManager.remoteLockEnvVars` → `RemoteResolver.remoteLockEnvVars`（static 維持可）。

### `syncResources` 契約の保存

移動メソッドは従来どおり「`syncResources` 下で呼ぶ」契約。呼び出し元（`RemoteLockManager.enqueue` /
`LRM.getNextRemoteEntry`）は既に `synchronized(syncResources)` 内なので、**ロック獲得の責務は呼び出し元のまま**変わらない。
`RemoteResolver` 自身はロックを取らない（純粋な解決ヘルパ）。Javadoc に「呼び出し側が syncResources を保持していること」を明記。

### コアに残る remote 痕跡（LRM）

§2 のシーム＋キューブリッジ＋設定。**+575 → 目標 +430 程度**（解決ロジック ~140 行が remote 層へ。残りは
正当なコア統合＝統一キュー・設定・Predicate シーム）。

---

## 5. その他

- **`LockableResourcesRootAction.doReleaseRemoteLock`（+61）**: ダッシュボードの管理 force-release アクション。
  HTTP/権限/RootAction 文脈に属するため**コアに残す**が、解放本体が LRM/RemoteLockManager のメソッドを呼ぶだけになるよう
  確認（薄ければ追加移動はしない）。M1G の主目的（state machine / resolver の凝集）からは外す。
- **`buildLockEnvVars`（`LockStepExecution` の static）**: local `proceed` と共有のため `LockStepExecution` に**残す**
  （local 由来。remote 専用ではない）。

## 6. スコープ整理

### 含む（M1G）

| 項目 | 内容 |
|---|---|
| 抽出① | `RemoteLockSession` ＋ `RemoteLockRouting` ＋ `RemoteCredentials` を新設し、`LockStepExecution` の状態機械を移動。Host シムだけ残す |
| 抽出② | `RemoteResolver` を新設し、LRM の admission/解決ロジックを移動。呼び出し元を付け替え |
| テスト | 既存 382＋E2E 20/20 グリーン維持。新クラスに配置固定ユニットを必要に応じ追加 |
| ドキュメント | 本書＋STEPS（j+e）、RESULT、README 索引/Status |

### 含まない（M1G スコープ外）

| 項目 | 備考 |
|---|---|
| 挙動変更・新機能・新 E2E | 純リファクタのため一切なし |
| 設定の別 holder 化 | Q2 で LRM 据え置き確定 |
| 統一キュー（proceedNextContext フック・remote キュー操作） | §2 のとおり正当なコア統合として残す |
| クライアント UI / read-only ミラー | 別サイクル（Phase 2 相当。[[LRR_REVIEW_P1_M1F]] 後の議論） |

## 7. 検証

- `dev/stabilize-build.sh`（worktree、コミット済み HEAD をビルド）で mvn フル成功（382＋新規ユニット、0 失敗）。
- `dev/jenkins-env/run-e2e.sh --clean-start` 全 20 件 PASS（挙動不変の回帰確認。特に S09 delegated / S11 heartbeat-resilience /
  S13 stale-admin-release / S16 resource-properties / S17 unknown-rejected が状態機械・解決・キューの移動を実環境で踏む）。

## 更新履歴

- 2026-06-15: 初版作成。M1F レビュー後の「コア改変が大きい」分析（既存5ファイルに ~1,208 行）を受け、挙動不変のまま
  remote ロジックを `remote` パッケージへ凝集する整理サイクルとして M1G を定義。抽出①（`RemoteLockSession`＋helpers、
  `LockStepExecution` から ~450 行）／②（`RemoteResolver`、LRM から ~140 行）を1サイクルで実施。設定は LRM 据え置き、
  統一キュー・Predicate シーム・公開 DSL/リソース状態は「不可避コアシーム」として意図的に残置（§2）。
