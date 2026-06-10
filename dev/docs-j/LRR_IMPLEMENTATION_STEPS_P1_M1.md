# M1 Implementation Steps (Remote lock - Phase 1 / M1)

このファイルは個人用の進捗トラッカーです。
実装を機能単位のコミットに分け、後から追跡できるようにします。

## 使い方

- 各ステップは完了したらチェックを入れる。
- 各ステップで「コミット」「対象ファイル」「確認結果」を記録する。
- 1ステップ 1コミットを基本にする（必要なら 1ステップ複数コミットでも可）。

## M1 のゴール

- `lock(..., serverId: 'X')` の明示指定で remote lock を扱える最小実装を作る。
- まずは peer mode の最小成立を優先し、後続で拡張しやすい構造にする。

## ステップ一覧

### 0. 事前準備（ブランチ/環境）

- [x] 作業ブランチを最新 master から作成済み
- [x] 3 controller ローカル環境（8081/8082/8083）で起動確認済み
- [x] 既存テストが通る基準点を確認済み

記録:
- 日付: 2026-05-09
- コミット: 739d6da（※ rebase 後の基点は `739d6da` のまま。M1 クローズ時点も同一）
- メモ: $HOME/.local/apache-maven-3.9.9/bin/mvn test を実行し BUILD SUCCESS（Tests run: 238, Failures: 0, Errors: 0, Skipped: 1, Total time: 13:42）を確認。
  2026-05-14 時点で cold build でも BUILD SUCCESS（Tests run: 238, Failures: 0, Errors: 0, Skipped: 1）を確認。
  2026-05-19 時点で Step 6c 実装後に再度 `$HOME/.local/apache-maven-3.9.9/bin/mvn test` を実行し BUILD SUCCESS（Tests run: 274, Failures: 0, Errors: 0, Skipped: 1, Total time: 13:37）を確認。
  - 補足: 現在の M1 PR ベースは upstream/master 直系（cherry-pick なし）。
  - Skipped: 1 は `LockStepInversePrecedenceTest#lockInverseOrderWithLabel`。JENKINS-40787 / GitHub #861 の既存バグ（ラベルベースロックで inversePrecedence が適用されずハングする）により `@Disabled` でスキップ中。M1 実装とは無関係。

---

### 1. リモート接続設定モデルの追加

目的:
- `serverId -> (url, credentialsId)` の設定を持てる土台を追加する。

実装候補:
- `LockableResourcesManager` に `remotes` 設定を追加
- 必要なら専用 model クラス（例: `RemoteConnection`）を追加
- 保存/読み込み/バリデーションの最小実装

完了条件:
- 設定が保存され、再起動後も読み出せる
- 不正値に対する最低限の入力チェックがある

- [x] 実装完了
- [x] 単体確認完了

記録:
- 日付: 2026-05-09
- コミット: d087498
- 変更ファイル:
  - src/main/java/.../RemoteConnection.java (新規)
  - src/main/java/.../LockableResourcesManager.java (編集)
  - src/test/java/.../RemoteConnectionTest.java (新規)
  - src/test/java/.../LockableResourcesManagerRemoteConnectionTest.java (新規)
- 確認結果: $HOME/.local/apache-maven-3.9.9/bin/mvn test -Dtest=RemoteConnectionTest,LockableResourcesManagerRemoteConnectionTest を実行し成功（Tests run: 15, Failures: 0, Errors: 0, Skipped: 0）。
- 補足: LockableResourcesManager は remotes を List で保持し、getRemotesAsMap() で動的に Map 変換。readResolve() で旧設定ロード時の null を空リストに正規化。reload を使った永続化テストを追加。

---

### 2. リモート API クライアントの骨格追加

目的:
- remote 側 REST へアクセスする最小クライアント層を分離して作る。

実装方針:
- クライアント責務は「HTTP呼び出し層 + DTO + エラー変換」に限定し、LockStepExecution への接続は次ステップへ分離
- 認証は Authorization ヘッダを受け取る形にして、資格情報解決責務は呼び出し側へ分離
- 既定値（内部定数）:
  - pollIntervalSeconds = 3
  - heartbeatIntervalSeconds = 10
  - requestTimeoutSeconds = 5（tick ループのブロック時間を抑えるため、Step5 で 10→5 に変更）
- エラー方針: fail-closed（4xx/5xx/通信失敗を RemoteApiException へ変換）
- URL方針: `/lockable-resources/remote/v1` を固定し、base URL の末尾スラッシュ差異を吸収
- ログ方針: serverId/method/path/status のみ出力し、認証情報は出力しない

完了条件:
- ダミー呼び出しを通せる（またはモックで検証できる）
- 失敗時の戻り値/例外方針が明確

- [x] 実装完了
- [x] 単体確認完了

記録:
- 日付: 2026-05-10
- コミット: 5b453dd
- 変更ファイル:
  - src/main/java/.../remote/RemoteClientDefaults.java (新規)
  - src/main/java/.../remote/RemoteAcquireState.java (新規)
  - src/main/java/.../remote/RemoteAcquireStatus.java (新規)
  - src/main/java/.../remote/RemoteApiException.java (新規)
  - src/main/java/.../remote/RemoteApiClient.java (新規)
  - src/test/java/.../remote/RemoteAcquireStatusTest.java (新規)
  - src/test/java/.../remote/RemoteApiClientTest.java (新規)
- 確認結果: $HOME/.local/apache-maven-3.9.9/bin/mvn test -Dtest=RemoteApiClientTest,RemoteAcquireStatusTest を Step2 コミット上で実行し成功（Tests run: 6, Failures: 0, Errors: 0, Skipped: 0）。
- 補足: レビュー指摘に合わせて、lockId欠如時のhttpStatus伝播、JSON parse失敗ログ、baseUrl防御チェック、null state→UNKNOWNフォールバックを反映済み。cancel 概念を Phase1 から外す方針に合わせ、Step2 履歴上も cancel API 実装を含めない形へ整理済み。

---

### 3. acquire/release の remote 呼び出しフロー実装

目的:
- acquire -> poll -> acquired/rejected -> release の最小ライフサイクルを実装する。

実装方針:
1. client 側はローカル queue に積まない（remote acquire は非同期ポーリングで追跡）
2. `start()` は remote acquire 登録後に即 return（non-blocking）
3. `GET /acquire/{lockId}` を 3 秒間隔でポーリング
4. 状態遷移:
  - `QUEUED` は継続
  - `ACQUIRED` で body 実行開始
  - `SKIPPED` は成功終了（body 未実行）
  - `FAILED` / `EXPIRED` は失敗終了
  - `CANCELLED` は中断扱い
5. heartbeat は body 実行中のみ送信し、body 完了で release
6. 中断時も release を試行（cancel 概念は Phase1 から除外）
7. fail-closed（通信失敗時に自動解放しない）
8. ログは `serverId / lockId / state` を中心に出し、認証情報は出力しない
9. RemoteApiClient の API 範囲は acquire/status + heartbeat/release（内部識別子は lockId 統一）
10. 再起動耐性は将来拡張しやすいフィールド設計に留め、完全復旧は次段で対応

完了条件:
- remote lock の取得/解放が end-to-end で成立
- 失敗時のログと終了動作が定義済み

- [x] 実装完了
- [x] 単体確認完了

記録:
- 日付: 2026-05-10
- コミット: 6c251fd
- 変更ファイル:
  - src/main/java/.../remote/RemoteApiClient.java (編集: heartbeat/release + optional Authorization header)
  - src/main/java/.../LockStepExecution.java (編集: remote enqueue/poll/heartbeat/release フロー)
  - src/main/java/.../LockStep.java (編集: serverId DataBoundSetter 追加)
