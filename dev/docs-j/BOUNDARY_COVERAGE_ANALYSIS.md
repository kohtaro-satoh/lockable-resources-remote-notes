# 境界カバレッジ分析（データ / 時系列 / スケール）

remote lock の E2E スイートを「データ・時系列・スケーリング性能の境界を網羅する」観点で棚卸しした結果。
対象は `dev/jenkins-env/`（run-e2e.sh / scenarios / lib）と、被試験側の
`lockable-resources-plugin` の remote パッケージ。

作成: 2026-08-10 / 対象プラグイン: `aa0c391`（Phase C まで）

---

## 1. 結論

**既存 S01–S22 は「機能が動くこと」の網羅としてはほぼ完成しているが、境界という観点では 3 軸とも
ほぼ空白だった。** 具体的には、22 シナリオすべてが「正しい値・正常な時間・小さい規模」だけを通す。

- **データ境界**: 全シナリオが `lock()` 経由。クライアントは常に整形された要求しか送らないため、
  API の**拒否側の契約（status + errorCode）が丸ごと未検証**だった。1 MiB の body 上限、
  `heartbeatIntervalSeconds` の明示バリデーションなど、**コードに書いてあるのにテストが 1 件もない**境界が複数。
- **時系列境界**: プラグインは 7 つの時間定数を持つが、テストはそれを名前で参照せず `sleep 25` のような
  裸の数値で書かれていた。定数が動けば**テストは黙って無意味化する**。境界の「内側と外側の両方」を
  突いていたものは 0 件。
- **スケール境界**: 負荷スイートは**並列度**という 1 次元しか振っていない。カタログ規模・待機列の深さ・
  ポーリングクライアント数・保持時間はすべて「一握り」に固定されていた。M2/M3 で入った
  `GET /resources`（無ページング・`syncResources` 保持）は**構造的に規模依存**なのに未測定だった。

今回、リファクタリングに加えて **B01–B07 の 7 シナリオ** を実装し、
上記の空白のうち最も価値の高い部分を埋めた。ハーネス側の欠陥 2 件（§5）に加え、
**プラグイン側の確定不具合 1 件（F1: remote の allocate timeout が期限どおりに発火しない）**と、
仕様として決めるべき点 3 件（F1a / F2 / F3）が出た（§4）。

> F1 は「テストが落ちて」見つかったのではない。**境界を洗い出す過程で API を直接叩いたことで**
> 見えたもので、既存 S18 は設計上この差を区別できなかった（§4 F1 参照）。

---

## 2. 被試験側の境界一覧

テストを書く前に、「境界」がどこにあるかを実装から拾い出した。以下が全量。

### 2.1 時間定数

| 定数 | 値 | 出典 | 意味 |
|---|---|---|---|
| `DEFAULT_POLL_INTERVAL_SECONDS` | 3s | `RemoteClientDefaults` | acquire 状態のポーリング間隔 |
| `DEFAULT_HEARTBEAT_INTERVAL_SECONDS` | 10s | `RemoteClientDefaults` | lease 更新間隔 |
| `DEFAULT_REQUEST_TIMEOUT_SECONDS` | 5s | `RemoteClientDefaults` | HTTP 1 回あたりの timeout |
| `MAX_CONSECUTIVE_POLL_FAILURES` | 20（≒60s） | `RemoteLockSession` | 連続ポーリング失敗の許容回数 |
| `STALE_THRESHOLD_MS` | 60s | `RemoteLockManager` | heartbeat 途絶から STALE までの猶予 |
| `TERMINAL_TTL_MS` | 120s | `RemoteLockManager` | 終端レコードが観測可能な期間 |
| `TTL_MILLIS`（catalog） | 10s | `RemoteCatalogCache` | クライアント側カタログの鮮度 |

→ `lib/timings.sh` に名前付きで一元化し、**実行のたびにプラグインソースと突き合わせて乖離を検出**するようにした
（`rlr_check_timing_drift`）。以後、定数が動けば実行が止まる。

