# M1A Implementation Steps (Remote lock - Phase 1 / M1A)

このファイルは個人用の進捗トラッカーです。
M1A の各変更を機能単位のコミットに分け、後から追跡できるようにします。

## 使い方

- 各ステップは完了したらチェックを入れる。
- 各ステップで「コミット」「対象ファイル」「確認結果」を記録する。
- 1ステップ 1コミットを基本にする（必要なら 1ステップ複数コミットでも可）。

## M1A のゴール

M1（最小 peer mode）を「`lock(...)` の透過 remote ラッパー」として意味論的に完成させる。

| 目標 | M1 現状 | M1A 達成目標 |
|---|---|---|
| lockRequest 透過 | flat フィールドで `resource` のみ送信 | `lockRequest` ネストオブジェクトで全 lock 意味論を透過送信 |
| 多リソース対応 | 単一リソース名のみ | `label` + `quantity` / `extra` 対応 |
| lockEnvVars 等価展開 | `step.variable` + 単一リソース名のみ | `GET /acquire/{lockId}` が local `lock()` と等価な `lockEnvVars` を返す |
| delegated mode | `serverId` 明示のみ（peer mode） | `forcedServerId` 設定で DSL 変更なしに全 `lock()` を remote に委譲 |

起点ブランチ: `feature/1025-remote-lockable-resources-p1-m1a`
（M1 の 14 コミット + テスト追従 1 コミット、全 326 件テスト成功確認済み）

参照設計書: `dev/docs-j/LRR_DESIGN_P1_M1A.md`

---

## ステップ一覧

### 0. 事前準備（完了済み）

- [x] 作業ブランチ `feature/1025-remote-lockable-resources-p1-m1a` 整備済み
- [x] M1 全テスト（326 件）が BUILD SUCCESS で通ることを確認済み
- [x] `LRR_DESIGN_P1_M1A.md` 設計書確認済み
- [x] ビルド環境（stabilize-build.sh / worktree モード）が安定していることを確認済み

記録:
- 日付: 2026-06-10
- ブランチ HEAD: `e8b8431`（テスト追従コミット、M1A 実装の起点）
- ビルドログ: `dev/reports/20260610231428-mvn-test.log`（BUILD SUCCESS / 326 件）

---

### 1. `RemoteLockRequest` DTO + lockRequest wire 形式変更

目的:
- M1 の flat フィールド形式（`resource`, `skipIfLocked` をトップレベルで送信）から、M1A の `lockRequest`
  ネストオブジェクト形式へ wire format を移行する。
- `LockStep` が持つ全 lock 意味論パラメータをクライアントからサーバーへ透過的に送れるようにする。
- **この時点ではサーバー側の取得ロジックは変更しない**（Step 2 で対応）。
  wire 形式のみ M1A 仕様に合わせる。

#### 設計要点（`LRR_DESIGN_P1_M1A.md` § 4 より）

クライアントが送る POST /acquire リクエスト:
```jsonc
{
  "lockRequest": {
    "resource": "board-a1",
    "label": "hw-board",
    "quantity": 2,
    "variable": "LOCKED_RESOURCE",
    "inversePrecedence": false,
    "resourceSelectStrategy": "SEQUENTIAL",
    "skipIfLocked": false,
    "extra": [],
    "priority": 10,
    "timeoutForAllocateResource": 5,
    "timeoutUnit": "MINUTES",
    "reason": "deploy"
  },
  "heartbeatIntervalSeconds": 10,
  "clientId": "https://jenkins-a.example.com/"
}
```

`serverId` / `forcedServerId` は routing 情報のため `lockRequest` に含めない。

#### 実装内容

**新規クラス**
- `src/main/java/.../remote/RemoteLockRequest.java` (新規)
  - `resource` / `label` / `quantity` / `variable` / `inversePrecedence` /
    `resourceSelectStrategy` / `skipIfLocked` / `extra` / `priority` /
    `timeoutForAllocateResource` / `timeoutUnit` / `reason` の各フィールドを保持するデータクラス
  - `LockStep` から生成するファクトリメソッド `static RemoteLockRequest from(LockStep step)` を追加
  - `@NonNull` / `@CheckForNull` 注釈を適切に付与
  - `resource` と `label` の両方 null の場合は不正（バリデーションは呼び出し側で実施）