- 確認結果: $HOME/.local/apache-maven-3.9.9/bin/mvn test -Dtest=LockStepTest,RemoteApiClientTest,RemoteAcquireStatusTest を実行し成功（Tests run: 37, Failures: 0, Errors: 0, Skipped: 0）。
- 補足: cancel 概念を Phase1 から除外する方針に合わせ、abort/完了とも release ベースでクリーンアップする実装へ整理済み。credentialsId は Phase1 では Authorization ヘッダーへ直接変換せず、認証未実装の扱いを明示している。

---

### 4. LockStep へ `serverId` 追加

目的:
- DSL から `serverId` を受け取り、local/remote の分岐に利用可能にする。

実装候補:
- `LockStep` に `serverId` フィールド追加
- Descriptor のバリデーション/補完（必要なら）
- `LockStepExecution` で remote 経路へ分岐

完了条件:
- `lock(resource: 'X', serverId: 'A')` が解釈される
- `serverId` なしの既存挙動が壊れない

- [x] 実装完了
- [x] 単体確認完了

記録:
- 日付: 2026-05-10
- コミット: 6c251fd
- 変更ファイル:
  - src/main/java/.../LockStep.java (編集: serverId DataBoundSetter 追加)
  - src/main/java/.../LockStepExecution.java (編集: serverId 分岐による remote フロー接続)
- 確認結果: $HOME/.local/apache-maven-3.9.9/bin/mvn test -Dtest=LockStepTest を実行し成功（Tests run: 31, Failures: 0, Errors: 0, Skipped: 0）。
- 補足: 実装は Step3 コミット内で同時に取り込んだため、履歴上は同一コミットで管理。

---

### 5. remote 側 REST エンドポイント（M1 必須範囲）

目的:
- M1 必要範囲のエンドポイントをサーバー側に実装する。

#### 確定設計方針

**1. リモートロックの表現（LockableResource 側）**
- `LockableResource` に `transient String remoteLockedBy`（lockId or null）フィールドを追加。
- LRM は `remoteLockedBy != null` のリソースを「使用中」と判定する。`RemoteLockRecord` の中身は知らない。

**2. Stapler ルーティング**
- `LockableResourcesRootAction.getDynamic("remote")` → `getDynamic("v1")` → `RemoteApiV1Action`
- `RemoteApiV1Action` に各エンドポイントを実装する。

**3. RemoteLockRecord の保管場所**
- `RemoteLockManager`（`@Extension`）を新規作成し、`ConcurrentHashMap<String, RemoteLockRecord>` で in-memory 管理。
- 永続化しない（Jenkins 再起動時は全レコードが消える）。
- 運用: 管理者が expose 対象リソースが healthy であることを確認してから `remoteApiEnabled = true` にする。

**4. マスタースイッチ / expose 設定**
- `LockableResourcesManager` に `remoteApiEnabled`（boolean、デフォルト false）と `exposeLabel`（String）を追加。
- `remoteApiEnabled = false` の場合、全エンドポイントが 403 を返す。

**5. 認証・認可**
- Jenkins 標準認証（API トークン）+ `Jenkins.READ` チェックのみ。
- 専用 Permission は M2 以降の検討とし、M1 では導入しない。

**6. Stale 検出と解放方針**
- `RemoteLockManager` のスケジューラスレッドで定期 scan し、STALE_THRESHOLD を超えたレコードを STALE マーク。
- Stale になったロックは自動解放しない（安全方向）。管理者が UI で手動 Unstale。
- Discovery / GET 系エンドポイントは read only（write 調停不要）。
- 並行性: `ConcurrentHashMap` + フィールドは `volatile`。

**並行性設計**
- `RemoteLockManager` は `ScheduledThreadPool(1)`（単一スレッド）で 1 秒周期の tick ループを持つ。
- tick 内で経過時間を見て必要なタスクを実行:
  - (client) 前回 poll から 3s 経過 → GET /acquire/{lockId}（アクティブロックごと）
  - (client) body 実行中 かつ 前回 heartbeat から 10s 経過 → POST /heartbeat（アクティブロックごと）
  - (client) Discovery: 前回から N 秒経過 → GET /resources
  - (server) 前回 Stale scan から STALE_THRESHOLD / 2 秒経過 → 全 RemoteLockRecord 走査
- 各タスクは `lastRunAt` タイムスタンプを持ち、tick 内で実行判断する。
- writer はこの 1 スレッドのみ → Discovery / GET 系は read only で調停不要。
- tick ループは単一スレッドのため、HTTP 呼び出しのブロック時間がそのまま tick 全体の遅延になる。
  この設計に合わせて `RemoteClientDefaults.DEFAULT_REQUEST_TIMEOUT_SECONDS` を 10 → 5 に変更する（Step5 コミットに含める）。

#### 実装対象エンドポイント

| メソッド | パス | 概要 |
|---|---|---|
| POST | `/lockable-resources/remote/v1/acquire` | acquire エンキュー、`{lockId}` を返す |
| GET  | `/lockable-resources/remote/v1/acquire/{lockId}` | 状態照会（QUEUED/ACQUIRED/SKIPPED/FAILED/EXPIRED） |
| POST | `/lockable-resources/remote/v1/lease/{lockId}/heartbeat` | heartbeat 更新、204 を返す |
| POST | `/lockable-resources/remote/v1/lease/{lockId}/release` | ロック解放、204 を返す |

#### 実装順序

1. `RemoteLockRecord` クラス新規作成
2. `RemoteLockManager` クラス新規作成（スケジューラ + record CRUD）
3. `LockableResource` に `remoteLockedBy` フィールド追加
4. `LockableResourcesManager` に `remoteApiEnabled` + `exposeLabel` 追加
5. `RemoteApiV1Action` 新規作成（エンドポイント実装）
6. `LockableResourcesRootAction` に `getDynamic` 追加

完了条件:
- local 側の `RemoteApiClient` から呼べる（3 controller 環境で動作確認）
- `remoteApiEnabled = false` のとき全エンドポイントが 403
- Stale マーク動作が確認できる

- [x] 実装完了
- [x] 単体確認完了

記録:
- 日付: 2026-05-14（2026-05-16 コードレビュー修正を amend）
- コミット: 05f09ba
- 変更ファイル:
  - src/main/java/.../remote/RemoteLockState.java (新規)
  - src/main/java/.../remote/RemoteLockRecord.java (新規)
  - src/main/java/.../remote/RemoteLockManager.java (新規)
  - src/main/java/.../remote/RemoteClientDefaults.java (編集: DEFAULT_REQUEST_TIMEOUT_SECONDS 10→5)
  - src/main/java/.../actions/RemoteApiV1Action.java (新規 + レビュー修正 amend)
  - src/main/java/.../LockableResource.java (編集: remoteLockedBy フィールド追加、isLocked() 更新)
  - src/main/java/.../LockableResourcesManager.java (編集: remoteApiEnabled + exposeLabel 追加)
  - src/main/java/.../actions/LockableResourcesRootAction.java (編集: getDynamic routing 追加)
  - src/test/resources/.../casc_expected_output.yml (編集: remoteApiEnabled: false 追加)
