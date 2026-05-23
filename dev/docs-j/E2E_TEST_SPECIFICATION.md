# E2E テスト仕様

この文書は、`dev/jenkins-env/run-e2e.sh` が実行している E2E テストの内容を整理したものです。

## 目的

この E2E ハーネスは、lockable-resources-plugin の remote lock 機能について次を確認します。

1. remote server から resource を取得し、別 controller で待機できること
2. Step 6d で実装した `credentialsId` 解決 + Basic Authorization（password 欄に API トークン）経路が実環境相当で成立すること
3. remote API が失敗したときに lock を自動解放せず、fail-closed で失敗すること
4. 実行結果とコンソールログを再現可能な形で保存できること

## 実行単位

`run-e2e.sh` は 3 台の Jenkins controller を Docker Compose で扱う前提です。

- 8081: holder 側の controller
- 8082: remote server 側の controller
- 8083: waiter 側の controller

スクリプトは以下の順で動きます。

1. 必要コマンドを確認する
2. 必要に応じて `start.sh` で controller を起動する
3. 3 台の Jenkins が `/login` で応答するまで待つ
4. `peer-basic` と `fail-closed` を順に実行する
5. `dev/reports/<runId>-e2e-test.md` にサマリを出力する

## 起動条件

### 必須コマンド

`run-e2e.sh` は次を要求します。

- `curl`
- `docker`
- `python3`
- `base64`

### `PLUGIN_DIR`

`--skip-start` を使わない場合、`PLUGIN_DIR` が必須です。

- `PLUGIN_DIR` は `start.sh` に渡され、lockable-resources-plugin のソース位置を示します
- `--skip-start` の場合は既存の Jenkins 環境を使うため、`PLUGIN_DIR` は不要です

### オプション

- `--skip-start`: `start.sh` を呼ばずに既存環境で実行する
- `--clean-start`: `start.sh --clean` で Jenkins home を初期化してから実行する
- `--only peer-basic`: `peer-basic` のみ実行する
- `--only fail-closed`: `fail-closed` のみ実行する

`--skip-start` と `--clean-start` は同時に使えません。

## 共通の実行前処理

`run-e2e.sh` が `start.sh` を呼ぶ場合、`start.sh` は次を行います。

1. lockable-resources-plugin を `mvn package -DskipTests` でビルドする
2. 生成された `.hpi` を Docker ビルドコンテキストへコピーする
3. Jenkins home ディレクトリを用意する
4. Docker イメージをビルドする
5. 3 つの controller を起動する
6. 各 controller の `/jenkins/login` 応答を確認する

`run-e2e.sh` 側では、さらに `wait_for_controllers 240` により 240 秒まで controller の起動完了を待ちます。

## シナリオ一覧

| シナリオ | 目的 | 判定 |
|---|---|---|
| `peer-basic` | 認証必須の remote lock 取得・待機・解放の基本動作を確認する | holder と waiter がどちらも `SUCCESS`、waiter が十分待機すること |
| `fail-closed` | remote API 障害時に自動解放されないことを確認する | 5 ケースすべてで build が `FAILURE`、lock body が実行されないこと |

## `peer-basic` の仕様

このシナリオは、remote lock の通常経路を確認します。

### 1. controller B を認証必須の remote server に設定する

controller B では次を設定します。

- SecurityRealm を `HudsonPrivateSecurityRealm` にする
- AuthorizationStrategy を `FullControlOnceLoggedInAuthorizationStrategy` にする（anonymous read は無効）
- CrumbIssuer を有効化する
- `LockableResourcesManager.remoteApiEnabled` を `true` にする
- `LockableResourcesManager.exposeLabel` を `remote-enabled` にする
- `remote-enabled` ラベル付きの resource を作成する

この状態で、controller B は remote API の提供側になります。

### 2. controller A/C に資格情報を作成し、remote client を設定する

controller A と C には、`credentialsId=step8-peer-basic-auth` の username/password 資格情報を自動作成します。

- username: `admin`
- password: controller B の `admin` ユーザー用 API トークン（シナリオ内で発行）

controller A と C は、同じ remote server として controller B を参照します。

- clientId はそれぞれ `jenkins-a`、`jenkins-c`
- remote connection の serverId は `b`
- remote URL は `http://jenkins-b:8080/jenkins`
- remote connection の credentialsId は `step8-peer-basic-auth`

設定後、`verify_remote_client_config` で clientId / remoteUrl / credentialsId が一致することを確認します。

### 3. pipeline job を作る

2 つの Pipeline job を作成します。

- `step8-peer-holder` を controller A に作成する
- `step8-peer-waiter` を controller C に作成する

どちらも `lock(resource: ..., serverId: "b")` を使います。

- holder 側は 25 秒 sleep して resource を保持する
- waiter 側は lock 取得後に 1 秒 sleep する

### 4. holder build を実行する

holder build を起動したあと、`HOLDER_ACQUIRED` が 120 秒以内にコンソールへ現れることを確認します。

ここでの判定は、remote acquire が成功して lock を取得できたかどうかです。

### 5. waiter build を実行する

waiter build を起動し、次を確認します。

- holder build が `SUCCESS`
- waiter build が `SUCCESS`
- waiter の実行時間が 15 秒以上であること
- waiter コンソールに `WAITER_ACQUIRED` が出ること

15 秒以上を条件にしているのは、holder が保持中に waiter が待機したことを見たいからです。

