# 高負荷テスト仕様（remote lock 統合ストレス）

この文書は `dev/jenkins-env/run-load.sh`（新規予定）が実行する高負荷／ストレステストの
設計・仕様を定義します。機能等価性を確認する `E2E_TEST_SPECIFICATION.md` の **正当性スイート**
とは目的・出力・合否条件が異なる、独立した **負荷スイート**です。

> **位置付け:** E2E（`run-e2e.sh`）が「機能が成立するか」を checkpoint で PASS/FAIL 判定するのに対し、
> 本スイートは「実システム規模で remote lock を同時多発させたときの**整合性・収束性・劣化の正当性**」を
> メトリクス＋不変条件で判定します。共通基盤（`lib/common.sh`・docker controllers）は共有しますが、
> ハーネスは別 (`run-load.sh`)。E2E の `all`（= サイクル DoD の 20/20 ゲート）には**含めません**。
>
> **主役は G01（4ノード相互 server/client ストーム）**。issue #1025 の「server/client 兼用・
> 独立一方通行リレーの組み合わせ」を統一キュー込みで実負荷で叩く統合シナリオです。
> L01〜L03（REST 直叩きの単体ストレス）は、G01 で異常が出たときに **lock 層単体に切り分ける補助**です。

---

## 目的

| # | 検証内容 | シナリオ |
|---|---|---|
| 1 | 4 台が server/client を兼用し各 50 ジョブを同時実行しても、**同一リソースが容量を超えて保持されない**（相互排他がシステム規模で破れない） | G01 |
| 2 | 高競合下でも**デッドロック・lost wakeup・phantom lock が起きず**、全ジョブが必ず終端する（成功 or 正当な timeout） | G01 |
| 3 | timeout したジョブが**正当な枯渇待ち**由来であること（バグ由来でない）をキューログから証明できる | G01 |
| 4 | `skipIfLocked` の中段取得が成否いずれでも**ジョブを止めない**（もみ消し成立） | G01 |
| 5 | local lock と remote lock が**同一物理リソース上で正しく排他**される（server-self-use の規模版） | G01 |
| 6 | 全ジョブ停止後、各サーバーが**全リソース free・STALE ゼロ**へ復帰する（クリーン後始末・リークなし） | G01 |
| 7 | 全ジョブ console から**リソースのキュー待ち時間の時系列を可視化**できる（PNG） | G01 |
| 8 | （補助）lock 層を孤立させたときの相互排他・スループット・リーク | L01–L03 |

---

## テスト体系

### シナリオ一覧

| ID | スクリプト/ジョブ | 負荷の型 | 主な検証ポイント | 既定規模 | 対象 |
|---|---|---|---|---|---|
| **G01** | `grid-storm`（Jenkinsfile + run-load.sh） | 統合システムストレス | 4 ノード相互 server/client、各 50 ジョブ × 3 周、相互排他・収束/劣化の正当性 | 4×50=200 並列 | a,b,c,d |
| L01 | `contention-storm`（REST 直叩き） | 競合下の整合性（単体） | 容量1リソースへ N 並列 acquire、クリティカルセクション非重複 | 並列 50 | 単一サーバー |
| L02 | `throughput-acquire`（REST 直叩き） | スループット/遅延（単体） | 競合なしで acquire→release 反復、req/s・p95 | 並列 30 | 単一サーバー |
| L03 | `sustained-soak`（REST 直叩き） | 持続/リーク（単体） | 中並列・長時間・heartbeat、record/リソースの baseline 復帰 | 並列 10 | 単一サーバー |

> 本書は **G01 を主体に詳述**し、L01〜L03 は末尾「補助シナリオ」に要約します。

### G01 構成図（Mermaid — トポロジーのみ）