- 確認結果: `mvn test` で BUILD SUCCESS（Tests run: 261, Failures: 0, Errors: 0, Skipped: 1）。レビュー修正後も同結果を確認（2026-05-16）。
- 補足:
  - Extension index (`META-INF/annotations/hudson.Extension.txt`) が生成されないと Jenkins 起動時に @Extension クラスが未発見になり全テスト失敗する。`target/classes` を削除して強制再コンパイルすることで解消。
  - `mvn compile && mvn test` はこの問題を引き起こすため NG。`mvn test` のみを使う。
  - Stale 自動解放なし（安全方向）。STALE_THRESHOLD_MS=60000ms、TERMINAL_TTL_MS=120000ms。
  - 永続化なし（Jenkins 再起動時は全レコードが消える）。
  - 2026-05-16 コードレビュー指摘を amend で修正:
    - `exposeLabel` 未設定時に全リソースを公開していたバグを修正（opt-in 設計に合わせ未設定=全拒否）
    - `heartbeatIntervalSeconds` のサーバー側バリデーション追加（≤0 または非整数 → 400 INVALID_HEARTBEAT_INTERVAL）
    - POST /acquire レスポンスを 200 → 202 Accepted に修正
    - エラーコードを RESOURCE_NOT_FOUND → UNKNOWN_RESOURCE に統一（LRR-DESIGN 準拠）
  - remoteApiEnabled=false 時のステータスは 403 を正とする（LRR-DESIGN-j.md も同日修正済み）

---

### 6. 最小 UI/可視化（M1 で必要な範囲のみ）

スコープ確定（2026-05-16）:
- **6a**: `clientId` を `POST /acquire` に追加（クライアント送信 + サーバー受信・保存 + 設定 UI）
- **6b**: B-side LR ページ表示（サーバー側 LR 一覧に `clientId` を表示）
- **6c**: System 設定 UI 拡張（server 側: exposeLabel / remoteApiEnabled、client 側: remotes 接続パラメータ）
- **6d**: 認証実装（`credentialsId` から username/password を解決し Authorization ヘッダ付与）

---

#### Step 6a: `clientId` 追加

目的:
- `POST /acquire` に送信元 Jenkins の識別子 `clientId` を持たせ、サーバー側でロック保有者を把握できるようにする。
- 管理者が明示設定できるフィールドを LRM に追加し、未設定時は `Jenkins.getRootUrl()` にフォールバックする。

実装内容:
- `RemoteLockRecord`: `clientId` フィールド追加（nullable）
- `RemoteLockManager.enqueue()`: シグネチャに `clientId` 追加
- `RemoteApiV1Action` (`POST /acquire`): `clientId` optional フィールドをパース・正規化・保存
- `RemoteApiClient.enqueueAcquire()`: `clientId` 引数追加、非 null 時のみリクエストボディに含める
- `LockableResourcesManager`: `clientId` 設定フィールド追加（`setClientId` / `getClientId` / `getEffectiveClientId`）、`readResolve()` に null 正規化追加
- `LockStepExecution`: `LockableResourcesManager.get().getEffectiveClientId()` を使用するよう変更
- `LockableResourcesManager/config.jelly`: "Remote Lockable Resources (Client)" セクションと `clientId` textbox 追加
- `LockableResourcesManager/config.properties`: UI ラベルキー追加
- `RemoteApiClientTest`: `enqueueAcquire()` 呼び出し箇所に `null` 引数追加
- `LRR-DESIGN-j.md`: `POST /acquire` 仕様・フロー図・セクション6 設定テーブルを更新

完了条件:
- `mvn test` が通る
- 設定 UI で `clientId` を入力・保存できる

- [x] 実装完了
- [x] `mvn test` 確認完了
- [x] コミット済み

記録:
- 日付: 2026-05-16
- コミット: ee1bb05
- 変更ファイル:
  - src/main/java/.../remote/RemoteLockRecord.java (編集)
  - src/main/java/.../remote/RemoteLockManager.java (編集)
  - src/main/java/.../actions/RemoteApiV1Action.java (編集)
  - src/main/java/.../remote/RemoteApiClient.java (編集)
  - src/main/java/.../LockableResourcesManager.java (編集: clientId フィールド追加)
  - src/main/java/.../LockStepExecution.java (編集: getEffectiveClientId() へ切替 + Jenkins import 削除)
  - src/main/resources/.../LockableResourcesManager/config.jelly (編集)
  - src/main/resources/.../LockableResourcesManager/config.properties (編集)
  - src/test/java/.../remote/RemoteApiClientTest.java (編集)
  - lrr-notes/dev/docs/LRR-DESIGN-j.md (編集)
- 確認結果: `mvn test` で BUILD SUCCESS（Tests run: 261, Failures: 0, Errors: 0, Skipped: 1, Total time: 13:05）。2026-05-16
- 補足: `getEffectiveClientId()` は `clientId` 設定が空なら `Jenkins.getRootUrl()` を返す（`@CheckForNull`）。UI は config.jelly に "Remote Lockable Resources (Client)" セクションを追加。

---

#### Step 6b: B-side LR ページ表示

目的:
- サーバー側 LR 一覧画面（Lockable Resources UI）に、remote lock 保有者の `clientId` を表示する。
- どの remote Jenkins がどのリソースをロックしているかを管理者が一目で把握できるようにする。

設計方針（確定）:
- 表示文字列: `Remote: <clientId>`（clientId が null の場合は `Remote: (unknown)`）
- データ取得: `LockableResource` に `getRemoteLockClientId()` メソッドを追加し、内部で `RemoteLockManager.get().find(remoteLockedBy)` を呼ぶ
- `remoteLockedBy` が null（remote lock なし）のときは通常の "Locked by" 表示に fallback

実装内容:
- `LockableResource`: `getRemoteLockClientId()` メソッド追加
- `LockableResource` の表示 jelly（`index.jelly` または `index.groovy`）: `remoteLockedBy != null` の場合に `Remote: clientId` を表示
- `LRR-DESIGN-j.md`: Step 6a でセクション 6 に B-side 表示設計を追記済み

完了条件:
- LR 一覧で remote lock 保有者が "Remote: clientId" として確認できる
- `clientId` が null の場合に "Remote: (unknown)" が表示される

- [x] 実装完了
- [x] `mvn test` 確認完了
- [x] コミット済み

記録:
- 日付: 2026-05-17
- コミット: 59d2709
- 変更ファイル:
  - src/main/java/.../LockableResource.java (編集: getRemoteLockClientId() 追加)
  - src/main/resources/.../LockableResourcesRootAction/tableResources/table.jelly (編集: remote lock ケース追加)
  - src/main/resources/.../LockableResourcesRootAction/tableResources/table.properties (編集: resource.status.remoteLockedBy キー追加)
- 確認結果: `mvn test` で BUILD SUCCESS（Tests run: 261, Failures: 0, Errors: 0, Skipped: 1, Total time: 12:52）。2026-05-17
- 補足:
  - `getRemoteLockClientId()`: `remoteLockedBy == null` なら null 即返し、そうでなければ `RemoteLockManager.get().find(remoteLockedBy)` でレコードを検索して `clientId` を返す。レコードなし（再起動後等）は null。
  - `table.jelly`: status コンテンツの `j:choose` で remote lock ケースを job-locked ケースより前に配置。`resource.remoteLockedBy != null` で分岐し、`remoteLockClientId` が null の場合は `(unknown)` にフォールバック。
  - CSS クラス選択の `j:choose` は変更なし（`resource.locked == true` が既に `warning` に当たる）。

---

#### Step 6c: System 設定 UI 拡張（server/client 設定）

目的:
- System 設定画面で、remote lock の server/client 基本設定を UI 経由で完結できるようにする。
- 現状 UI で露出していない `remoteApiEnabled` / `exposeLabel` / `remotes[]` を設定可能にし、手動 Groovy 依存を減らす。

対象スコープ（本ステップ）:
- server 側設定（LockableResourcesManager）
  - `remoteApiEnabled`（master switch）
  - `exposeLabel`（公開対象ラベル）
- client 側設定（LockableResourcesManager）
  - `remotes[]`
    - `serverId`
    - `url`
    - `credentialsId`