### 6. 追加のログ確認

holder コンソールには、remote lock のライフサイクルを示す次の文言が残っていることを確認します。

- `Remote acquire enqueued`
- `Remote lock acquired on`
- `Remote lock released on`

これは必須判定ではなく、出ていれば補助的な証跡として記録されます。欠けていても WARN 扱いです。

### `peer-basic` の出力

次のファイルが生成されます。

- `dev/reports/<runId>-e2e-test/peer-basic/holder-console.txt`
- `dev/reports/<runId>-e2e-test/peer-basic/waiter-console.txt`
- `dev/reports/<runId>-e2e-test/peer-basic/summary.txt`
- `dev/reports/<runId>-e2e-test/peer-basic/scenario-details.md`

`scenario-details.md` には、実行順序、チェックポイント、アーティファクト一覧がまとまります。

## `fail-closed` の仕様

このシナリオは、remote API の通信失敗や認証失敗時に lock body を実行せず、build を失敗させることを確認します。

### 共通の前提

まず controller B を認証必須の remote server として、controller A を credentials 付き remote client として設定します。

controller A には、`credentialsId=step8-fail-valid-creds`（`admin` + controller B の API トークン）を作成して baseline に使います。

このベース状態は各ケースの前に再利用されます。

### lock body

失敗系の Pipeline job では、次の body を使います。

- `lock(resource: ..., serverId: "b")` の中で `UNEXPECTED_BODY_EXECUTION` を出力する

つまり、もし lock body が実行されたらログに明確な痕跡が残ります。

### ケース 1: remote-down

controller B を `docker compose stop jenkins-b` で停止し、remote API が到達不能な状態を作ります。

期待結果は次のとおりです。

- build 結果は `FAILURE`
- コンソールに通信失敗系の痕跡が出る
- `UNEXPECTED_BODY_EXECUTION` が出ない

### ケース 2: timeout

controller A の remote URL を `http://10.255.255.1:18082/jenkins` に差し替え、タイムアウトを起こします。

期待結果は次のとおりです。

- build 結果は `FAILURE`
- コンソールに timeout 系の痕跡が出る
- `UNEXPECTED_BODY_EXECUTION` が出ない

### ケース 3: auth-error

controller A 側で `credentialsId=step8-fail-invalid-auth-creds`（`admin/not-a-valid-api-token`）を作成し、意図的に認証失敗を起こします。

期待結果は次のとおりです。

- build 結果は `FAILURE`
- コンソールに HTTP 401/403 または認証失敗系の痕跡が出る
- `UNEXPECTED_BODY_EXECUTION` が出ない

### ケース 4: missing-credentials-id

controller A の remote connection に存在しない `credentialsId`（`step8-fail-missing-creds`）を設定し、credentials 解決失敗を起こします。

期待結果は次のとおりです。

- build 結果は `FAILURE`
- コンソールに `Remote credentials not found for serverId=b, credentialsId=...` が出る
- `UNEXPECTED_BODY_EXECUTION` が出ない

### ケース 5: credentials-type-mismatch

controller A で secret text credential（`StringCredentialsImpl`）を作成し、その ID（`step8-fail-type-mismatch-creds`）を remote connection に設定します。

`LockStepExecution.resolveAuthorizationHeader()` は `StandardUsernamePasswordCredentials` のみ受け付けるため、型不一致で fail-fast します。

期待結果は次のとおりです。

- build 結果は `FAILURE`
- コンソールに `Remote credentials not found for serverId=b, credentialsId=...` が出る
- `UNEXPECTED_BODY_EXECUTION` が出ない

### `fail-closed` の出力

各ケースごとに次のファイルが生成されます。

- `dev/reports/<runId>-e2e-test/fail-closed/remote-down/console.txt`
- `dev/reports/<runId>-e2e-test/fail-closed/timeout/console.txt`
- `dev/reports/<runId>-e2e-test/fail-closed/auth-error/console.txt`
- `dev/reports/<runId>-e2e-test/fail-closed/missing-credentials-id/console.txt`
- `dev/reports/<runId>-e2e-test/fail-closed/credentials-type-mismatch/console.txt`
- `dev/reports/<runId>-e2e-test/fail-closed/<case>/summary.txt`
- `dev/reports/<runId>-e2e-test/fail-closed/scenario-details.md`

## レポート仕様

`run-e2e.sh` の最後に、次の要約レポートが生成されます。

- `dev/reports/<runId>-e2e-test.md`

レポートには次が含まれます。

- 実行 ID
- 実行日時
- 実行モード
- `--skip-start` / `--clean-start` の設定
- 成功数、失敗数、スキップ数
- シナリオ別の状態
- シナリオ詳細の本文

## 終了コード

- すべてのシナリオが成功した場合: 0
- 1 つでも失敗した場合: 1
- シナリオスキップは `run_scenario` で exit code 10 として扱う

## 補足

- `--only` を使うと、個別シナリオの切り分けができます
- `--skip-start` は既存の Jenkins 環境があるときの短縮実行に向いています
- `--clean-start` は Jenkins home を初期化したいときに使います
- ログやコンソール出力の保存先はすべて `dev/reports/` にまとまります

## 更新履歴

- 2026-05-23: Step 6d の検証を E2E に統合。`peer-basic` を認証必須前提へ切替え、`fail-closed` に `missing-credentials-id` / `credentials-type-mismatch` を追加して認証失敗ケースを拡張。