```mermaid
flowchart LR
  subgraph A[jenkins-a: server+client / 50 res(40 exposed) / 50 jobs]
  end
  subgraph B[jenkins-b: server+client / 50 res(40 exposed) / 50 jobs]
  end
  subgraph C[jenkins-c: server+client / 50 res(40 exposed) / 50 jobs]
  end
  subgraph D[jenkins-d: server+client / 50 res(40 exposed) / 50 jobs]
  end
  A <-->|remote lock 相互| B
  A <-->|remote lock 相互| C
  A <-->|remote lock 相互| D
  B <-->|remote lock 相互| C
  B <-->|remote lock 相互| D
  C <-->|remote lock 相互| D
```

> 各ジョブは remote ターゲットを 4 台から**ランダム選択**（自分自身を含む＝server-self-use も内包）。
> 時系列の可視化は Mermaid ではなく**生成した PNG**で行う（後述「レポート & 可視化」）。

---

## 実行環境

### 4 コントローラー（全台 server/client 兼用）

| サービス | ホストポート | 内部 URL | jenkins home | 役割 |
|---|---|---|---|---|
| `jenkins-a` | 8081 | `http://jenkins-a:8080/jenkins` | `jha/` | server + client |
| `jenkins-b` | 8082 | `http://jenkins-b:8080/jenkins` | `jhb/` | server + client |
| `jenkins-c` | 8083 | `http://jenkins-c:8080/jenkins` | `jhc/` | server + client |
| `jenkins-d` | 8084 | `http://jenkins-d:8080/jenkins` | `jhd/` | server + client |

各台で相互に `remotes[self→other]`（× 他 3 台）と、相手サーバー用 admin API トークン credentials を設定する。

### リソースモデル（各台 50 個・うち 40 exposed）

`quantity` は **label 選択にのみ効く**（named resource は常に 1 個）。よって `quantity:2` 等は
**label ベース要求**で構成する。各台に以下のラベル付けでリソースを生成する。

| グループ | 個数 | 付与ラベル | 用途 |
|---|---|---|---|
| 全リソース | 50 | `pool` | local / remote 双方の**唯一の選択ラベル** |
| うち exposed | 40 | + `remote-enabled`(=exposeLabel) | remote 公開（= remote 選択対象になる） |

選択ラベルは `pool` 一本に統一する（専用の `rpool` は設けない）。exposure は exposeLabel
（`remote-enabled`）だけで決まり、`quantity` 選択は常に `pool` で行う。

- **remote 選択**: クライアントは `label: 'pool'` を送り、サーバーは自分の **exposed（`remote-enabled`）の中から**
  `pool` 一致を `quantity` 個確保する。exposed は 50 個中 40 個なので → 1 台あたり remote 供給 = 40。
- **local 選択**: `label: 'pool'`（quantity:1）。exposed/非 exposed の双方 50 個に当たり得る（"expose 不問"）。
  → exposed リソースは **local と remote で奪い合い**になり、server-self-use の排他を規模で突く。

### executor