実装方針:
- `LockableResourcesManager/config.jelly` に Remote 設定セクションを再編追加
  - Server セクション: checkbox (`remoteApiEnabled`) + textbox (`exposeLabel`)
  - Client セクション: 既存 `clientId` を維持しつつ `remotes` repeatable を追加
- `LockableResourcesManager/config.properties` に UI ラベルキーを追加
- 必要に応じて help ファイルを追加
  - `help/remoteApiEnabled`
  - `help/exposeLabel`
  - `help/remotes`
  - `help/remotes/serverId`, `help/remotes/url`, `help/remotes/credentialsId`
- バリデーション方針
  - `RemoteConnection.validate()` の既存検証を尊重
  - `serverId` 重複は既存実装通り warning + last-entry-wins（将来 strict 化は別タスク）
  - `exposeLabel` 未設定時は opt-in 設計に合わせ「公開なし」を維持

完了条件:
- System 設定 UI で `remoteApiEnabled` / `exposeLabel` を入力・保存できる
- System 設定 UI で `remotes[]`（serverId/url/credentialsId）を追加・保存できる
- Jenkins 再起動後も設定が保持される
- `mvn test` が通る（少なくとも UI 変更に関連する既存テストは回帰なし）

- [x] 実装完了
- [x] `mvn test` 確認完了
- [x] コミット済み

記録:
- 日付: 2026-05-19
- コミット: 7e2d00e
- 変更ファイル:
  - src/main/resources/.../LockableResourcesManager/config.jelly (編集)
  - src/main/resources/.../LockableResourcesManager/config.properties (編集)
  - src/main/resources/.../LockableResourcesManager/help-remoteApiEnabled.html (新規)
  - src/main/resources/.../LockableResourcesManager/help-exposeLabel.html (新規)
  - src/main/resources/.../LockableResourcesManager/help-remotes.html (新規)
  - src/main/resources/.../RemoteConnection/config.jelly (新規)
  - src/main/resources/.../RemoteConnection/config.properties (新規)
  - src/main/resources/.../RemoteConnection/help-serverId.html (新規)
  - src/main/resources/.../RemoteConnection/help-url.html (新規)
  - src/main/resources/.../RemoteConnection/help-credentialsId.html (新規)
  - src/test/java/.../LockableResourcesManagerRemoteConnectionTest.java (編集: Global Configure round-trip テスト追加)
- 確認結果: 追加した `LockableResourcesManagerRemoteConnectionTest` を単体実行して成功（Tests run: 10, Failures: 0, Errors: 0, Skipped: 0）。その後、全件 `mvn test` でも BUILD SUCCESS（Tests run: 274, Failures: 0, Errors: 0, Skipped: 1, Total time: 13:37）。2026-05-19
- 補足:
  - System 設定 UI を server/client で整理し、server 側に `remoteApiEnabled` / `exposeLabel`、client 側に既存 `clientId` と `remotes[]` editor を配置。
  - `RemoteConnection` 用の設定断片と help を追加し、`serverId` / `url` / `credentialsId` を UI から編集可能にした。
  - UI submit 経由の回帰防止として Global Configure round-trip テストを 1 本追加した。既存の persistence test と合わせて保存・再読込経路を確認済み。

---

#### Step 6d: 認証実装（credentialsId 解決 + Authorization ヘッダ付与）

目的:
- `remotes[].credentialsId` を実際に解決し、remote API 呼び出し時に認証情報を送信できるようにする。
- 「credentialsId は保持するが未使用」の状態を解消し、M1 ゴールに合わせて peer mode の認証経路を成立させる。

対象スコープ（本ステップ）:
- client 側（LockStepExecution / RemoteApiClient 呼び出し経路）
  - credentials 解決
  - Authorization ヘッダ生成（Basic）
- エラー処理
  - credentials 未設定・未解決・型不一致・認証失敗時の fail-closed

実装方針:
- `LockStepExecution.resolveAuthorizationHeader()` を実装
  - Jenkins 全体の Credentials から `credentialsId` で `StandardUsernamePasswordCredentials` を解決する
  - `username:password` を Base64 エンコードして `Authorization: Basic ...` を生成
- 認証方式は Step 6d では Basic のみ対象とする
  - username/password または username/API token を同一の Basic Authorization として扱う
  - Secret text や Bearer token は本ステップのスコープ外とする
- `credentialsId` が空の場合
  - 既存方針どおり認証なし呼び出しを維持（サーバー設定次第で 403 → fail-closed）
- `credentialsId` 指定ありで解決失敗時
  - 明示的に `AbortException` で停止（誤設定の早期検知）
- `credentialsId` 指定ありで型不一致時
  - 明示的に `AbortException` で停止（`StandardUsernamePasswordCredentials` 以外は受け付けない）
- ログ方針
  - credentials 値は絶対に出力しない
  - `serverId` / `credentialsId`（識別子のみ） / 失敗理由カテゴリを出力
  - 401/403 は remote API 失敗として既存どおり fail-closed で build failure にする

完了条件:
- `credentialsId` 指定時に Authorization ヘッダ付きで remote API が呼ばれる
- 認証失敗（403 等）で fail-closed に build failure になる
- credentials 解決失敗時に意図したエラーで停止する
- `mvn test` が通る（関連テストを追加/更新）

- [x] 実装完了
- [x] `mvn test` 確認完了
- [x] コミット済み

記録:
- 日付: 2026-05-19
- コミット: plugin `c704822`, docs-j `6b8ebda`
- 変更ファイル:
  - src/main/java/.../LockStepExecution.java (編集: credentials 解決 + Authorization 生成)
  - src/main/java/.../remote/RemoteApiClient.java (必要に応じて編集)
  - src/test/java/.../LockStepRemoteTest.java (認証成功/失敗ケース追加)
  - src/test/java/.../remote/RemoteApiClientTest.java (Authorization ヘッダ送信検証追加)
- 確認結果:
  - `LockStepRemoteTest` / `RemoteApiV1ActionTest` / `RemoteApiClientTest` の対象実行が成功（Failures: 0, Errors: 0）。
  - 全件 `mvn test` ログ `dev/reports/20260519170441-mvn-test.log` で BUILD SUCCESS を確認（Tests run: 276, Failures: 0, Errors: 0, Skipped: 1）。
- 補足:
  - デバッグ中に発生した `missing descriptor` / `cannot find symbol` は並行実行や一時的な build state 不整合起因で、Step 6d 実装の不具合ではないことを切り分け済み。

---

#### Step 6e: errorCode 統一修正（`UNKNOWN_RESOURCE`）

目的:
- remote API 入口と内部遷移で不一致だった missing-resource の errorCode を統一し、運用時の判定とログ解釈を単純化する。

実装内容:
- `RemoteLockManager` 内の missing-resource 失敗コードを `RESOURCE_NOT_FOUND` から `UNKNOWN_RESOURCE` に統一
- 回帰防止として `RemoteLockManagerTest` を新規追加し、存在しない resource enqueue 時に `FAILED + UNKNOWN_RESOURCE` となることを固定

完了条件:
- plugin 側の修正がコミット済み
- 対象テストが成功している

- [x] 実装完了
- [x] 対象テスト確認完了
- [x] コミット済み

記録:
- 日付: 2026-05-23
- コミット: plugin `5acb822`
- 変更ファイル:
  - src/main/java/.../remote/RemoteLockManager.java (編集)
  - src/test/java/.../remote/RemoteLockManagerTest.java (新規)
- 確認結果:
  - `$HOME/.local/apache-maven-3.9.9/bin/mvn test -Dtest=RemoteLockManagerTest,RemoteApiV1ActionTest` を実行し成功（Tests run: 2, Failures: 0, Errors: 0, Skipped: 0）。