### 2.2 データ検証点（`RemoteApiV1Action` / `RemoteQueueEntry`）

| 入力 | 実装の扱い |
|---|---|
| body が JSON でない | 400 `INVALID_JSON` |
| `lockRequest` 欠落 / 非オブジェクト | 400 `MISSING_LOCK_REQUEST` |
| ターゲット無し / resource+label 併記 / 未知 strategy / priority+inversePrecedence | 400 `INVALID_REQUEST`（canonical validator） |
| `extra[i]` が resource も label も持たない | 400 `INVALID_EXTRA` |
| `heartbeatIntervalSeconds` ≤ 0 / 非整数 | 400 `INVALID_HEARTBEAT_INTERVAL` |
| body > 1 MiB | 413 `PAYLOAD_TOO_LARGE` |
| 未知 / 未公開のリソース・ラベル | 404 `UNKNOWN_RESOURCE` / `UNKNOWN_LABEL` |
| `quantity` 非数値・負値 | **検証なし**（`optInt` 既定 0 → label では「全件」） |
| `timeoutUnit` が TimeUnit でない | **検証なし**（deadline 0 = 無期限待ちに化ける） |
| `timeoutForAllocateResource` ≤ 0 | 無期限待ち（local `lock()` と同義、意図的） |

---

## 3. 3 軸のギャップと、その埋め方

### 3.1 データ境界

**空白だったもの**（すべて B01 / B03 で新規カバー）:

| 切り口 | 旧状態 | 対応 |
|---|---|---|
| 拒否側の契約（status + errorCode の対） | 未検証。`lock()` は整形要求しか送らない | **B01**: 13 種の拒否を status/errorCode 対で検証 |
| 1 MiB body 上限 | 未検証（定数だけ存在） | **B01**: ちょうど 1 MiB=202 / +1 文字=413 の**両側** |
| `heartbeatIntervalSeconds` バリデーション | 未検証（専用の検証コードがあるのに） | **B01**: 0 / 負 / 非整数 の 3 件 |
| 検証されない値の挙動 | 未検証・未文書 | **B01**: 観測として記録（§4 の所見 F1/F2） |
| リソース名のエンコーディング | 英小文字＋ハイフンのみ | **B03**: 空白 / 多バイト / 244 文字 / カンマ |
| combined variable の分離子衝突 | 未検証 | **B03**: カンマ入り名の曖昧性を実測（所見 F3） |

**未着手（優先度順）**:

1. **`extra` の件数スケール**（10 件 / 50 件）と、**main と extra が同一リソース**を指す自己重複。
   後者は単一 lease 内での自己待ちになり得る。
2. **`variable` の 10 件超展開**（`V10` 以降の順序・命名）。現在は最大 3 件までしか通っていない。
3. **`exposeLabel` を空文字にした場合の露出範囲**。設定 1 つで「全公開」にも「全非公開」にもなり得る、
   影響半径の大きい設定値の境界。
4. **保持中のリソース定義変更**: ロック中に exposeLabel を外す / リソースを削除する / 予約する。
5. **`clientId` の UI 混入**。C2 で `heldByClientId` がページに出るようになったため、
   クライアントが与えた文字列がサーバー側 UI に描画される経路ができた。エスケープの境界確認が要る。

### 3.2 時系列境界

**空白だったもの**:

| 切り口 | 旧状態 | 対応 |
|---|---|---|
| 定数への依存の明示 | `sleep 25` 等の裸の数値。定数が動くと黙って無意味化 | `lib/timings.sh` ＋ドリフト検出。S11/S13/S18 を定数由来に書き換え |
| `TERMINAL_TTL`(120s) の両側 | S18 が「TTL より長い待ち」の片側のみ | **B02**: TTL 内=200/`FAILED`+`RELEASED`、TTL 超=404 |
| lease の状態不整合な呼び出し | 未検証 | **B02**: 未知 ID への heartbeat/poll/release、二重 release、release 後 heartbeat、QUEUED への heartbeat |
| QUEUED の取り下げ | 未検証 | **B02**: release で待ち行列から抜けること＋抜けたまま昇格しないこと |
| カタログ TTL(10s) | 未検証 | **B04**: TTL 内は古いまま / TTL 超で追随 / サーバー停止中も描画（劣化して継続） |
| **中断**（abort） | 未検証 | **B05**: QUEUED 中の中断＝幽霊ロックを作らない、ACQUIRED 中の中断＝STALE を待たず即解放 |

**未着手（優先度順）**:

1. **`MAX_CONSECUTIVE_POLL_FAILURES`(20回≒60s) の両側**。19 回失敗して復帰した場合はロックを続行し、
   20 回で fail-closed。これは**クライアント側の唯一の「諦める」閾値**なのに 1 件もテストがない。
   実装は heartbeat 失敗（S11）とは別経路。
2. **STALE 閾値の直下/直上**。S11 は「STALE より短い途絶」、S13 は「STALE に到達」を見るが、
   いずれも境界の近傍ではない。特に **STALE 後に heartbeat が復帰した場合**（410 `LOCK_STALE`）の
   クライアント挙動が未検証。
3. **サーバー再起動時のクライアント保持**。`RemoteLockManager` のレコードは in-memory なので、
   サーバー再起動でレコードだけが消え、リソースは XML から復元される。クライアントの poll は 404 になり
   fail-closed するはずだが、**リソースがロックされたまま残るか否か**が未確認。運用で最も起きやすい事象。
4. **release と queue promotion の競合**。`RemoteLockManager.release()` に
   「QUEUED を同時に昇格させると orphan remote lock（リソースが固定され復旧不能）になる」旨の
   コメントがあり、`syncResources` で保護している。**既知の危険箇所なのに、それを狙って突くテストがない。**
5. **同一 priority における FIFO 公平性**。S12 は priority の逆転を見るが、同 priority で N 件並んだときの
   順序保存は未検証。

### 3.3 スケール境界

**空白だったもの**:

| 次元 | 負荷スイート | E2E | 対応 |
|---|---|---|---|
| 並列クライアント数 | G01 で 200 並列まで | — | 既存で充足 |
| **カタログ規模** | 固定（50/台） | 固定（数個） | **B06**: 100 / 500 / 2000 で応答時間・サイズ・全件性 |
| **discovery と acquire の干渉** | 未測定 | 未測定 | **B06**: カタログ 4 並列取得下での acquire 中央値 |
| **待機列の深さ** | 実質数件 | 1〜2 | **B07**: 1/10/50 件での昇格スループットと公平性 |
| 1 要求あたりのリソース数 | 1〜2 | 最大 3 | 未着手 |
| 持続時間（リーク） | — | — | 未着手（L03 は仕様のみ） |

**B06 の実測値**（この環境・この時点の基準値）:

| カタログ規模 | `GET /resources` | 応答サイズ | 全件性 |
|---|---|---|---|
| 100 | 12 ms | 15 KB | 100/100 |
| 500 | 21 ms | 53 KB | 500/500 |
| 2000 | 42 ms | 197 KB | 2000/2000 |

acquire+release 中央値: **71 ms（無負荷）→ 111〜119 ms（カタログ 2000 件を 4 クライアントが連続取得中）= 約 1.6 倍**。

→ 2000 件規模では線形・劣化は緩やかで、**現時点でクリフは無い**。ただし干渉は測定可能な形で存在する
（`describe()` が `syncResources` 内で全件直列化するため）。数千〜万規模を想定するなら、
この約 1.6 倍という数字が**回帰の基準線**になる。

**B07 の実測値**（同上）:

| 待機列の深さ | 昇格レイテンシ（解放→次の保持）※2 回実行 | ドレイン時間（全件） | 公平性 |
|---|---|---|---|
| 1 | 50 / 55 ms | 0.05 s | 1/1 |
| 10 | 54 / 106 ms | 4.5〜5.4 s | 10/10 |
| 50 | 125 / 99 ms | 15.1〜16.5 s | 50/50 |

→ **昇格レイテンシは深さに依存しない**。深さ 50 が深さ 10 より速い実行もある（125 ms vs 99 ms）ことから、
差は深さではなくノイズ。50 件が後ろに並んでいても次の 1 件を昇格させるコストは変わらない
＝**キュー再スキャンによる二次的劣化は無い**。飢餓も無し（accepted と served が全深さで一致）。

> **測定上の注意**: ドレイン時間はサーバー指標ではない。各昇格は「前のクライアントが気づいて解放する」
> のを待つ連鎖なので、クライアント側の検知間隔（本シナリオでは 0.5 秒）が 1 件あたり載る。
> 初版の実装は**全待機 ID を 1 ループで走査**しており、深さ N の監視に O(N²) のリクエストを要していた。
> 深さ 50 でのドレイン 33 秒はそのほぼ全てがハーネス自身のポーリングだった（修正後は 15 秒）。
> 現在は待機 1 件につき 1 クライアントが自分の lease だけを見る形にしてある。

**未着手（優先度順）**:

1. **ポーリング負荷**。待機クライアントは 3 秒間隔で poll し、保持クライアントは 10 秒間隔で heartbeat する。
   200 待機 = 約 66 req/s の純粋なポーリングで、各要求が `checkPermission` を通る。
   **poll の応答が 5 秒（`DEFAULT_REQUEST_TIMEOUT_SECONDS`）を超え始める点**がどこかは、
   そこを超えると連続失敗カウンタが回り始めるという意味で重要。
2. **soak / リーク**。`RemoteLockManager` のレコードマップと `RemoteClientRegistry` のエントリが、
   高回転を長時間続けたあとに baseline へ戻るか。仕様書の **L03 `sustained-soak` は未実装**
   （後述 §6）。C1 で入った `RemoteClientRegistry` は `forget()` 依存なので、
   `forget` を通らない失敗経路があればそこがリークになる。
3. **復旧時の thundering herd**。サーバー停止中に N クライアントが待ち、復帰した瞬間に全員が同時に来る。
4. **1 lease あたりのリソース数**（label で 40 件一括など）の取得レイテンシ曲線。

---

## 4. 実測で出た所見

いずれも B01/B03 の実行で確認したもの。**バグ断定ではなく、仕様として決めるべき点**として挙げる。

### F1: remote の allocate timeout が期限どおりに発火しない（優先度: 高・**確定 → 修正済み**）

**`timeoutForAllocateResource` は remote lock では待ち時間の上限にならない。** 期限は正しく計算されるが、
それを評価しに来る起床が予約されないため、**他の理由でキュー整備が走るまで発火しない**。

証拠 4 点:

1. **コードの非対称性**: ローカル経路は `queueContext()` の末尾と `getNextQueuedContext()` の末尾の
   2 箇所で `scheduleTimeoutAt(deadline)` を呼び、期限に自ら起床する。
   remote 経路（`queueRemote()` / `getNextRemoteEntry()`）に**対応する処理が無い**。
   `RemoteQueueEntry.isTimedOut()` は `getNextRemoteEntry()` が呼ばれた時にしか評価されない。
2. **経路は正常**: `RemoteLockManager.enqueue()` は `timeoutForAllocateResource` / `timeoutUnit` を
   `RemoteQueueEntry` に正しく渡しており、deadline も計算されている。**渡し忘れではなく、起床の欠落**。
3. **直接実験**: 保持中のリソースに `timeoutForAllocateResource: 5, timeoutUnit: "SECONDS"` で acquire
   → **60 秒経過しても QUEUED のまま**（期限の 12 倍）。この間キューを触る事象は無し。