**クライアント側変更**
- `RemoteApiClient.enqueueAcquire()`:
  - シグネチャ変更: `String resource, boolean skipIfLocked` 個別引数を除去し
    `RemoteLockRequest lockRequest` パラメータに統合
  - リクエスト JSON を `{ "lockRequest": { ... }, "heartbeatIntervalSeconds": 10, "clientId": "..." }` 形式に変更
  - `lockRequest` フィールドのシリアライズ: null 値はスキップ（`extra` は空リスト時もスキップ）
- `LockStepExecution`:
  - `enqueueAcquire()` 呼び出し箇所を `RemoteLockRequest.from(step)` で統合
  - `validateRemoteResource()` メソッド（現在は `step.resource` が空なら例外）を修正:
    `resource` も `label` も null の場合のみエラー（label-only の lock を許容）

**サーバー側変更**
- `RemoteApiV1Action.AcquireRouter.doIndex()`:
  - `"lockRequest"` キーのネストオブジェクトをパース（存在しない場合は 400 MISSING_LOCK_REQUEST）
  - `resource` と `label` を `lockRequest` から取得
  - `skipIfLocked` / `heartbeatIntervalSeconds` / `clientId` も対応フィールドから取得
  - `RemoteLockManager.enqueue()` のシグネチャを `RemoteLockRequest` 受け取りに変更（実装は Step 2）
  - この時点では resource/label いずれかを使った既存の enqueue() を呼ぶだけでよい
  - バリデーション追加: `resource` と `label` が両方 null の場合は 400 MISSING_LOCK_TARGET

**テスト更新**
- `RemoteApiClientTest`: `enqueueAcquire()` の引数を `RemoteLockRequest` 型に更新、
  lockRequest ネスト JSON が正しく生成されることを確認するテストを追加
- `RemoteApiV1ActionTest`: `lockRequest` ネスト形式での POST /acquire テスト
  （旧 flat 形式は後方互換不要として削除）

完了条件:
- `mvn test -Dtest=RemoteApiClientTest,RemoteApiV1ActionTest` が通る
- `RemoteApiClient` が新 `lockRequest` ネスト JSON を送ること
- `RemoteApiV1Action` が `lockRequest` オブジェクトをパースできること
- `LockStepExecution` が全 `LockStep` フィールドを `RemoteLockRequest` 経由で渡せること
- `mvn test` 全件 BUILD SUCCESS（既存 326 件 + 新規テスト）

- [x] 実装完了
- [x] `mvn test` 確認完了
- [x] コミット済み

記録:
- 日付: 2026-06-11
- コミット: `19a0703`
- 変更ファイル:
  - src/main/java/.../remote/RemoteLockRequest.java (新規)
  - src/main/java/.../remote/RemoteLockRecord.java (編集: `@NonNull` → `@CheckForNull` on resourceName)
  - src/main/java/.../remote/RemoteApiClient.java (編集: enqueueAcquire シグネチャ変更 + buildLockRequestJson 追加)
  - src/main/java/.../remote/RemoteLockManager.java (編集: enqueue シグネチャ変更 + label-only FAILED対応)
  - src/main/java/.../LockStepExecution.java (編集: resolveRemoteDisplayTarget + RemoteLockRequest.from 使用)
  - src/main/java/.../actions/RemoteApiV1Action.java (編集: lockRequest ネストパース)
  - src/test/java/.../remote/RemoteApiClientTest.java (編集: enqueueAcquire 呼び出し更新)
  - src/test/java/.../actions/RemoteApiV1ActionTest.java (編集: lockRequest ネスト形式テスト)
  - src/test/java/.../remote/RemoteLockManagerTest.java (編集: enqueue 呼び出し更新)
  - src/test/java/.../actions/LockableResourcesRootActionTest.java (編集: enqueue 呼び出し更新)