---

### 7. 正式テスト（plugin 側 / M1 の成立確認）

方針:
- plugin に入れるべきものだけをこのステップで扱う
- 対象は `lockable-resources-plugin/src/test/...` と `src/test/resources/...` に置く回帰防止テスト
- `mvn test` あるいは対象絞り込み付き `mvn test -Dtest=...` で再実行できる形を完了条件にする

目的:
- 回帰防止のため、M1 の核心を自動テストで固定する。

優先テスト:
- `serverId` ありの分岐
- `serverId` なし既存挙動の維持
- remote acquire 成功/失敗の代表ケース
- `RemoteApiV1Action` HTTP レベルテスト（サーバー側エンドポイントの直接固定）:
  - `remoteApiEnabled=false` のとき全エンドポイントが 403 を返すこと
  - `exposeLabel` 未設定のとき POST /acquire が 404 UNKNOWN_RESOURCE を返すこと
  - `exposeLabel` 設定済みで対象ラベルなしリソースへの acquire が 404 UNKNOWN_RESOURCE を返すこと
  - `heartbeatIntervalSeconds` に不正値（0、負数、文字列）を送ると 400 INVALID_HEARTBEAT_INTERVAL を返すこと
  - 正常な acquire リクエストが 202 と lockId を返すこと

対象リポジトリ:
- `lockable-resources-plugin`

想定配置:
- `src/test/java/.../RemoteApiV1ActionTest.java` または近接する HTTP レベルテスト
- `src/test/java/.../LockStep...Test.java` 系への remote 分岐ケース追加
- 必要に応じて `src/test/resources/...` の fixture 追加

完了条件:
- 追加テストが安定して通る
- 主要ケースが再現可能
- plugin 単体で CI に載せられる状態になっている

- [x] 実装完了
- [x] CI 相当のローカル実行で確認完了

記録:
- 日付: 2026-05-17
- コミット: f4b1ccb, 93ab6be, 2879e9a
- 変更ファイル:
  - src/test/java/.../actions/RemoteApiV1ActionTest.java (新規)
  - src/test/java/.../LockStepRemoteTest.java (新規)
  - src/test/java/.../actions/LockableResourcesRootActionTest.java (編集: Remote: clientId 正常表示テスト追加)
- 確認結果:
  - `$HOME/.local/apache-maven-3.9.9/bin/mvn test -Dtest=RemoteApiV1ActionTest` を実行し成功（Tests run: 1, Failures: 0, Errors: 0, Skipped: 0）。
  - `$HOME/.local/apache-maven-3.9.9/bin/mvn test -Dtest=LockStepRemoteTest` を実行し成功（Tests run: 6, Failures: 0, Errors: 0, Skipped: 0）。
  - `$HOME/.local/apache-maven-3.9.9/bin/mvn test -Dtest=LockableResourcesRootActionTest` を実行し成功（Tests run: 19, Failures: 0, Errors: 0, Skipped: 0）。
  - `$HOME/.local/apache-maven-3.9.9/bin/mvn test`（plugin 全体）を実行し成功（Tests run: 268, Failures: 0, Errors: 0, Skipped: 1）。
- 補足:
  - Step7 は着手済み。まず `RemoteApiV1Action` の代表契約を固定する回帰テストを追加した。
  - 現時点で固定した内容: `remoteApiEnabled=false` 時の 403、`exposeLabel` 制約による 404 `UNKNOWN_RESOURCE`、`heartbeatIntervalSeconds` 不正値による 400 `INVALID_HEARTBEAT_INTERVAL`、正常 acquire の 202 + `lockId`。
  - `LockStepRemoteTest` で `serverId` 指定時に remote 分岐へ入ること、`serverId` なしでは remote 設定が存在しても既存 local lock フローを維持することを固定した。
  - failure 系として、`serverId` に対応する remote 接続が未設定のケース、remote acquire status が `FAILED` を返すケース、`EXPIRED` を返すケース、`POST /acquire` の通信失敗ケースを追加し、body 未実行のまま build failure になることを固定した。
  - UI では `Remote: (unknown)` に加えて `Remote: clientId` の正常表示分岐も `LockableResourcesRootActionTest` で固定した。
  - 当初は JenkinsRule + HTTP 経由で組んだが、ローカル環境で Jetty の port bind が不安定だったため、action 直叩き + mocked Stapler に切り替えて安定化した。
  - `serverId` 分岐、既存 local 挙動維持、代表的な failure 系の最小回帰テストは追加済み。Step7 全体としては、必要に応じて heartbeat 中断や status poll 中の通信失敗などの拡張ケース追加を残している。
  - 2026-05-23 追記: Step6e の errorCode 統一修正後、`RemoteLockManagerTest,RemoteApiV1ActionTest` の対象実行が成功（Tests run: 2, Failures: 0, Errors: 0, Skipped: 0）。
  - 2026-05-23 追記: `./stabilize-build.sh` 再実行で全件 `mvn test` が成功（Tests run: 278, Failures: 0, Errors: 0, Skipped: 1, BUILD SUCCESS, Total time: 14:45）。ログ: `dev/reports/20260523075036-mvn-test.log`。

---

### 8. 自動 E2E（3 controller / 個人環境）

方針:
- 3 controller の検証は M1 の成立確認として必要だが、環境依存が強いため plugin 本体には入れない
- `lockable-resources-remote-notes` 側に、起動済み 8081/8082/8083 環境で再実行できる自動E2E資産を置く
- 実装方式は A 案に合わせて Java / shell / curl / Jenkins CLI など既存環境で回せるものを優先し、Playwright は使わない

目的:
- peer mode の最小成立を 3 controller 構成で自動再現できるようにする
- 実装後に同じ手順をコマンド一発で再実行できるようにする

対象リポジトリ:
- `lockable-resources-remote-notes`

実装候補:
- `dev/jenkins-env/` 配下に実行スクリプトと README を追加
- 各 controller へのジョブ投入、待機、結果確認、後片付けを自動化
- 必要なら `curl` ベースで remote API の生呼び出し確認も補助的に追加

事前方針決定（2026-05-18）:
- 認証方式: 当初は「匿名 READ 一時許可」で成立優先。
- 2026-05-23 更新: 認証必須 + API トークン方式へ移行（CSRF 403 を回避し、Step6d 実装に合わせる）。
- 実行責務: `run-e2e.sh` が `start.sh` を内包して起動まで実施（`--skip-start` オプションで既存起動環境も利用可）。
- 合格判定: Build 結果だけでなく、待機時間閾値とログキーワードを併用して誤判定を抑制。

完了条件:
- 3 controller E2E を一連で自動実行できる
- 成功時/失敗時の判定基準がスクリプト化されている
- ローカル環境依存の前提条件が `lockable-resources-remote-notes` 側に明記されている

- [x] 実装完了
- [x] ローカル自動実行で確認完了

記録:
- 日付: 2026-05-18（最終更新: 2026-05-23）
- コミット: 本コミットで反映
- 変更ファイル:
  - `dev/jenkins-env/run-e2e.sh`
  - `dev/jenkins-env/lib/common.sh`
  - `dev/jenkins-env/scenarios/peer-basic.sh`
  - `dev/jenkins-env/scenarios/fail-closed.sh`
  - `dev/jenkins-env/start.sh`
  - `dev/jenkins-env/stop.sh`
  - `dev/jenkins-env/docker-compose.yml`
  - `dev/jenkins-env/docker/init.groovy.d/00-init.groovy`
  - `dev/jenkins-env/README.md`