4. **S18 の実測**: 保持時間と遅延が一致する。保持 144 秒・期限 124 秒 → 149 秒で失敗（25 秒遅れ）。
   保持を 184 秒に伸ばすと → **183 秒で失敗（59 秒遅れ）**。
   遅延は期限ではなく**保持者の解放時刻に追随**している。

影響: リソースが解放されない限り、有限の待ちを要求したクライアントが無期限に待つ。
STALE 保持（管理者対応待ち）や長時間ビルドが相手だと、`timeoutForAllocateResource` は無効に等しい。

なぜ既存テストで露見しなかったか（2 層とも同じ盲点）:

- **E2E**: S18 は「保持者の解放 ≒ 期限」という設定（保持 144s / 期限 124s）で、判定も `>= 120s` だったため
  **期限で失敗したのか解放で失敗したのかを区別できなかった**。現在は保持を期限 +60 秒にして両者を離し、
  **CP08 をハード判定**にしてある。
- **ユニット**: `RemoteLockManagerTest` の既存 timeout テストは `manager.checkTimeouts()` を**手で呼んで**いた。
  本番コードが決してやらないことをテストが代行していた形。

**修正（2 箇所・`LockableResourcesManager`）**:

1. `queueRemote()` — ローカル `queueContext()` と同じ「期限が現行より早ければ起床予約」を追加
2. `getNextQueuedContext()` — 最早期限を**両キューにまたがって**計算（`earliestRemoteDeadline()` を新設）

2 が必須。`scheduleTimeoutAt()` は**貼り直す前に既存タスクをキャンセル**するため、ローカルキューだけで
再計算すると remote が頼っていた起床を消して二度と戻さない。1 だけでは直らない。

**回帰テスト**: `queuedRequestTimesOutOnItsOwnDeadlineWithoutOutsideHelp` — `checkTimeouts()` を呼ばず
release もしない。修正前は `expected: <FAILED> but was: <QUEUED>`（500ms の期限に 10 秒待っても QUEUED）。

### F1a: 不正な `timeoutUnit` が「タイムアウト無効」に化ける（優先度: 中・**修正済み**）

`RemoteQueueEntry` は `TimeUnit.valueOf(timeoutUnit)` の
`IllegalArgumentException` を捕まえて `deadlineMs = 0` にする。`isTimedOut()` は
`timeoutDeadlineMillis > 0` を要求するので、**0 は「期限なし」= 無期限待ち**を意味する。

つまり `timeoutUnit: "MINUTE"`（正しくは `MINUTES`）というタイポは、
**5 分で諦めるはずの要求を、永久に待つ要求に変える**。しかも要求は 202 で受理されるため、
パイプライン側に手掛かりが出ない。

非対称性が根拠になる: 同じ「列挙値のタイポ」でも `resourceSelectStrategy: "NOPE"` は
400 `INVALID_REQUEST` で弾いている。片方だけ黙って通すのは一貫していない。

> F1 とは別物。F1 は「期限が予約されない」（正しい単位でも起きる）、F1a は「期限がそもそも 0 になる」。
> F1 を直しても F1a は残った。

**分類（2026-08-11 の判断）**: ローカルは `LockStep.setTimeoutUnit()` で**検証して例外を投げる**（#1010 由来）ため
**ローカルでは顕在しない**。`QueuedContextStruct` の同等分岐は DSL から到達不能な防御。
remote は JSON から読んで `LockStep` の setter を通らずに渡るため、到達不能だったはずの分岐に到達する。
**「検証を欠いた新しい入力経路」を作ったのは #1055** という理由で ① 扱い（本 PR で修正）とした。

**修正 = F2a と同じ 1 コミット（A7）**: `RemoteApiV1Action` の JSON パースを厳格化。
解釈できない値は既定に落とさず **400 `INVALID_FIELD_VALUE`**。

### F2a: `quantity` の非数値が「全件ロック」に化ける（優先度: 中・**修正済み**）