- 確認結果: Tests run: 326, Failures: 0, Errors: 0, Skipped: 1 — BUILD SUCCESS (19:57)

---

### 2. サーバー側: label/quantity 対応多リソース取得

目的:
- `lockRequest.label` + `lockRequest.quantity` を使って複数リソースを一括取得できるようにする。
- M1 では単一 `resource` 名のみだったが、M1A ではサーバー側でも label-based / quantity 指定の
  local `lock()` と等価な取得挙動を実現する。
- 取得済みリソース名リストをレコードに保持し、release 時に全件解放できるようにする。

#### 設計方針

取得ロジック（`RemoteLockManager.enqueue()` / `tryAcquireQueued()`）:

| lockRequest のパラメータ | サーバー側挙動 |
|---|---|
| `resource` のみ指定 | `lrm.fromName(resource)` → `isFree()` + `setRemoteLockedBy()` (M1 相当) |
| `resource` + `extra[]` | `resource` + `extra` 全リソースを同時取得（全部 free の場合のみ取得、一部でも busy なら wait） |
| `label` + `quantity` | `lrm.getResourcesWithLabel(label)` から exposed かつ free のものを `quantity` 分取得 |
| `label` のみ（quantity=0） | quantity=1 として扱う |
| skipIfLocked=true | 取得できない場合は QUEUED ではなく SKIPPED へ即遷移 |

`exposeLabel` チェック:
- resource-based: 指定リソースが `exposeLabel` を持つこと（M1 相当）
- label-based: 取得候補リソースが `exposeLabel` を持つこと

`RemoteLockRecord` のリソース保持:
- M1 の `String resourceName` は `List<String> acquiredResourceNames` に変更
- enqueue 時は null（取得前）、取得成功時にセット
- QUEUED retry に必要な情報（`label`, `quantity`, `resource`, `skipIfLocked`）を保持

解放ロジック (`RemoteLockManager.release()`):
- `acquiredResourceNames` の全件について `setRemoteLockedBy(null)` を呼ぶ

#### 実装内容

- `RemoteLockRecord`:
  - `String resourceName` → retry 情報 + `List<String> acquiredResourceNames` に再設計
  - retry 情報フィールド: `label` / `quantity` / `resource` / `skipIfLocked`
    （コンストラクタで `RemoteLockRequest` から受け取る）
  - `markAcquired(List<String> names)` にシグネチャ変更（lockEnvVars は Step 3 で追加）
  - `getAcquiredResourceNames()` を追加。後方互換のため `getResourceName()` は
    acquiredResourceNames が 1 件の場合に最初の要素を返す形で維持（または削除）
- `RemoteLockManager`:
  - `enqueue(RemoteLockRequest, String clientId)` シグネチャに変更
  - label-based 取得ロジックを実装（`lrm.getResourcesWithLabel()` を利用）
  - resource + extra の同時取得ロジックを実装
  - `tryAcquireQueued()` も同様に label/quantity/extra 対応
  - `release()`: `acquiredResourceNames` 全件を解放するよう変更
  - ヘルパー `isExposedResource(LockableResource, LockableResourcesManager)`: exposeLabel チェック共通化

完了条件:
- `mvn test -Dtest=RemoteLockManagerTest,RemoteApiV1ActionTest` が通る
- label + quantity=2 の acquire が `QUEUED → ACQUIRED` 遷移で動作すること
- `skipIfLocked=true` で busy な label-リソースが `SKIPPED` になること
- `release` で `acquiredResourceNames` の全リソースが free に戻ること
- resource + extra の同時取得ができること
- `mvn test` 全件 BUILD SUCCESS

- [x] 実装完了
- [x] `mvn test` 確認完了
- [x] コミット済み

記録:
- 日付: 2026-06-11
- コミット: `9a08b8f`
- 変更ファイル:
  - src/main/java/.../remote/RemoteLockRecord.java (編集: RemoteLockRequest 保持 + acquiredResourceNames)
  - src/main/java/.../remote/RemoteLockManager.java (編集: label/quantity/extra 対応取得ロジック)
  - src/test/java/.../remote/RemoteLockManagerTest.java (編集: 10 テスト追加)