- 確認結果:
  - `./run-e2e.sh --skip-start --only peer-basic` が PASS（`dev/reports/20260518112121-e2e-test.md`）
  - `./run-e2e.sh --skip-start --only fail-closed` が PASS（`dev/reports/20260518112207-e2e-test.md`）
  - `PLUGIN_DIR=... ./run-e2e.sh --clean-start --only peer-basic` が PASS（`dev/reports/20260523100012-e2e-test.md`）
  - `PLUGIN_DIR=... ./run-e2e.sh --clean-start` が PASS（`dev/reports/20260523100138-e2e-test.md`, pass=2 fail=0）
- 補足:
  - 2026-05-18: Step8 着手。`dev/jenkins-env/` に `run-e2e.sh`（ハーネス）、`lib/common.sh`（共通関数）、`scenarios/*.sh`（正常系/異常系の初版雛形）を追加。現時点のシナリオ本体は TODO として `SKIP` を返す。
  - 2026-05-18: シナリオ本体を実装。`peer-basic` は 8081 holder / 8083 waiter の待機検証（SUCCESS + 待機時間閾値 + ログ確認）、`fail-closed` は remote down / timeout / auth error の 3 ケースを自動実行し、body 未実行を確認する構成に更新。現時点では文法/ヘルプ確認まで実施し、ローカルフル実行は次フェーズ。
  - 2026-05-18: 実行結果保存先を `dev/reports/` に統一。`run-e2e.sh` 実行ごとに `yyyymmddhhmmss-e2e-test.md`（サマリ）と `yyyymmddhhmmss-e2e-test/`（console log / case summary / 手動キャプチャ格納先）を生成する。
  - 2026-05-18: `RemoteApiV1Action` の `/acquire` ルーティングを整理（`POST /acquire` と `GET /acquire/{lockId}` の競合回避）。
  - 2026-05-18: Stapler の 302 正規化（末尾 `/`）で lockId 解析が壊れる問題を回避するため、`RemoteApiClient` の acquire 系パスを canonical path に修正。
  - 2026-05-18: scenario 側は run ごとにユニークな resource 名を使うように変更し、stale state 干渉を抑制。
  - 2026-05-18: レポートに Scenario Details（Sequence + Checkpoints）を追加。各チェックポイントに API/Action・Expected・Actual・Result を出力するよう更新。
  - 2026-05-18: Scenario Details の markdown table 崩れを修正（Sequence と Checkpoints を分離生成して最終合成）。
  - 2026-05-18: レポート本文を英語化（Summary/Scenario details/checkpoint descriptions）。
  - 2026-05-18: plugin 側修正をコミット（`3d5fddf`）: `RemoteApiV1Action` の acquire ルーティング整理、`RemoteApiClient` の acquire path canonical 化、対応テスト更新。
  - 2026-05-23: compose service/container 名を `jenkins-8081/2/3` から `jenkins-a/b/c` へ変更し、`common.sh` / `start.sh` / `fail-closed.sh` / `README.md` の参照先も追従。
  - 2026-05-23: `peer-basic` の 403 を切り分け。Controller B ログで `No valid crumb was included ... /remote/v1/acquire/ ... Returning 403` を確認。
  - 2026-05-23: E2E ハーネスを API トークン運用へ変更。Controller B の `admin` API token をシナリオで発行し、Controller A/C の username/password credentials（password 側）に設定して Basic 認証で remote API を呼び出す形へ更新。
  - 2026-05-23: `dev/docs-j/E2E_TEST_SPECIFICATION.md` / `dev/docs-e/E2E_TEST_SPECIFICATION.md` を更新し、認証必須（APIトークン）/ fail-closed 5ケース / compose 命名（a/b/c）へ内容更新。

E2E 確認チェック（3 controller）:
- [x] 8081 -> 8082 の remote lock が取得できる
- [x] 8083 から同一 resource を叩くと待機/拒否の期待挙動になる
- [x] release 後に待機側が進む
- [x] 異常系（remote down, timeout, auth error）で fail-closed になる

Step8 最終状態（2026-05-23）:
- 認証必須 + API トークン方式で E2E が安定実行可能
- S/D 拡張後のフル実行結果: pass=10 fail=0 skip=0（`dev/reports/20260523133947-e2e-test.md`）

#### 2026-05-23 追記（M1: S/D シリーズ拡張実装）

- 既存 `peer-basic` を廃止し、`E2E_TEST_SPECIFICATION.md` の設計に合わせて 10 シナリオ構成へ拡張した。
  - S 系: `mutual-peer`, `fan-in-contention`, `server-self-use`, `mixed-local-remote`, `skip-if-locked`, `three-way-mesh`, `fail-closed`
  - D 系: `fan-in-4`, `chain-4`, `diamond`
- `run-e2e.sh` の `--only` を拡張し、個別シナリオ名に加えて `s-series` / `d-series` / `all` を選択可能にした。
- `lib/common.sh` を汎用化し、任意 `serverId` 向け remote 設定関数と 4 controller 待機関数を追加した。
- `docker-compose.yml` に `jenkins-d`（8084）を追加した。
- `fail-closed` は S07 命名規約へ更新した（credentials/job 名の `s07-*` 化）。

この時点の変更ファイル（拡張分）:
- `dev/jenkins-env/run-e2e.sh`
- `dev/jenkins-env/lib/common.sh`
- `dev/jenkins-env/docker-compose.yml`
- `dev/jenkins-env/README.md`
- `dev/jenkins-env/start.sh`
- `dev/jenkins-env/stop.sh`
- `dev/jenkins-env/scenarios/fail-closed.sh`
- `dev/jenkins-env/scenarios/mutual-peer.sh`
- `dev/jenkins-env/scenarios/fan-in-contention.sh`
- `dev/jenkins-env/scenarios/server-self-use.sh`
- `dev/jenkins-env/scenarios/mixed-local-remote.sh`
- `dev/jenkins-env/scenarios/skip-if-locked.sh`
- `dev/jenkins-env/scenarios/three-way-mesh.sh`
- `dev/jenkins-env/scenarios/fan-in-4.sh`
- `dev/jenkins-env/scenarios/chain-4.sh`
- `dev/jenkins-env/scenarios/diamond.sh`
- `dev/jenkins-env/scenarios/peer-basic.sh`（削除）

拡張分の検証ステータス（2026-05-23 時点）:
- [x] スクリプト文法チェック（`bash -n`）
- [x] `run-e2e.sh --help` で新オプション表示確認
- [x] `--only s-series` 実行確認
- [x] `--only d-series` 実行確認
- [x] `--only all` 実行確認

追加デバッグ（2026-05-23）:
- S04 `mixed-local-remote` で初回失敗を確認。
  - 原因1: ローカルリソースが存在しないケースで `isLocked()` を直接呼び、NullPointerException 相当の誤判定が発生。
  - 対応1: `EXISTS`/`LOCKED` の2値を取得し、`LOCKED=false` を条件とする判定へ修正。
- S04 再実行時に credentials 再作成で失敗。
  - 原因2: `provider.getCredentials().removeAll { ... }` が `CopyOnWriteArrayList` 環境で `UnsupportedOperationException`。
  - 対応2: `SystemCredentialsProvider#getStore()` + `Domain.global()` の add/remove API に置換。
- D 系は当初 SKIP（`jenkins-d` 再起動ループ）。
  - 原因3: `jhd/` が root 所有になり `copy_reference_file.log` 書き込み不可。
  - 対応3: `start.sh`/`stop.sh` を 4 controller 前提へ更新し、`jhd` 作成と Docker 経由 `chown -R 1000:1000` を追加。