各台の built-in node を **50 executors**（= 同時 50 ジョブ）に設定する。
ホストは WSL2 1 台で **4 JVM × 50 executor = 200 同時 pipeline**。これは重い。
→ **段階起動を必須運用**とする（[段階的パラメータ](#段階的パラメータ収束-劣化)参照）。
小規模（例 4×10）でハーネス健全性を確認 → フルスケール。各 JVM のヒープは start.sh / Dockerfile で引き上げる。

### Jenkinsfile 供給（ファイル読み → インライン注入）

負荷ジョブの pipeline は **notes リポジトリ内の Jenkinsfile を真実の源**とし、`run-load.sh` がその
ファイルを読んで **`CpsFlowDefinition`（sandbox 無効）でインライン注入**する（既存 `upsert_pipeline_job`
の content をヒアドキュメントからファイル読みに置換）。

- 採用理由: メンテは Jenkinsfile 1 ファイル編集で済み版管理も効く。一方、ランタイム git checkout を
  使わないので **外部依存ゼロ・600 回 checkout のノイズゼロ**。負荷試験に最適（SCM checkout 案は不採用）。
- **sandbox 無効**: 信頼済みハーネスが生成する負荷ジョブに限り `new CpsFlowDefinition(script, false)` とし、
  `System.currentTimeMillis()` / `Random` 等を使えるようにする（構造化イベントの epoch 採取・ランダム選択用）。
- 配置: `dev/jenkins-env/load/Jenkinsfile.grid`（パラメータ化。サーバー一覧・自 serverId・各ラベル・
  反復数・sleep・各 lock timeout・ジョブ全体 timeout を env/params で受ける）。

### 依存コマンド

- `curl`, `python3`, `docker`, `base64`, `flock`
- **matplotlib**（PNG 生成）: ホストに未導入のため `dev/.venv` を作成し `pip install matplotlib`。
  描画は `dev/jenkins-env/lib/analyze_load.py`（venv の python で実行、コンテナ非依存）。

### REST API 契約（被試験エンドポイント）

`RemoteApiV1Action`（`.../actions/RemoteApiV1Action.java`）。ベース URL `<server>/lockable-resources/remote/v1/`。

| メソッド / パス | 用途 | 成功 | 主な失敗 |
|---|---|---|---|
| `POST /acquire` | enqueue。body `{"lockRequest":{...},"clientId":"..."}` | `202` `{lockId,state}` | `400`/`403`/`404`/`413` |
| `GET /acquire/{lockId}` | 状態ポーリング（純 read、QUEUED 寿命はサーバーキュー所有） | `200` `{lockId,state,...}` | `404` |
| `POST /lease/{lockId}/heartbeat` | lease 更新 | `204` | `410` |
| `POST /lease/{lockId}/release` | 解放（冪等） | `204` | — |

G01 はプラグインのクライアント実装（pipeline の `lock(...)`）経由でこれらを使う。L01〜L03 は curl で直接叩く。

---

## ジョブ設計（G01 / Jenkinsfile.grid）

各台で **50 ジョブを同時起動**。1 ジョブの挙動:

```groovy
// パラメータ: SERVERS=[a,b,c,d], SELF=<自id>, ALLOW_SELF=false, ITER=3, SLEEP=30,
//             RLOCK_TO=3(min), LLOCK_TO=3(min), JOB_TO=15(min)
// pickTarget: ALLOW_SELF=false なら SELF を除外（純クロス）、true なら 4 択（25% loopback）
timeout(time: JOB_TO, unit: 'MINUTES') {       // ジョブ全体 15 分
  for (i in 1..ITER) {                          // 3 周
    def t1 = pickTarget(SELF, SERVERS, ALLOW_SELF)   // remote ターゲット
    emit(i, 'REMOTE_MAIN', 'REQUEST', t1)
    lock(label: 'pool', quantity: 2, serverId: t1, variable: 'RMAIN',
         timeoutForAllocateResource: RLOCK_TO, timeoutUnit: 'MINUTES') {   // ① remote 2 個（label）
      emit(i, 'REMOTE_MAIN', 'ACQUIRED', t1, env.RMAIN)   // env.RMAIN = 取得名(カンマ区切り)
      emit(i, 'LOCAL', 'REQUEST', SELF)
      lock(label: 'pool', quantity: 1, variable: 'LRES',
           timeoutForAllocateResource: LLOCK_TO, timeoutUnit: 'MINUTES') { // ② local 1 個（expose 不問）
        emit(i, 'LOCAL', 'ACQUIRED', SELF, env.LRES)
        def t2 = pickTarget(SELF, SERVERS, ALLOW_SELF)
        try {                                     // ③ remote 1 個 skipIfLocked（もみ消し）
          lock(label: 'pool', quantity: 1, serverId: t2, skipIfLocked: true) {
            emit(i, 'REMOTE_SKIP', 'ACQUIRED', t2)
          }
        } catch (e) { emit(i, 'REMOTE_SKIP', 'FAILED', t2) }  // 成否とも継続
        emit(i, 'LOCAL', 'BODY', SELF)
        sleep(time: SLEEP, unit: 'SECONDS')       // ④ 30 秒保持
        emit(i, 'LOCAL', 'RELEASED', SELF)
      }                                           // local 解放
      emit(i, 'REMOTE_MAIN', 'RELEASED', t1)
    }                                             // remote 解放
  }
}
```

### 構造化イベント（console 出力の契約）

可視化と判定は console の構造化行から行う。Jenkinsfile の `emit()` は次の 1 行を出力する
（epoch ミリ秒・パイプ区切り。timestamps プラグイン非依存）。

```
LLT|<epochMs>|<jobUid>|<self>|<iter>|<phase>|<event>|<target>|<resources>
  phase     : REMOTE_MAIN | LOCAL | REMOTE_SKIP
  event     : REQUEST | ACQUIRED | SKIPPED | FAILED | BODY | RELEASED
  jobUid    : "<JOB_NAME>#<BUILD_NUMBER>@<self>"
  resources : ACQUIRED 行のみ。lock(variable:'X') の lockEnvVars 経由で得た
              取得リソース名（カンマ区切り）。他イベントでは空
```

- **キュー待ち時間** = 同一 `(jobUid,iter,phase)` の `ACQUIRED.epochMs − REQUEST.epochMs`。
- **保持区間** = `ACQUIRED` 〜 `RELEASED`（同一 `(jobUid,iter,phase)` で対応付け）。重なり解析には
  `ACQUIRED` 行の `resources`（取得名）と `target`（保持サーバー）を使う。

`run-load.sh` は全ジョブの `consoleText` を収集し `LLT|` 行を抽出、`python3` で集計・解析・作図する。

---

## 段階的パラメータ（収束 ↔ 劣化）

「両方（段階的）」運用。まず緩い設定で**収束**（ほぼ全成功・待ちレイテンシ測定）を確認し、
並列度・競合を上げて**劣化点**（正当な timeout の発生）まで押す。`run-load.sh` の引数で振る。

| プリセット | jobs/台 | ITER | SLEEP | RLOCK_TO | JOB_TO | 狙い |
|---|---|---|---|---|---|---|
| `smoke` | 5 | 1 | 10s | 2min | 5min | ハーネス健全性（4×5=20 並列） |
| `converge` | 20 | 3 | 30s | 3min | 15min | 収束を期待（成功妥当・レイテンシ基準採取） |
| `full` | 50 | 3 | 30s | 3min | 15min | 当初設計どおり（4×50=200、overcommit 約 2.5×） |
| `stress` | 50 | 3 | 60s | 3min | 15min | 劣化を誘発（保持を伸ばし枯渇 → 正当 timeout を観測） |

```
--preset smoke|converge|full|stress
--jobs-per-controller <N>  --iterations <N>  --sleep <SEC>
--remote-timeout <MIN>  --local-timeout <MIN>  --job-timeout <MIN>
--allow-loopback        remote ターゲットに SELF を含める（25% loopback）。既定 OFF=純クロス。
                        実運用で remote 経由の自 server 指定はバグ筋なので remote 機能の高負荷
                        テストでは既定で除外。loopback 性能を測りたい時のみ ON
--only grid-storm | contention-storm | throughput-acquire | sustained-soak | g-series | l-series | all
--skip-start
```

> **timeout 収支メモ:** 1 周の最悪 = remote 待ち RLOCK_TO + local 待ち LLOCK_TO + skip + SLEEP。
> `full` で最悪 ≈ 3+3+0.5+0.5 ≈ 7 分/周 → 3 周で最悪 ≈ 21 分 > JOB_TO 15 分。
> よって**病的競合下では 15 分壁に当たり得る**。これは異常ではなく**劣化シグナル**として扱い、
> 「その timeout が正当な枯渇待ち由来か」をオラクル（後述 CP04）で判定する。

---

## 検証基準 / オラクル

高競合下の結果は確率的なので、**成功件数では合否にしない**。システム不変条件と、ジョブごとの
**結果分類＋正当性**で判定する。

### ジョブ結果の分類

各 `jobUid` を console 末尾イベントと build result から分類:

| 分類 | 定義 |
|---|---|
| `COMPLETED` | ITER 周ぶんの `REMOTE_MAIN/RELEASED` が揃い build = SUCCESS |
| `TIMED_OUT` | 15 分壁。末尾が未完の `*_REQUEST`（= lock 待機中に打ち切り） |
| `FAILED` | remote main lock が fail-closed 失敗（通信/認証/枯渇 timeout で body 未実行） |
| `HUNG` | 上記いずれでもなく 15 分 + grace を超えて終端しない（**バグ疑い**） |

### 検証基準（システム不変条件）

| ID | 検証項目 | 期待値 |
|---|---|---|
| CP01 | **相互排他**: 全ジョブ・全台の保持区間を解析し、同一リソースが容量超で同時保持される重なりが無い | 重なり `0` |
| CP02 | **local/remote 排他**: exposed リソース上で local 保持と remote 保持の区間が重ならない | 重なり `0` |
| CP03 | **終端性**: `HUNG` が無い（全ジョブが COMPLETED/TIMED_OUT/FAILED のいずれかで終端） | `HUNG = 0`（デッドロック/lost wakeup なし） |
| CP04 | **timeout 正当性**: 各 `TIMED_OUT` ジョブは、打ち切り時刻に当該 label の保持数が容量に達しており**正当な枯渇待ち**だったと証明できる（lost wakeup でない） | 全 TIMED_OUT で `true` |
| CP05 | **skip もみ消し**: `REMOTE_SKIP` の ACQUIRED/FAILED いずれもジョブを `FAILED` にしていない | `true` |
| CP06 | **fail-closed**: `FAILED` ジョブで remote main 失敗後に `LOCAL/ACQUIRED` 等の body 進行イベントが出ていない | `true` |
| CP07 | **後始末**: 全ジョブ停止後、各台で全リソース free・remote record の STALE/保持ゼロ（Groovy 確認） | `true` |
| CP08 | （converge プリセット）COMPLETED 率 | 高い（例 ≥ 0.95。基準は実測で確定） |

> CP01/CP02 が核心。保持区間（ACQUIRED〜RELEASED）を `(target, resource)` ごとに集め、`python3` で
> 区間スイープし容量超の重なりを検出する。**リソース名**は `ACQUIRED` 行の `resources` フィールド
> （`lock(variable:'X')` の lockEnvVars 経由）から取得する。各 lock に `variable` を付けるのはこのため。

---

## レポート & 可視化

`run-load.sh` 終了時に生成:

```
reports/<runId>-load-test.md
reports/<runId>-load-test/grid-storm/
  consoles/<jobUid>.txt            # 各ジョブの consoleText
  events.csv                       # 解析済み LLT イベント（全ジョブ統合）
  netstats.csv                     # docker stats サンプル（epochMs,name,cpu,mem,net,block）
  job-classification.csv           # jobUid, outcome, justified(timeout), iters_completed
  overlaps.txt                     # CP01/CP02 の重なり（0 件なら空）
  metrics.json                     # 分類別件数, queue-wait の p50/p95/p99, netstats 要約
  plots/queue-waiters-over-time.png
  plots/queue-wait-scatter.png
  plots/resource-mean-hold-scatter.png
  plots/network-throughput.png     # コンテナ別 rx+tx スループット推移
  plots/cpu-utilization.png        # コンテナ別 CPU% 推移
  scenario-details.md
```

### レポート観点 1: ジョブ挙動が想定通りか

- 結果分類の内訳（COMPLETED / TIMED_OUT / FAILED / **HUNG=0 であること**）。
- **timeout の妥当性**: 各 TIMED_OUT に CP04 の判定（正当な枯渇待ち / 疑わしい）を併記。
- **成功の妥当性**: COMPLETED ジョブが CP01/CP02 の相互排他を一度も破っていないこと。
- skip もみ消し（CP05）・fail-closed（CP06）の成立。

### レポート観点 2: キュー待ち時間の可視化（PNG、Mermaid 不使用）

`analyze_load.py`（matplotlib / venv）が `events.csv` から生成し、レポート md からリンク:

| PNG | 内容 |
|---|---|
| `queue-waiters-over-time.png` | 各時刻の **QUEUED 待機者数**の推移（台別の線 + 合計）。山＝競合ピーク |
| `queue-wait-scatter.png` | 取得ごとの **キュー待ち秒数**（y）を取得時刻（x）に散布。台/phase で色分け、200 ジョブの生分布が見える |
| `resource-mean-hold-scatter.png` | **全リソースの平均保持時間の散布**。1 点 = 1 リソース（50×4=200 個）、x = そのリソースの取得時刻の中央値、y = **平均保持秒数**、色 = 保持サーバー、点サイズ = 取得回数。プールのどのリソースが長く/多く掴まれたか（負荷の偏り）が一望できる |

### レポート観点 3: 処理負荷（docker stats）

run 中に `docker stats` を `SAMPLE_INTERVAL`（既定 3 秒）で全コンテナサンプリングし、`netstats.csv` に記録。
解析側で **ネットワークスループット（rx+tx の累積差分／秒）**・CPU%・mem を集計する。
Jenkins Metrics プラグインは未導入のためサーバー側 HTTP メーターは使わず、コンテナ実測で代替する。

- **利用率テーブル**（レポート md）: コンテナ別の peak CPU% / peak mem / net rx total / net tx total。
- `network-throughput.png`: コンテナ別 rx+tx スループット推移（= ネットワーク系処理負荷）。取得バーストで山。
- `cpu-utilization.png`: コンテナ別 CPU% 推移（remote ターゲットに偏った台がスパイク）。
- full スケールでホスト容量（CPU 飽和・mem 上限）を判断する材料にもなる。

> remote API の poll はプラグイン内部呼び出しで LLT には出ないが、netstats の rx/tx に**実バイトとして反映**される。

---

## 終了コード

- 全不変条件成立（HUNG=0・重なり0・後始末OK、TIMED_OUT は CP04 で正当）: 0
- 不変条件違反（HUNG 検出 / 相互排他の重なり / 不当 timeout / 後始末残り）: 1
- 被試験コントローラー未起動などで実行不能: 10

---

## 補助シナリオ（lock 層単体ストレス：L01–L03）

G01 で異常が出たとき、Jenkins/pipeline の影響を排して **lock 層を孤立**させ原因を切り分ける。
負荷源はホストの curl ワーカー群（pipeline を介さず REST 直叩き）。被試験は単一サーバー（既定 jenkins-b）。

| ID | 概要 | 核心の検証 |
|---|---|---|
| L01 `contention-storm` | 容量1リソースへ N 並列 acquire→（短 hold）→release | クリティカルセクション区間の**重なり 0**（二重取得ゼロ）。バリア同期で一斉開始 |
| L02 `throughput-acquire` | 競合しない割当で acquire→release を時間制限ループ | error 率 ≤ 0.5%、p95/p99・req/s（初回 report-only → 以降回帰検知） |
| L03 `sustained-soak` | 中並列・長時間・heartbeat 更新 | record/保持リソースの **baseline 復帰**・STALE 非蓄積・record 単調増加なし |

各 L シリーズの詳細（パラメータ・出力）は G01 の規約に準じ、`--only <name>` で単独実行する。

---

## 設計上の決定（なぜこの形か）

- **run-e2e.sh に足さない**: 出力（checkpoint vs メトリクス）・合否（一致 vs 閾値/不変条件）・実行プロファイルが
  異なり、E2E の `all`（DoD 20/20 ゲート）を汚さないため別ハーネス `run-load.sh`。`lib/common.sh` は再利用。
- **G01 は pipeline 経由**: 統一キュー・lockEnvVars・cross-controller を実システムで叩くのが目的。
  単体 lock 層だけ見たい場合は L01–L03（REST 直叩き）で切り分ける。
- **Jenkinsfile はファイル読み→インライン注入**（SCM checkout 不採用）: メンテ性は 1 ファイル編集で同等、
  かつランタイム git ゼロ・checkout ノイズゼロ。負荷試験の純度を保つ。
- **quantity は label ベース**: `quantity` は label 選択にのみ効くため、remote/local とも label 要求で構成。
- **合否は件数でなく不変条件**: 高競合は確率的。相互排他・終端性・timeout 正当性で判定し偶然 PASS を排除。
- **時系列可視化は PNG**: Mermaid は連続時系列に不向き。matplotlib（venv）で生成しリンク。

---

## 実装・検証実績

| 日付 | 範囲 | 結果 | 備考 |
|---|---|---|---|
| 2026-06-21 | `smoke`（4×5=20 ジョブ, ITER1, sleep10s） | **20/20 SUCCESS・HUNG 0・相互排他違反 0・queue待ち p95 ≈173ms** | ハーネス健全性確認。PNG 3 枚生成 |
| 2026-06-21 | `converge`（4×20=80 ジョブ, ITER3, sleep30s） | **80/80 COMPLETED・HUNG 0・相互排他違反 0**。queue待ち p50 115ms / **p95 ≈27.2s / max 30.2s**（実競合発生・収束達成）。待機者 peak ≈35（3 波＝3 周）。peak CPU b 261% / a 187% | docker stats 132 サンプル。net rx/tx ≈0.6–0.8MB/台。PNG 5 枚 |
| 2026-06-21 | `full`（4×50=**200 ジョブ**, ITER3, sleep30s, **loopback ON**） | **200/200 COMPLETED・HUNG 0・相互排他違反 0**。重競合：queue待ち p50 3.1s / **p95 ≈78s / max ≈90s**、**待機者 ≈140 で飽和**後に完全排出。peak CPU **d 449% / b 295%**、net rx/tx ≈3.5–4.5MB/台。wall ≈6.4 分 | self ターゲット 25%（144/600）。max待ち90s < lock timeout 180s で timeout 未到達 |
| 2026-06-22 | `full`（200 ジョブ, ITER3, sleep30s, **loopback OFF=純クロス**） | **200/200 COMPLETED・HUNG 0・相互排他違反 0**。self=0（600/600 cross）。より厳しい：queue待ち p50 4.4s / **p95 ≈96s / p99 ≈118s / max ≈124s**。peak CPU **a 366% / b 243% / d 240%**、peak mem ≈1.0GiB/台、net rx/tx ≈4.1–5.5MB/台。wall ≈6.5 分 | **目標達成（最も厳しい純クロス構成で remote LR 非破綻）**。全 remote がネットワーク越し → loopback ON 比で待ち +23%・net +25%。max待ち124s < lock timeout 180s で完全収束（CP04 観測には stress 必要）。`--allow-loopback` で loopback ON 切替可 |

| 2026-06-22 | `stress`（200 ジョブ, ITER3, **sleep60s**, loopback OFF, **lock timeout 3分 修正後**） | **191 SUCCESS / 9 FAILURE・HUNG 0・相互排他違反 0・9 件すべて fail-closed（body 実行 0）**。queue待ち p95 167s / max 182s（≈3 分で打ち切り）。劣化系を初観測 | **finding: 失敗 9 件が 2 系統**。3 件=クリーンな `LOCK_WAIT_TIMEOUT`（server が state=FAILED 返却）、**6 件=QUEUED ポーリング中の `GET /acquire/{id}` が HTTP 404 → client が RemoteApiException（通信失敗扱い）で fail-closed**。安全側（破綻なし）だが、サーバ側キュー期限切れを「通信失敗」と誤表示する診断性の粗。下記 finding 参照 |

### stress で見つかった finding: QUEUED 期限切れの signal 不整合（安全だが診断性に粗）

hold 60s・200 並列の枯渇下で remote acquire が失敗する経路が **2 系統**に割れた（いずれも fail-closed・整合性保持）:

- **A（3/9）**: client のポーリングが record 存在中に当たり、`state=FAILED, errorCode=LOCK_WAIT_TIMEOUT` を受領 → 「lock 待ち timeout」と明示。**クリーン**。
- **B（6/9）**: サーバ側の QUEUED entry timeout で record が先に消え、client の `GET /acquire/{lockId}` が **404 LOCK_NOT_FOUND** → `RemoteApiClient` がこれを `RemoteApiException: Remote API communication failure` と扱い fail-closed。**正当な枯渇 timeout が「通信失敗」と誤表示**される。

**確定真因（当初「race」と書いたが訂正）**: terminal record の保持 TTL（`TERMINAL_TTL_MS=120s`）を **`enqueuedAt` 起点**で測っているバグ（`RemoteLockManager.maybeScanStale` L228-230）。timeout 起因の FAILED 記録は `t=timeoutForAllocateResource` で生成されるため、`timeoutForAllocateResource > 120s` だと**生成直後に TTL 超過扱い → 即削除**。以降の GET poll が 404 → client が「server may have restarted」で fail-closed（系統 B）。A/B の揺れは「markFailed〜次回掃引まで」の隙間のみで、**主因は決定的バグ・負荷非依存**。詳細・修正・E2E 検出可否は `dev/docs-j/LRR_ISSUE_P1_M1H_queued_expiry_poll_404.md`。

**評価**: `破綻` ではない（相互排他保持・デッドロック無し・body 未実行）。だが正当な枯渇 timeout が 404 通信失敗として誤表示される。**修正の本丸は terminal 遷移時刻起点で TTL を測ること**。`timeoutForAllocateResource > 120s` の E2E 1 本で決定的に再現でき、負荷は必須でない（高負荷テストは stress が偶々 timeout=3 分を使ったため先に炙り出した）。

### smoke で確定した事項（旧「未確定」の解消）

- **quantity:2 が label 経由で成立**: remote `lock(label:'pool', quantity:2, serverId:X)` が 2 リソース
  （例 `a-res-05,a-res-06`）を取得し `variable` 経由で body に届く（旧未確定⑥を解消）。
- **self ターゲット可**: `serverId=self` で server-self-use 経路が動作（4 択ランダムに self を含めてよい）。
- **ジョブ注入**: sandbox=false + `ScriptApproval.get().preapprove(script, GroovyLanguage.get())` で承認。
  `System.currentTimeMillis()` / `Random` が使える（LLT の epoch 採取に必須）。
- **キュー合体回避**: 無パラメータの同時トリガは Jenkins キューで合体するため、`STORM_IDX` パラメータで
  各トリガを別キュー項目にする（`buildWithParameters`）。
- **executor**: `Jenkins.setNumExecutors(jobs/台)` で同時実行数を確保（smoke は 5/台で 5 並列を確認）。
- **CSV 整合**: `resources` の複数名はセル内を `;` 区切りにして列ずれを防ぐ（解析側も `;` で split）。

### 残課題（converge / full / soak の実走で確定）

- `converge`/`full` 実走での **COMPLETED 率・queue-wait 基準値**（CP08 の閾値確定）。
- **200 並列に耐えるヒープ/executor 実値**（full でホスト容量を確認）。
- `lock(timeout:)` と remote `timeoutForAllocateResource` の関係、QUEUED 滞留時の挙動
  （smoke は無競合で未到達。stress で枯渇 timeout を実観測して CP04 を検証）。
- **後始末 CP07・soak リーク検査の Groovy 取得手段**（remote record 数 / STALE 数）。L03 実装時に確定。

## 更新履歴

- 2026-06-21: 初版（統合ストレス G01 を主役に全面設計）。4 ノード相互 server/client、各 50 リソース
  （40 exposed）・50 ジョブ × 3 周、ジョブ全体 timeout 15 分。Jenkinsfile は notes 配置＋インライン注入
  （sandbox 無効）、可視化は matplotlib PNG。合否はシステム不変条件（相互排他・終端性・timeout 正当性・
  後始末）。L01–L03 は lock 層単体切り分けの補助に降格。段階運用 smoke→converge→full→stress。
  **未確定（実機確認の上、本書を更新）**: ① QUEUED の `timeoutForAllocateResource` の実挙動、
  ② remote record 数 / 保持状態の Groovy 取得手段、③ STALE 閾値の実値、④ converge の COMPLETED 率・
  queue-wait 基準値、⑤ 200 並列に耐えるヒープ/executor 実値、⑥ `lockEnvVars` 取得名の emit 連携。
```