- 確認結果: Tests run: 336, Failures: 0, Errors: 0, Skipped: 1 — BUILD SUCCESS

---

### 3. lockEnvVars 生成・送信・受信・適用

目的:
- 取得成功時にサーバー側で `lockEnvVars` を生成し、`GET /acquire/{lockId}` のレスポンスに含める。
- クライアント側は `lockEnvVars` を受け取り、local `lock()` と同等の環境変数展開を `{ body }` に適用する。
- 設計書 §2 の等価展開ゴールを達成する。

#### 設計方針

`lockEnvVars` 生成ルール（local `lock()` の変数展開に準拠）:
- `lockRequest.variable` が設定されている場合:
  - `{variable}`: スペース区切りの全取得リソース名（例: `"r1 r2"`）
  - `{variable}0`, `{variable}1`, ...: 各リソース名
- `variable` が未設定の場合: `lockEnvVars` を `null` で返す（クライアントは環境変数注入なしで body を実行）

```jsonc
// ACQUIRED 時の GET /acquire/{lockId} レスポンス例
{
  "lockId": "...",
  "state": "ACQUIRED",
  "errorCode": null,
  "message": null,
  "lockEnvVars": {
    "LOCKED_RESOURCE": "r1 r2",
    "LOCKED_RESOURCE0": "r1",
    "LOCKED_RESOURCE1": "r2"
  }
}
```

#### 実装内容

**サーバー側**
- `RemoteLockRecord`:
  - `Map<String, String> lockEnvVars` フィールドを追加（nullable）
  - `markAcquired(List<String> names, Map<String, String> lockEnvVars)` にシグネチャ変更
  - `getLockEnvVars()` ゲッターを追加
- `RemoteLockManager`:
  - `generateLockEnvVars(String variable, List<String> resourceNames)` プライベートメソッドを追加:
    `variable` が null / 空の場合は null を返す。それ以外は上記ルールで Map を生成
  - `enqueue()` / `tryAcquireQueued()` での `markAcquired()` 呼び出しに lockEnvVars を渡す
- `RemoteApiV1Action.AcquireStatusResource.doIndex()`:
  - レスポンス JSON に `"lockEnvVars"` を追加（state=ACQUIRED かつ非 null の場合のみ）
  - `"message"` フィールドも追加（現状 errorCode のみだが設計書では含まれる）

**クライアント側**
- `RemoteAcquireStatus`:
  - `Map<String, String> lockEnvVars` フィールドを追加
  - コンストラクタ・ゲッターを更新
- `RemoteApiClient.getAcquireStatus()`:
  - レスポンス JSON の `"lockEnvVars"` オブジェクトを `Map<String, String>` としてパース
  - `lockEnvVars` キーが存在しない / null の場合は `null`（QUEUED 等の場合）
- `LockStepExecution.proceedRemote()`:
  - `status.getLockEnvVars()` が非 null の場合: 全エントリを `EnvironmentAction` に適用する
  - M1 の手動展開コード（`step.variable` + 単一リソース名を直接構築）を除去し
    `lockEnvVars` ベースに切り替える
  - `lockEnvVars` が null の場合: 環境変数注入なしで body を実行（`variable` 未設定ケース）

完了条件:
- `mvn test -Dtest=RemoteApiV1ActionTest,LockStepRemoteTest,RemoteApiClientTest` が通る
- `variable` 指定時に `GET /acquire/{lockId}` レスポンスに `lockEnvVars` が含まれること
- クライアント側で `lockEnvVars` が EnvironmentAction に反映されること
- 複数リソース取得時に全リソース名が展開されること（`variable0`, `variable1`, ...）
- `variable` 未指定時に `lockEnvVars=null` でも body が正常に実行できること
- `mvn test` 全件 BUILD SUCCESS

- [ ] 実装完了
- [ ] `mvn test` 確認完了
- [ ] コミット済み