拡張分の実行確認結果:
- `PLUGIN_DIR=../../../lockable-resources-plugin ./run-e2e.sh --clean-start --only s-series`
  - 初回: pass=6 fail=1 skip=0（S04 失敗）
- `./run-e2e.sh --skip-start --only s-series`
  - 修正後: pass=7 fail=0 skip=0
- `./run-e2e.sh --skip-start --only d-series`
  - 修正後: pass=3 fail=0 skip=0
- `./run-e2e.sh`
  - 最終: pass=10 fail=0 skip=0（report: `dev/reports/20260523133947-e2e-test.md`）

今回のデバッグで plugin 側不具合は未検出。
検出・修正したのは `lockable-resources-remote-notes` 側 E2E ハーネス/環境起動スクリプトの問題。

フォローアップ結果（2026-05-23）:
1. report 差分確認とコミットは完了（notes: `1ac2932`）
2. `./run-e2e.sh` のフル実行レポートを最新版として採用し、`--clean-start --only all` の再取得は任意扱いへ整理
3. Step9 の完了条件を README / E2E spec / 本手順書で満たしていることを確認し、本節へ反映

---

### 9. テスト運用資産の整備（notes 側）

方針:
- plugin 側テストを補完する個人運用資産は `lockable-resources-remote-notes` に置く
- M1 完了後も再利用できるよう、実行順序・コマンド・前提条件を文書化する

目的:
- Step7 と Step8 の実行方法を迷わない状態にする
- 将来 M2 以降でも使い回せる最小運用資産を残す

対象リポジトリ:
- `lockable-resources-remote-notes`

実装候補:
- `dev/docs/` にテスト実行手順メモを追加
- `dev/jenkins-env/` の README または run スクリプトを整備
- plugin 側の推奨実行コマンドを notes に集約

完了条件:
- Step7 / Step8 の実行入口が notes 側で整理されている
- 新しい環境でも追従しやすいよう前提条件・既知制約が書かれている

- [x] 実装完了
- [x] 内容見直し完了

記録:
- 日付: 2026-05-23
- コミット: notes `1ac2932`
- 変更ファイル:
  - `dev/jenkins-env/README.md`
  - `dev/docs-j/E2E_TEST_SPECIFICATION.md`
  - `dev/docs-e/E2E_TEST_SPECIFICATION.md`
  - `dev/docs-j/LRR_IMPLEMENTATION_STEPS_P1_M1.md`
  - `dev/docs-e/LRR_IMPLEMENTATION_STEPS_P1_M1.md`
- 確認結果:
  - Step7 の実行入口と `mvn test` 安定化手順は本ファイル内に整理済み
  - Step8 の実行入口・前提条件・`--only` オプション・レポート出力先は `dev/jenkins-env/README.md` と `E2E_TEST_SPECIFICATION.md` に整理済み
  - 既知制約と復旧手順（descriptor 欠落、target 再生成、clean worktree 切り分け）は本ファイル内に整理済み
- 補足:
  - Step9 は新規の専用運用文書を増やすのではなく、既存の README / E2E spec / 実装手順書へ入口と前提条件を集約する形で完了とした
  - M1 スコープ上の残件は解消済み。以後は M2 以降の検討事項のみ

---

## テスト実行の整理（M1時点の確定方針）

1. Step7 は `lockable-resources-plugin` に入る正式テスト
2. Step8 は `lockable-resources-remote-notes` に置く個人環境向け自動E2E
3. Step9 は Step7/8 を回すための運用資産整備
4. plugin 側に入れない理由が「環境依存」だけなら Step8/9 へ送る
5. 将来 upstream に残したい検証はまず Step7 で検討する

## `mvn test` 異常時の運用手順（初心者向け）

### 背景（今回の学び）

- `LockableResourcesManager is missing its descriptor` が大量に出ても、必ずしもコード回帰とは限らない。
- 同一 commit でも、`target/` などの生成物状態が崩れていると JenkinsRule 系テストが雪崩式に失敗する。
- 比較検証はクリーンな worktree で実行しないと、bisect 判定が偽陽性になることがある。

### まずやること（最短復旧）

1. 作業ツリー状態を確認する。
2. `target/` を消して再生成する。
3. 代表 JenkinsRule テストを先に実行する。
4. 問題が消えたら全件 `mvn test` を実行する。

実行例:

```bash
cd /home/ksato/projects/jenkins/remote-lr/lockable-resources-plugin
git status --short
rm -rf target
$HOME/.local/apache-maven-3.9.9/bin/mvn test -Dtest=org.jenkins.plugins.lockableresources.actions.LockableResourcesRootActionTest
$HOME/.local/apache-maven-3.9.9/bin/mvn test
```

### 切り分け（回帰か環境か）

1. 同じ commit をクリーン worktree に展開する。
2. そこで `mvn test` を実行する。
3. クリーン worktree で成功するなら、まず環境/生成物問題として扱う。
4. クリーン worktree でも失敗するなら、コード回帰として差分解析に進む。

実行例:

```bash
git worktree add -f /tmp/lr-check <commit-hash>
cd /tmp/lr-check
$HOME/.local/apache-maven-3.9.9/bin/mvn test
```

### 今後の固定ルール（再発防止）

1. bisect は各ステップをクリーン worktree で実行する。
2. `mvn test` 失敗時は、先に `target/` 再生成で再試行してから回帰判定する。
3. 長時間テストは途中中断を避ける（中断後は `target/` 再生成して再実行）。
4. 失敗の一次判断は surefire レポート（`target/surefire-reports/*.txt`）で行う。
5. 「大量同時失敗 + 起動初期化エラー」は、個別テスト不良より環境不整合を先に疑う。

## 最終版 安定化手順（M1 確定）

### 前提条件
- WSL または Linux 環境で bash を使用
- Maven 3.9.9 が `$HOME/.local/apache-maven-3.9.9/bin/mvn` に存在

### 手順

#### 1. Maven 多重実行の停止
```bash
pkill -f "mvn" || true
```

#### 2. 作業ディレクトリのリセット
```bash
cd /home/ksato/projects/jenkins/remote-lr/lockable-resources-plugin
rm -rf target
```

#### 3. Extension インデックス生成確認
```bash
$HOME/.local/apache-maven-3.9.9/bin/mvn -DskipTests test-compile
ls target/classes/META-INF/annotations
```

**確認ポイント**: `hudson.Extension` と `hudson.Extension.txt` が見えることを確認。

#### 4. 本テスト実行
```bash
$HOME/.local/apache-maven-3.9.9/bin/mvn test
```

**期待結果**: `Tests run: 278, Failures: 0, Errors: 0, Skipped: 1, BUILD SUCCESS`

### トラブルシューティング

**症状1**: Step 3 で `hudson.Extension` ファイルが見えない
- **原因**: Maven キャッシュが破損している可能性
- **対処**:
  ```bash
  rm -rf ~/.m2/repository/org/jenkins-ci/tools/maven-hpi-plugin/3.1814.v77d15159f9b_d
  $HOME/.local/apache-maven-3.9.9/bin/mvn -U -DskipTests test-compile
  ls target/classes/META-INF/annotations
  ```

**症状2**: テスト実行時に `cannot find symbol` で main classes が見えない
- **原因**: ビルド生成物の状態不整合（通常は一時的）
- **対処**: WSL を再起動した後に Step 2 から再開

**症状3**: `LockableResourcesManager is missing its descriptor` エラー多発
- **原因**: Extension インデックスの欠落（descriptor 登録失敗）
- **対処**: Step 3 の Extension インデックス確認に戻る。Step 1 で並列実行中の Maven がないことを確認