`optInt("quantity", 0)` は解釈不能な値に対し既定の 0 を返す。label 指定では 0 は
「マッチする全件」を意味する（S15 が検証している正しい仕様）。したがって
`quantity: "2"` のつもりで型を間違えた要求は、**1 台のつもりでプール全体をロックする**方向に広がる。

拒否ではなく**要求範囲の拡大**に倒れる点が問題で、失敗するより静かに悪い。

**分類**: ローカルの `quantity` は `int`。DSL では型変換で落ち、freestyle の String 経路も
`Integer.parseInt` で例外になる。**「不正な値が黙って全件に化ける」経路は remote だけ**で、
その JSON パースは #1055 が追加したコード → ① として本 PR で修正（A7）。

**F2b（負値）は対象外**: `LockableResourcesStruct` の `if (quantity > 0)` は
`e8425b5`（Label/Quantity 拡張、#1055 以前）由来で、`quantity <= 0` = 全件は共有パスの仕様。
ローカル `lock(label:'x', quantity:-1)` でも同じ挙動 → ② として無視。

### F3: リソース名に含まれるカンマで combined variable が曖昧になる（優先度: 低〜中・**対象外**）

`lock(variable: 'V')` は取得したリソース名をカンマ連結して `V` に入れる（S10/S14/S15 が検証済み）。
名前自体がカンマを含むと連結結果は曖昧になる。B03 の実測:

- ロックしたリソース: 1 件（`b03-comma,inside-<stamp>`）
- `V.split(',')` の結果: **2 要素**（どちらも存在しない名前）
- `V0`: 正確

**分類**: `String.join(",", ...)` は `018e913^`（#1055 マージ前）から存在し、
現在は local と remote が同じ `buildLockEnvVars()` を共有しているだけ。
ローカル `lock(resource:'a,b', variable:'V')` でも同一に発生する → ② として**実装変更は見送り**。

インデックス付き変数（`V0`, `V1`, ...）は影響を受けないため、**実害はドキュメントで回避可能**。
「複数リソースを扱うときは `V` を split せず `V0..Vn` を使う」ことを README に明記するのが最小の対処。
名前にカンマを禁止する検証を入れるなら local `lock()` と揃える必要があり、範囲が広がる。

---

## 5. ハーネス側で見つかった欠陥（今回修正済み）

### H1: 失敗したシナリオがレポートに何も残さなかった

22 シナリオが `scenario-details.md` をスクリプト末尾のヒートドキュメントで生成しており、しかも
チェックポイント表に `PASS` を**べた書き**していた。つまり:

- 成功時: 計算していない「PASS」の表が出る
- **失敗時: 末尾に到達しないのでファイルごと生成されず**、レポートには
  「Details file is not available」だけが残る

診断情報が最も必要な場面で最も情報が無くなる構造だった。`lib/scenario.sh` で
判定した場所で記録し、EXIT トラップで必ず書き出すよう変更。`set -e` による予期しない停止も
「どのステップの途中で落ちたか」を含む ABORT 行として記録される。

### H2: S08 が前回実行のリソースを掴んでいた

S08 は固定ラベル `hw` を使っていた。ラベル取得は実行をまたいでマッチするため、
**前回実行が残した `s08-hw-board-<古い stamp>` を掴んでいた**。旧アサーションが
`^HW_LOCK=s08-hw-board-` という前方一致だったため、どちらを掴んでも通っていた。

厳密一致に変えた結果、検証中に実際に検出された（`expected=...1786369030 actual=...1786367567`）。
S14/S15 は既に stamp 付きラベルを使っていたので、S08 だけの取りこぼし。
ラベルを stamp 付きにし、加えて `drop_resources` によるリソース後始末を入れた。

> 副次的に、これは**スケールの問題でもある**: E2E は実行ごとにリソースを増やし続け、
> `start.sh --clean` を挟まない連続実行ではカタログが単調増加する。

