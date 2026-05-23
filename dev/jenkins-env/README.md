# lockable-resources-plugin Docker 開発環境

Jenkins 3 コントローラー（ポート 8081/8082/8083）を Docker Compose で起動し、
remote lock 機能の統合テストを行うための開発環境です。

## 前提条件

- Docker（`docker compose` コマンドが使えること）
- JDK 17 以上
- Maven（`$HOME/.local/apache-maven-3.9.9/bin/mvn` があればそちらを優先、なければ `mvn`）

## ディレクトリ構成

```
jenkins-env/
├── README.md               このファイル
├── docker-compose.yml      3 コントローラー定義
├── start.sh                ビルド＆起動スクリプト
├── stop.sh                 停止スクリプト
├── .gitignore
├── docker/
│   ├── Dockerfile
│   ├── plugins.txt         依存プラグイン一覧
│   └── init.groovy.d/
│       └── 00-init.groovy  admin ユーザー自動作成（dev only）
├── lockable-resources-plugin/   ← プラグインのソース（後述）
├── jha/                    Jenkins home（自動生成、.gitignore 対象）
├── jhb/
└── jhc/
```

## セットアップ

### 1. プラグインのソースを用意する

`lockable-resources-plugin` のソースを `jenkins-env/` と同じ場所に用意します。
方法は以下のいずれかです。

**A. 直接 clone する（推奨）**

```bash
cd path/to/jenkins-env
git clone https://github.com/jenkinsci/lockable-resources-plugin.git
```

**B. シンボリックリンクを張る**

すでに別の場所に clone 済みの場合：

```bash
cd path/to/jenkins-env
ln -s /path/to/your/lockable-resources-plugin lockable-resources-plugin
```

**C. 環境変数で場所を指定する**

```bash
# 絶対パス
PLUGIN_DIR=/path/to/lockable-resources-plugin ./start.sh

# start.sh からの相対パス
PLUGIN_DIR=../../../lockable-resources-plugin ./start.sh
```

### 2. 起動する

```bash
./start.sh
```

`start.sh` の処理内容：

1. `mvn package -DskipTests` でプラグインをビルド
2. ビルドした `.hpi` を `docker/` へコピー
3. `jha`〜`jhc` ディレクトリを作成（初回のみ）
4. Docker イメージをビルド
5. 3 コンテナを起動
6. 各コントローラーの起動を確認

起動後のアクセス先：

| URL | 認証情報 |
|---|---|
| http://localhost:8081/jenkins/ | admin / admin |
| http://localhost:8082/jenkins/ | admin / admin |
| http://localhost:8083/jenkins/ | admin / admin |

> どのディレクトリからでも実行できます:
> ```bash
> ~/projects/jenkins/remote-lr/lockable-resources-remote-notes/dev/jenkins-env/start.sh
> ```

## 操作

### Step8 自動 E2E（初版スキャフォールド）

Step8 着手として、以下のスクリプトを追加済みです。

- `run-e2e.sh`: E2E 実行ハーネス（`start.sh` 内包、`--skip-start` 対応）
- `lib/common.sh`: 共通関数（Jenkins API 呼び出し、job 作成、build 待機、ログ保存）
- `scenarios/peer-basic.sh`: 正常系シナリオ（認証必須 remote lock の 8081 holder / 8083 waiter 待機検証）
- `scenarios/fail-closed.sh`: 異常系シナリオ（remote down / timeout / auth error / missing credentialsId / credentials type mismatch）

実行例:

```bash
PLUGIN_DIR=../../../lockable-resources-plugin ./run-e2e.sh
PLUGIN_DIR=../../../lockable-resources-plugin ./run-e2e.sh --clean-start
./run-e2e.sh --skip-start
PLUGIN_DIR=../../../lockable-resources-plugin ./run-e2e.sh --only peer-basic
```

> `--only peer-basic` / `--only fail-closed` で個別実行できます。
> `run-e2e.sh` が `start.sh` を呼ぶ場合は `PLUGIN_DIR` の指定が必須です（`--skip-start` 時は不要）。
> E2E はデフォルトで認証必須モードを使います（Step6d 検証を含む）。
> 実行結果は `dev/reports/` に保存されます。
>
> - レポート: `yyyymmddhhmmss-e2e-test.md`
> - 付随ログ/キャプチャ: `yyyymmddhhmmss-e2e-test/`

### 停止（Jenkins home は保持）

```bash
./stop.sh
```

コンテナを停止しますが、`jha`〜`jhc` のデータは残ります。
次回 `./start.sh` で続きから使えます。

### 完全初期化（Jenkins home も削除）

```bash
./start.sh --clean
```

または：

```bash
./stop.sh --clean
./start.sh
```

`jha`〜`jhc` ディレクトリを削除してから起動します。
管理者設定・パイプライン設定などをすべてリセットしたいときに使います。

### ログを確認する

```bash
# 全コントローラーのログをフォロー
docker compose -f path/to/jenkins-env/docker-compose.yml logs -f

# 特定コントローラーのみ
docker compose -f path/to/jenkins-env/docker-compose.yml logs -f jenkins-a
```

`jenkins-env/` ディレクトリにいる場合は `-f` オプション不要：

```bash
cd path/to/jenkins-env
docker compose logs -f jenkins-b
```

## プラグインを更新して再起動する

ソースを修正したら `start.sh` を再実行するだけです。
ビルド→イメージ再構築→コンテナ再起動まで一括で行います。

```bash
./start.sh
```

Jenkins home のデータは保持されます。初期化したい場合は `--clean` を付けます。

## よくある問題

### `PLUGIN_DIR` が見つからない

```
[ERROR] HPI not found in .../target/
```

`PLUGIN_DIR` が正しく解決されていないか、ビルドに失敗しています。

- `echo $PLUGIN_DIR` で解決先を確認する
- `lockable-resources-plugin/` の clone またはシンボリックリンクを確認する
- Maven のエラーログを確認する

### ポートが使用中

```
Bind for 0.0.0.0:8081 failed: port is already allocated
```

既存コンテナまたは別プロセスが占有しています。

```bash
./stop.sh
./start.sh
```

### コンテナが READY にならない

240 秒以内に `/jenkins/login` が返らない場合：

```bash
docker compose logs jenkins-a
```

でログを確認してください。