### 注記
- maven-hpi-plugin の POM キャッシュ警告は出ていても、テスト成立を妨げない場合がある
- 初回実行時は 14 分程度かかる（以後は incremental キャッシュで高速化）
- Skipped: 1 は既知バグ（JENKINS-40787 / GitHub #861）による `LockStepInversePrecedenceTest#lockInverseOrderWithLabel` スキップ

## コミット運用ルール（この作業向け）

- 1ステップ 1コミットを基本とする
- コミットメッセージは命令形で簡潔に書く
- ステップ跨ぎの変更は避ける
- 仕様変更が入ったらこのファイルのステップ定義も更新する

## 2026-06-10〜11 追記: master rebase 対応（m1a ブランチ）とビルド/起動安定化

PR #1035 が upstream にマージされ master が更新されたことを受け、M1 を現行 master へ追従させた `feature/1025-remote-lockable-resources-p1-m1a` を整備した。あわせて、作業中に顕在化したローカルビルド/起動の不安定要因（VS Code Java 拡張と `target/` の競合）を恒久対策した。

### 経緯

1. **rebase 前提の確定（2026-06-10）**
   - upstream で PR #1035（Manage Jenkins ページ刷新）がマージされ、`origin/master` が #1035 を含む `863ea4d` に更新。
   - M1 ブランチ `feature/1025-remote-lockable-resources-p1-m1`（旧 master `739d6da` ベース）はそのままでは設定画面 / LR テーブル UI で conflict する状態。

2. **m1a ブランチ作成**
   - 2026-06-09 に用意済みだった現 master への rebase 済みブランチ（M1 の 14 コミットを再適用したもの）を起点に `feature/1025-remote-lockable-resources-p1-m1a` を作成。
   - conflict 解消内容を検証: #1035 で再構成された status 列の `j:choose` に remote lock（`remoteLockedBy`）分岐を統合する妥当な内容で、M1 版との差分は `tableResources/table.jelly` と `table.properties` の 2 ファイルのみ。機能差なしと確認。

3. **テスト追従修正（plugin `e8b8431`）**
   - `Remote: clientId` 表示の UI テスト 2 件（`LockableResourcesRootActionTest`）が失敗。
   - 切り分けの結果、製品コードは正常で（配信 HTML に `LOCKED by Remote: client-jenkins-a` が描画済み）、#1035 のタブ UI でリソーステーブルが非アクティブタブへ移ったため `asNormalizedText()`（可視テキストのみ）に含まれなくなったことが原因と判明。
   - アサーションを `page.getWebResponse().getContentAsString()`（配信 HTML）に変更。全件 `mvn test` で 326 件 BUILD SUCCESS（Skipped 1 は既知バグ JENKINS-40787）。

4. **ビルド不安定の根本原因特定**
   - `mvn test` / hpi ビルドの連続失敗（クラスファイル消失、Extension index 欠落、surefire の「Unresolved compilation problems」）は、VS Code の Java 拡張（jdt.ls）が CLI Maven と同じ `target/` に ECJ コンパイル結果を書き込む競合が原因と確定。

5. **stabilize-build.sh の改修（notes `0786ae3` / レポート `a7ee167`）**
   - デフォルトを「plugin HEAD の隔離 worktree（`/tmp` 配下）でビルド」に変更し、jdt.ls 競合を恒久回避。リポジトリ直下ビルドは `--in-place`（Java 拡張停止が前提）。失敗時は調査用に worktree を保持。期待テスト件数を 271 → 326 に更新。
   - 改修後のフル実行で BUILD SUCCESS（326 件）。ログ: `dev/reports/20260610231428-mvn-test.log`。

6. **start.sh 起動障害の修正（2026-06-11、notes `11668d9`）**
   - `PLUGIN_DIR=../../../lockable-resources-plugin ./start.sh --clean` で Jenkins が「起動待ち」ページのままハングする事象が発生。
   - 原因は同じ jdt.ls / `target/` 競合で生成された壊れた hpi。内部 jar に `META-INF/annotations`（Extension index）が無く、`@Extension` が一切登録されず（`LockableResourcesManager` の descriptor 不在）起動時 initializer が失敗していた。
   - 対策: start.sh の hpi ビルドもデフォルトで隔離 worktree 化（`--in-place-build` で従来動作）。さらに Docker イメージへ焼き込む前に hpi 内の Extension index を検証するガードを追加し、壊れた hpi はエラーで停止するようにした。
   - 4 コントローラの起動（`--clean` / 通常）・停止・再起動を検証し、4 台とも `lockable-resources` が active・SEVERE ログ 0 件を確認。

### この経緯で追加 / 変更したコミット

- plugin `feature/1025-remote-lockable-resources-p1-m1a`: `e8b8431`（テストを #1035 タブ UI に追従）
- notes `main`: `0786ae3`（stabilize-build.sh を worktree ビルド化）/ `a7ee167`（m1a の mvn test レポート追加）/ `11668d9`（start.sh を worktree ビルド化 + hpi 検証）

## 現在ステータス

- 開始日: 2026-05-09
- **plugin 側 M1 実装: Step 0〜8 完了 ✅**（最終確認: 2026-05-23、plugin HEAD `5acb822`、`./stabilize-build.sh` 経由で `mvn test` BUILD SUCCESS / 278件 / Failures: 0 / Errors: 0 / Skipped: 1）
- **notes 側運用資産: Step 9 完了 ✅**（2026-05-23、README / E2E spec / 本手順書の同期完了）
- **テスト安定化: 最終版手順 確定済み ✅**（2026-05-23、再実行で BUILD SUCCESS を確認）
- **最新レポート更新済み ✅**（2026-05-24、`PLUGIN_DIR=../../../lockable-resources-plugin ./run-e2e.sh` 成功、ログ/レポートを更新）
- **master rebase 対応（m1a ブランチ）完了 ✅**（2026-06-10、`feature/1025-remote-lockable-resources-p1-m1a`、HEAD `e8b8431`、全 326 件 BUILD SUCCESS）
- **ローカルビルド/起動の安定化完了 ✅**（2026-06-10〜11、stabilize-build.sh と start.sh を隔離 worktree ビルド化、起動/停止/再起動を検証）
- 次アクション: m1a を push（未実施）。M1 PR 作成 もしくは M1A 実装着手の判断
- ブロッカー: 解消済み（PR #1035 はマージ済み、conflict 解消済み）
- 最新ビルド: `dev/reports/20260610231428-mvn-test.log`（BUILD SUCCESS / 326 件）
- 最新E2E: `dev/reports/20260524105443-e2e-test.md`（pass=10 fail=0 skip=0）

### ブランチ整理メモ

- M1 PR ベースブランチは `feature/1025-remote-lockable-resources-p1-m1`（upstream/master ベース、cherry-pick なし）
- 旧ブランチ `feature/1025-remote-lockable-resources-p1-m1-old` は削除予定（履歴比較用に一時退避）
- notes 側の M1 同期コミットは `1ac2932`、`.gitignore` 整理は `037e395`
- 2026-05-24: notes 側ステータス同期コミット `56563d9`（手順書文言同期 + 最新テストレポート差し替え）
- issue #1025 に「#1035 マージ待ち → master 基準で conflict 解消後に PR」をコメント済み
- 2026-06-10: 現行 master（#1035 含む `863ea4d`）へ追従した `feature/1025-remote-lockable-resources-p1-m1a` を整備（M1 と同一機能、rebase 済み 14 コミット + テスト追従 `e8b8431`）。m1a が M1A 実装の起点ブランチ。
- 関連ブランチ: `origin/feature/1025-remote-lockable-resources-p1-m1-rebased`（m1a の起点、2026-06-09 作成）/ `feature/1025-remote-lockable-resources-p1-m1`（旧 master ベースの M1）は履歴として残置