---

## 6. 隣接する既知の空白: 負荷スイートの L01–L03 が未実装

`LOAD_TEST_SPECIFICATION.md` は G01 に加えて L01 `contention-storm` / L02 `throughput-acquire` /
L03 `sustained-soak` を定義しているが、`run-load.sh` は `ONLY="grid-storm"` を代入するだけで
**`--only` を解析しておらず、`$ONLY` を一度も参照していない**。3 つとも仕様のみで実体が無い。

このうち **L03 `sustained-soak` は §3.3 の「持続/リーク」そのもの**であり、
スケール軸の空白を埋めるうえで最も直接的な未実装項目。

---

## 7. 追加した B シリーズ一覧

| ID | シナリオ | 軸 | 検証点 | 所要 |
|---|---|---|---|---|
| B01 | `acquire-payload-boundaries` | data | 拒否 13 種（status+errorCode）、1 MiB 上限の両側、未検証値 4 種の観測 | 約 3 秒 |
| B02 | `lease-lifecycle-edges` | time | 状態不整合な heartbeat/poll/release、二重 release、QUEUED 取り下げ、TERMINAL_TTL の両側 | 約 2.5 分 |
| B03 | `resource-name-boundaries` | data | 空白 / 多バイト / 244 文字 / カンマ入り名の往復、カタログの健全性 | 約 1 分 |
| B04 | `catalog-cache-ttl` | time | TTL 内は据え置き / TTL 超で追随 / サーバー停止中の描画継続 / 復旧 | 約 1.5 分 |
| B05 | `acquire-abort-races` | time | QUEUED 中断＝幽霊ロック無し、ACQUIRED 中断＝STALE 前に解放 | 約 1.5 分 |
| B06 | `catalog-scale` | scale | 100/500/2000 件の応答時間・サイズ・全件性、discovery 負荷下の acquire レイテンシ | 約 2 分 |
| B07 | `queue-depth-scale` | scale | 同一リソースに 1/10/50 件の待機を積んだときの昇格スループットと公平性（飢餓の有無） | 約 2 分 |

実行: `./run-e2e.sh --only boundary`（`lib/scenarios.tsv` の series 列）。

B01 は 21 チェックポイントを 3 秒弱で回す。**API を直接叩く境界テストは
pipeline 経由のシナリオに比べて桁違いに安いので、データ境界はここを厚くするのが費用対効果が高い。**

---

## 8. 次にやるなら（優先度順）

| # | 項目 | 軸 | 理由 |
|---|---|---|---|
| 1 | `MAX_CONSECUTIVE_POLL_FAILURES` の両側（19 回復帰 / 20 回で fail-closed） | time | クライアント唯一の「諦める」閾値。テスト 0 件 |
| 2 | サーバー再起動中のクライアント保持 | time | 運用で最も起きやすい。in-memory レコードとリソース XML の非対称 |
| 3 | release と queue promotion の競合 | time | 実装コメントが「復旧不能」と名指ししている既知の危険箇所 |
| 4 | L03 `sustained-soak` の実装 | scale | 仕様済み・未実装。レコードマップと registry のリーク検出 |
| 5 | `exposeLabel` 空文字の露出範囲 | data | 設定 1 つで影響半径が最大 |
| 6 | `clientId` の UI 描画エスケープ | data | C2 で新設された経路 |

---

## 参照

- `dev/docs-j/E2E_TEST_SPECIFICATION.md` — シナリオ仕様（S01–S22）
- `dev/docs-j/LOAD_TEST_SPECIFICATION.md` — 負荷仕様（G01 実装済 / L01–L03 未実装）
- `dev/jenkins-env/lib/scenarios.tsv` — シナリオ登録簿（id / series / controllers / axis）
- `dev/jenkins-env/lib/timings.sh` — 時間定数とドリフト検出
- `dev/jenkins-env/lib/scenario.sh` — チェックポイント記録と details 生成