記録:
- 日付:
- コミット:
- 変更ファイル:
  - src/main/java/.../remote/RemoteLockRecord.java (編集)
  - src/main/java/.../remote/RemoteLockManager.java (編集)
  - src/main/java/.../actions/RemoteApiV1Action.java (編集)
  - src/main/java/.../remote/RemoteAcquireStatus.java (編集)
  - src/main/java/.../remote/RemoteApiClient.java (編集)
  - src/main/java/.../LockStepExecution.java (編集)
  - src/test/java/.../remote/RemoteApiClientTest.java (編集)
  - src/test/java/.../actions/RemoteApiV1ActionTest.java (編集)
  - src/test/java/.../LockStepRemoteTest.java (編集)
- 確認結果:

---

### 4. forcedServerId delegated mode

目的:
- Controller 側設定 `forcedServerId` を追加し、DSL の `serverId` 指定なしでも全 `lock()` 呼び出しを
  remote に委譲できる delegated mode を実装する。
- peer mode（`step.serverId` 明示）との共存を保ちつつ、`forcedServerId` が設定されている場合は
  `forcedServerId` が優先される（issue #1025 コメント 12 の resolution rules に準拠）。

#### 設計方針（`LRR_DESIGN_P1_M1A.md` § 2, 3, 6 より）

ルーティング解決ルール:
```
forcedServerId が設定されている場合:
    target = forcedServerId のリモート
    ※ step.serverId は INFO ログ出力後に無視（lockRequest には含めない）

forcedServerId が未設定かつ step.serverId が指定されている場合:
    target = (step.serverId, lockRequest)  → peer mode

どちらも未設定:
    target = LOCAL  → 既存挙動（影響なし）
```

重要:
- `forcedServerId` は routing 情報のため `lockRequest` には含めない
- `forcedServerId` が設定されているのに `remotes` にそのキーが存在しない場合:
  設定保存時にバリデーションエラー

#### 実装内容

**設定モデル**
- `LockableResourcesManager`:
  - `forcedServerId: String`（nullable）フィールドを追加
  - `getForcedServerId()` / `setForcedServerId()` を追加
  - `readResolve()` に null 正規化を追加
  - `Descriptor.configure()` または専用バリデーターで、`forcedServerId` が設定されている場合に
    `remotes` のキーに存在するか確認（存在しない場合は `FormValidation.warning()` または error）

**ルーティング**
- `LockStepExecution.isRemoteLock()`:
  - 既存の `step.serverId != null` 判定に加えて、
    `LockableResourcesManager.get().getForcedServerId() != null` の場合も true を返す
- `LockStepExecution` のリモートフロー冒頭:
  - `String effectiveServerId = lrm.getForcedServerId() != null ? lrm.getForcedServerId() : step.serverId;`
  - `lrm.getForcedServerId() != null && step.serverId != null && !step.serverId.equals(lrm.getForcedServerId())` の場合:
    INFO ログ出力（「forcedServerId が優先されます: ...」）
  - `findRemoteConnectionOrFail()` を `effectiveServerId` で呼び出す

**Settings UI**
- `src/main/resources/.../LockableResourcesManager/config.jelly`:
  - "Remote Lockable Resources (Client)" セクションに `forcedServerId` textbox を追加
  - 位置: `clientId` フィールドと `remotes` repeatable の間が適切
- `src/main/resources/.../LockableResourcesManager/config.properties`:
  - `forcedServerId` ラベルキーを追加
- `src/main/resources/.../LockableResourcesManager/help-forcedServerId.html` (新規):
  - delegated mode の説明・使用例・注意点（`forcedServerId` が設定されると全 lock が remote に委譲される旨）

完了条件:
- `mvn test -Dtest=LockStepRemoteTest,LockableResourcesManagerRemoteConnectionTest` が通る
- `forcedServerId` を設定すると `lock('X')` が remote に委譲されること（serverId なし DSL）
- `forcedServerId` 設定済みで DSL に `serverId` を書いても `forcedServerId` が優先されること（INFO ログあり）
- `forcedServerId` 未設定時は既存 peer mode / local mode に影響しないこと
- UI で `forcedServerId` を設定・保存・再読み込みできること
- `mvn test` 全件 BUILD SUCCESS

- [ ] 実装完了
- [ ] `mvn test` 確認完了
- [ ] コミット済み

記録:
- 日付:
- コミット:
- 変更ファイル:
  - src/main/java/.../LockableResourcesManager.java (編集)
  - src/main/java/.../LockStepExecution.java (編集)
  - src/main/resources/.../LockableResourcesManager/config.jelly (編集)
  - src/main/resources/.../LockableResourcesManager/config.properties (編集)
  - src/main/resources/.../LockableResourcesManager/help-forcedServerId.html (新規)
  - src/test/java/.../LockStepRemoteTest.java (編集)
  - src/test/java/.../LockableResourcesManagerRemoteConnectionTest.java (編集)
- 確認結果:

---

### 5. テスト拡張・回帰固定

目的:
- M1A の核心機能（lockRequest 透過・label/quantity 取得・lockEnvVars 展開・forcedServerId）を
  回帰テストとして固定する。
- Step 1〜4 の各ステップで暫定的にした既存テスト更新を最終化し、抜け漏れを補完する。

対象テスト（追加 / 拡張）:

**`RemoteApiV1ActionTest`**:
- `lockRequest` ネスト形式で POST /acquire（resource-based・label-based）
- `lockEnvVars` 付きの ACQUIRED レスポンス確認
- label-based で `exposeLabel` フィルタが正しく動作すること
  （`exposeLabel` = "hw" に対して label="hw" が ACQUIRED、label="other" が UNKNOWN_RESOURCE）
- label + quantity 不足時は 202 + QUEUED（待機）になること
- `resource` と `label` 両方 null で 400 MISSING_LOCK_TARGET になること

**`RemoteLockManagerTest`**:
- label + quantity=2 の取得/解放サイクル
- skipIfLocked + label-based（リソース busy 時に SKIPPED）
- resource + extra の同時取得（extra が busy なら全部 QUEUED）
- release で acquiredResourceNames 全件が free に戻ること
- lockEnvVars の variable なし（null を返すこと）
- lockEnvVars の variable あり（正しいキー/値セットを返すこと）

**`LockStepRemoteTest`**:
- `variable` 指定時に body 内で `lockEnvVars` 相当の環境変数が展開されること
  （`LOCKED_RESOURCE`, `LOCKED_RESOURCE0` が期待値）
- `variable` 未指定時に環境変数なしで body が正常実行できること
- `forcedServerId` 設定時に `serverId` なし DSL が remote に委譲されること
- `forcedServerId` 設定時に `serverId` ありの DSL で `forcedServerId` が優先されること（INFO ログ）
- label-based の lockRequest を送る end-to-end の最小ケース（mocked server）

**`LockableResourcesManagerRemoteConnectionTest`**:
- `forcedServerId` の保存・再読み込み（Global Configure round-trip）
- `forcedServerId` が `remotes` キーに存在しない場合のバリデーション動作

完了条件:
- 追加テストが全件成功
- `mvn test` 全件 BUILD SUCCESS

- [ ] 実装完了
- [ ] `mvn test` 確認完了
- [ ] コミット済み

記録:
- 日付:
- コミット:
- 変更ファイル:
  - src/test/java/.../actions/RemoteApiV1ActionTest.java (編集)
  - src/test/java/.../remote/RemoteLockManagerTest.java (編集)
  - src/test/java/.../LockStepRemoteTest.java (編集)
  - src/test/java/.../LockableResourcesManagerRemoteConnectionTest.java (編集)
- 確認結果:

---

### 6. E2E シナリオ拡張 (lockable-resources-remote-notes 側)

目的:
- M1A で追加した機能（label-based 取得 + lockEnvVars 展開、forcedServerId delegated mode）を
  実際の Jenkins 起動環境で確認する。
- M1 の既存 10 シナリオに M1A 特有の 2 シナリオを追加する。

追加シナリオ:

**`label-env-vars`** (S08):
- Controller A が Controller B の `exposeLabel` 付きリソースを label-based で取得する。
- `variable` を指定し、body 内で `printenv` / `echo ${LOCKED_RESOURCE}` 等でキャプチャ。
- レポートの Checkpoint に `lockEnvVars` 相当の環境変数が期待値通りに展開されていることを記録する。

**`delegated-mode`** (S09):
- Controller A に `forcedServerId = B` を設定する。
- `lock('resource-b1')` という `serverId` なし DSL を持つジョブを A で実行する。
- ジョブが Controller B のリソースを取得できることを確認する。
- A のジョブ実行中に Controller B の LR ページで `Remote: jenkins-a` 表示を確認する。

既存シナリオの追従:
- `peer-basic` → lockRequest 新形式への対応（setup スクリプト変更なければ影響なし）
- `fan-in-contention` / `server-self-use` 等: 環境初期化の resource/label 設定が変わる場合は更新

実装内容:
- `dev/jenkins-env/scenarios/label-env-vars.sh` (新規)
- `dev/jenkins-env/scenarios/delegated-mode.sh` (新規)
- `dev/jenkins-env/run-e2e.sh` (編集: 新シナリオ S08, S09 を登録)
- `dev/jenkins-env/lib/common.sh` (編集: forcedServerId 設定ヘルパー関数を追加)
- `dev/docs-j/E2E_TEST_SPECIFICATION.md` (編集: S08, S09 シナリオ定義を追記)

完了条件:
- `./run-e2e.sh --only label-env-vars` が PASS（lockEnvVars 展開確認）
- `./run-e2e.sh --only delegated-mode` が PASS（forcedServerId ルーティング確認）
- `./run-e2e.sh --only all` が全 PASS（既存 10 + 新規 2 = 12 シナリオ）

- [ ] 実装完了
- [ ] E2E 確認完了
- [ ] コミット済み

記録:
- 日付:
- コミット:
- 変更ファイル:
  - dev/jenkins-env/scenarios/label-env-vars.sh (新規)
  - dev/jenkins-env/scenarios/delegated-mode.sh (新規)
  - dev/jenkins-env/run-e2e.sh (編集)
  - dev/jenkins-env/lib/common.sh (編集)
  - dev/docs-j/E2E_TEST_SPECIFICATION.md (編集)
- 確認結果:

---

## テスト実行の整理（M1A 方針）

1. Step 1〜4 の各ステップで `mvn test -Dtest=<対象テスト>` を実行してステップ単位での成功を確認する。
2. 各ステップのコミット前に `./stabilize-build.sh`（worktree モード）で全件 `mvn test` を実行する
   （jdt.ls 競合回避のため。`--in-place` は Java 拡張停止が前提）。
3. Step 5 は追加テストを含めた全件確認（`mvn test` BUILD SUCCESS + テスト件数増加を確認）。
4. Step 6 は `lockable-resources-remote-notes` 側の E2E ハーネスで確認する（`./run-e2e.sh`）。

## コミット運用ルール（M1A）

- 1ステップ 1コミットを基本とする
- コミットメッセージ例:
  - Step 1: `feat(remote-lock): transparent lockRequest payload (M1A wire format)`
  - Step 2: `feat(remote-lock): label/quantity multi-resource acquisition (M1A server)`
  - Step 3: `feat(remote-lock): lockEnvVars generation and client application (M1A)`
  - Step 4: `feat(remote-lock): forcedServerId delegated mode (M1A)`
  - Step 5: `test(remote-lock): M1A regression coverage`
  - Step 6: `chore(e2e): add M1A scenarios (label-env-vars, delegated-mode)`
- ステップ跨ぎの変更は避ける
- 仕様変更が入ったらこのファイルのステップ定義も更新する

## 現在ステータス

- プラン作成日: 2026-06-11
- 起点ブランチ HEAD: `e8b8431`（M1A 実装の起点、全 326 件テスト成功確認済み）
- **Step 0: 完了 ✅**
- Step 1〜6: 未着手
- 次アクション: Step 1 実装着手（`RemoteLockRequest` DTO + lockRequest wire 形式変更）
