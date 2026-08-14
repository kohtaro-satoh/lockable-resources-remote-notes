# 実装計画（Phase 1 / M2 + M3）

> **設計書:** [`design_01.md`](./design_01.md)（本計画の各項目は設計書の節を参照する）
> **作業ブランチ:** `feature/issues-1025-remote-lr`
> **基点:** `upstream/master` = `origin/master` = **`27422e3`**（2026-08-08 時点）
> **作成日:** 2026-08-08

---

## 方針

- **1 機能 1 コミット。** 混ぜない。レビュアが 1 コミット単位で意味を追えることを優先する
- **実装順: バグ fix 系 → 機能追加系 → ドキュメントメンテ。** 機能追加のうち **LR 画面系は最後**に回す
- **ユニットテストは該当コミットに同梱**する（Jenkins プラグインの慣例。テストだけ後追いにしない）
- **help / Messages / JCasC も該当機能のコミットに同梱**する（設定を足したコミットが help なしで着地しない）
- **E2E シナリオは notes リポジトリ側の作業**なので plugin のコミットには含めない（[§並行作業](#並行作業notes-リポジトリ側)）
- コミットメッセージは英語・命令形・prefix なし。**`Co-Authored-By` は付けない**

---

## Phase A: バグ fix（7 コミット）

先に入れる。以降の機能追加が同じファイルに触るため、バグ fix が後ろに回ると差分が混ざる。
A6・A7 は remote 経路にしか存在しない欠陥で、A1〜A5 と同じく #1055 由来。

### A1. `lockCause` がリモート保持を考慮していない

- [x] `Report the remote holder in the lock cause`
- **対象:** `LockableResource#getLockCause()` / `#getLockCauseDetail()`（`LockableResource.java:652`〜）
- **内容:** remote 保持中の資源が `locked by null at <unknown>` と表示される。`remoteLockedBy != null` で分岐させ、
  `clientId` と `RemoteLockRecord#getAcquiredAt()` を使う。Held By 列（氏の実装）と同じ情報源を参照する
- **露出範囲:** REST API の `lockCause` と、**ローカル待機ジョブのコンソール**の両方。後者は「なぜ待たされているか」を
  調べる利用者が最初に見る場所
- **テスト:** remote 保持中の資源の `lockCause` に clientId と取得時刻が入ること／local 保持時は従来どおり
- **設計書:** §6.1

### A2. QUEUED の release 直後に `GET /acquire/{lockId}` が 404 になる

- [x] `Keep a released queued request until its terminal TTL`
- **対象:** `RemoteLockManager#release()`
- **内容:** QUEUED に対する release が `markFailed("RELEASED")` の直後に `records.remove()` するため、
  直後の GET が 404 を返す。**terminal TTL（120s）保持に変更**し、`records.remove()` は掃引に一本化する。
  **新状態 `CANCELLED` は追加しない**（M1 の「クライアントからは CANCELLED を発行しない」方針を維持）
- **テスト:** release 直後の GET が **200 `FAILED` / `RELEASED`**／TTL 経過後は 404 に戻る／
  ACQUIRED の release は従来どおり（回帰）
- **設計書:** §3.3

### A3. 404/410 のラベルが実態とねじれている

- [x] `Report a vanished remote record as a missing record, not a timeout`
- **対象:** `RemoteLockSession#pollOnce()` の 404/410 分岐（現 249-290 行）
- **内容:** 到達可能な `!bodyStarted` 側を「record が存在しない（サーバ再起動の可能性）」寄りの表現に**一本化**する。
  正当な allocate timeout はサーバ側 FAILED 経路に一本化済みである前提をコメントで明示。A2 と併せて
  **404 が出る条件そのものが減る**
- **前提確認済み:** 当該分岐は `73a2d3b`＋`7fd218b` で全行が当方のコード（氏の `9ffade8` は acquire 時ログのみ）
- **テスト:** 既存の 404/410 テストの文言更新（回帰）
- **実装時の発見:** E2E S18 の CP03 は「waiter コンソールに `LOCK_WAIT_TIMEOUT` がある」ことを見ているが、
  **旧実装では 404 分岐が `LOCK_WAIT_TIMEOUT` を自ら生成していた**ため、M1I がリグレッションしても CP03 は緑のままだった。
  一本化により 404 経路は "server may have restarted or the record expired" を出すので、**S18 が本来の回帰ガードになる**。
  新メッセージには既存判定に合わせて `server may have restarted` の語を残した（S18 の除外 grep と `analyze_load.py` の分類が
  そのまま効く）
- **設計書:** §6-1 / §10 Q1

### A4. `variable` 指定が空 `lockEnvVars` で注入されない

- [x] `Inject the remote lock variable even when no env vars are returned`
- **対象:** `LockStepExecution#withRemoteMetadata()`（`LockStepExecution.java:340`、呼び出しは `:168`）
- **内容:** 空 `lockEnvVars` の条件の内側に入っているため注入が落ちる。条件の外に出し、
  **`variable` 指定があれば常に注入**されるようにする
- **テスト:** `lockEnvVars` が空でも `X_SERVER_ID` / `X_LOCK_ID` と variable が入ること
- **設計書:** §6-7

### A5. Queue タブが remote 行を正しく扱っていない（3 件まとめて 1 コミット）

- [x] `Fix the queue tab handling of remote entries`
- **対象:** `LockableResourcesRootAction`（`QueueStruct` / `getQueuePage` / `doChangeQueueOrder`）、
  `tableQueue/table.jelly`、`tableQueue/queue-too-long.js`
- **内容:**
  1. **Change Position ボタン** — remote 行では描画しない（`doChangeQueueOrder` は local キューのみ扱うため、
     押すと必ず `423`。実測済み）
  2. **表示順** — local 全件 → remote 全件の単純連結をやめ、**priority 降順でマージしてから index を振る**
     （実際の昇格順＝`proceedNextContext` と一致させる）
  3. **フリーテキスト filter** — `getRemoteRequest()` / `getRequestedBy()` を filter 分岐に追加し、remote 行にも効かせる
- **1 コミットにする理由:** 3 件とも「Queue タブが remote 行を local 行と同じには扱えていない」という同一機能面の欠陥で、
  同じファイル群に触る。分割するとレビュー時に 3 つの差分を行き来することになる
- **テスト:** マージ順序のユニット（local+remote を priority 降順に並べ index が昇格順と一致）
- **実装時の判断:** 並べ替えは `Queue.sortByPromotionOrder()` を新設し、**連結済みリストを priority 降順で安定ソート**する。
  `List.sort` が安定なので「local を先に連結 → 同priorityでは local が前」が自動的に成立し、
  `proceedNextContext`（同値なら local 優先）と一致する。個別の比較規則を書かずに済む。
  サーバ側 `doChangeQueueOrder` には手を入れない（remote id は範囲チェック通過後に
  `error_queueDoesNotExist` で落ちるため、新しい i18n キーを増やす必要がない）
- **設計書:** §6-3 / §6-5 / §6-6

### A6. remote の allocate timeout が期限どおりに発火しない

- [x] `Enforce the allocate timeout of a queued remote request`
- **対象:** `LockableResourcesManager#queueRemote()` / `#getNextQueuedContext()`
- **内容:** remote のキューエントリは `timeoutForAllocateResource` から deadline を正しく計算するが、
  **それを評価しに来る起床を予約しない**。結果 `timeoutForAllocateResource` は待ち時間の上限として機能せず、
  **他の理由でキュー整備が走ったときにしか発火しない**（実測では保持者の解放時）。
  ローカル経路は `queueContext()` と `getNextQueuedContext()` の 2 箇所で `scheduleTimeoutAt()` を呼んでいる:
  1. `queueRemote()` に同じ「期限が現行より早ければ起床予約」を追加
  2. `getNextQueuedContext()` の最早期限計算を**両キューにまたがる**ものにする（`earliestRemoteDeadline()` 新設）
- **2 が必須な理由:** `scheduleTimeoutAt()` は**貼り直す前に既存タスクをキャンセル**する。
  ローカルキューだけで再計算すると、remote が頼っていた起床を消して二度と戻さない。1 だけでは直らない
- **影響:** リソースが解放されない限り、有限の待ちを要求したクライアントが無期限に待つ。
  STALE 保持（管理者対応待ち）や長時間ビルドが相手だと実質無効
- **テスト:** `queuedRequestTimesOutOnItsOwnDeadlineWithoutOutsideHelp` —
  **`checkTimeouts()` を呼ばず release もしない**。既存の timeout テストはこれを手で呼んでおり、
  本番コードが決してやらないことを代行していたため緑のままだった
- **E2E:** S18 に CP08（期限どおりに発火したか）をハード判定で追加。
  旧 S18 は holder 保持 150s / 期限 130s と両者が近く、判定も `>= 120s` だったため
  「期限で失敗」と「解放で失敗」を構造的に区別できなかった。holder 保持を期限 +60 秒にして両者を離した
- **設計書:** §3.3（terminal TTL）と対になる、キュー側の期限

### A7. acquire エンドポイントが解釈できない値を既定値に落とす

- [x] `Reject acquire fields the endpoint cannot interpret`
- **対象:** `RemoteApiV1Action`（`AcquireRouter#doIndex` のパース区間）
- **内容:** `lock()` の DSL は型を Java から得るが JSON にその保証は無い。`optInt` / `optLong` / `optString` で
  読んでいるため、**解釈できない値が黙って既定値になり、要求の意味が変わる**。しかも「より多くやる」方向に倒れる:
  - `quantity` が非数値 → 0 → label では**全件**（1 台のつもりがプール全体）
  - `timeoutForAllocateResource` が非数値 → 0、`timeoutUnit` が不正 → deadline 無効 → **有限待ちが無限待ちに**

  解釈できない値は **400 `INVALID_FIELD_VALUE`** で返す。対象は `quantity` / `priority` /
  `timeoutForAllocateResource` / `timeoutUnit` / `extra[i].quantity`
- **ローカル等価の維持:** `timeoutUnit` は空白なら既定・小文字は正規化（`LockStep.setTimeoutUnit` と同一）。
  **`quantity <= 0` と `timeout <= 0` は従来どおり「無制限」**（ローカルでも同義なので新たに拒否しない）
- **後方互換（実測で確認）:** json-lib は `"2"` のような**数値文字列を数値として読む**ためこれは通す。
  **JSON の null は「未指定」扱い**（シリアライザが未設定を null で書くのは一般的で、拒否すると無意味に壊れる）
- **併せて直す同型の穴:** `optString(key, null)` は **JSON null に対し文字列 `"null"` を返す**。
  `"resource": null` が「null という名前のリソース」を探して 404、`"variable": null` が
  `null` という名前の env var を作る。`stringField()` に統一（absent / null / 空白 = 未指定）。
  数値だけ直して文字列を放置すると規則が半端になるため同一コミットに含める
- **テスト:** `acquireRejectsFieldValuesItCannotInterpret`（拒否側 6 件）＋
  `acquireStillAcceptsTheLooseFormsClientsActuallySend`（数値文字列 / null / 空白単位 / 小文字単位 / 負値 / null セレクタ）
- **E2E:** B01 が拒否 5 件と互換形 4 件を検証（26 チェックポイント）
- **B2 との関係:** ローカルの検証は 2 層ある — 意味検証（`LockStepResource.validate()`）と
  型/バインディング検証（`LockStep.setTimeoutUnit()`、`int` 型そのもの）。B2 は前者を canonical に委譲する。
  A7 は**後者に対応物が無い**という別の欠落を埋めるもので、A7 → B2 の順に入れる
  （B2 が `MISSING_TARGET` を廃止するため、A7 のテスト期待値は B2 側で更新される）

---

## Phase A': テスト補強（6 コミット）

バグ fix の直後、機能追加の前に置く。**verify だけが PR に載る層**であり（E2E / load は notes リポジトリで
レビュアには見えない）、remote LR の規模に対してクライアント側の分岐カバレッジが 32% だったため。

着手前の実測（jacoco、`-P enable-jacoco`）: **remote 関連で行 78.7% / 分岐 63.3%**、未到達 275 行。
最も低いのが `RemoteLockSession`（行 54.8% / 分岐 32.4%）と `RemoteApiClient`（69.5% / 53.5%）。

**方針: 数字を目標にしない。** 「誰にも触られておらず、壊れたら実害がある」順に埋める。
行を通すだけのテストは書かない（実際、死んだコードは 1 件テストではなく削除した）。

### T1. テスト用リモートサーバをスクリプト可能にする

- [x] `Let the test remote server be scripted`
- **対象:** `RemoteServerFixture`（`LockStepRemoteTest` の入れ子クラスから独立ファイルへ抽出）
- **なぜ最初か:** 既存 fixture は **ACQUIRED 固定 ＋ 503 のみ**しか返せず、これがクライアント側の
  低カバレッジの直接原因。ここに一度投資すると T2〜T5 がまとめて書けるようになる
- **追加した表現力:** n 回 QUEUED の後 ACQUIRED / 終端状態（FAILED・SKIPPED＋errorCode）/
  status の n 回連続失敗 / heartbeat の任意ステータス / `/resources` / **同一ポートでの再起動**
- **検証:** 既存 15 テストが**無改変で通る**ことを確認（抽出が挙動を変えていない保証）

### T2. クライアントが受け取った答えにどう反応するか

- [x] `Cover what the client does with the answers it gets`
- **対象:** `RemoteLockSession`（8 テスト新規）
- **内容:** QUEUED→昇格 / 終端 FAILED（`LOCK_WAIT_TIMEOUT`）/ 終端 SKIPPED /
  404・410（**A3 の「タイムアウトと誤ラベルしない」を守る**）/ 一時的なポーリング失敗の乗り切り /
  **連続失敗の閾値超過で fail-closed**（クライアント唯一の「諦める」条件。約 60 秒かかる）/
  heartbeat 410 でも body を中断しない
- **60 秒テストについて:** `MAX_CONSECUTIVE_POLL_FAILURES` は `private static final` で
  ポーリング間隔 3 秒と組み合わさる。**テスト都合でプロダクションの可視性を変えない**判断
  （既存 `ResourceManagementTest` は 159 秒なのでスイート内では軽い方）

### T3. 再起動がリモートロックに何をするか

- [x] `Cover what a restart does to a remote lock`
- **対象:** `RemoteLockSession#onResume`（3 テスト新規）
- **着手前は 3 層すべてで未到達**（行 0% / 分岐 0/12）。E2E・load が停止するのは常に**サーバ側**
  （jenkins-b）で、**クライアント側を再起動するテストが存在しなかった**
- **内容:** 待機中の再起動→ポーリング再開して昇格を受け取る / **保持中の再起動→リモートロックを
  best-effort 解放**（サーバに孤児リソースを残さない）/ 一時停止サーバ待ちの再起動→fail-closed
- **fixture は同一ポートで再起動する。** 別ポートでは「移動したサーバに繋がらない」ことしか証明できない
- **結果: バグは出ず。** 3 分岐とも実装は正しく動作していた

### T4. 他コントローラのカタログを読む

- [x] `Cover reading another controller's catalogue`
- **対象:** `RemoteApiClient#listResources`（5 テスト新規。着手前は**分岐 0/8**）
- **内容:** 全項目のパース / **フィールド欠落への耐性**（古いサーバ。`acceptNewAcquires` 欠落は「停止中」でなく
  「稼働中」）/ 空カタログは正常 / **403 と到達不能は例外として上げる**
- **403 を空カタログとして返さないことが要点:** キャッシュの stale フォールバックはこの区別に依存する。
  空リストとして読むと「このサーバは何も公開していない」という別の（誤った）主張になる

### T5. ルーティング判断と陳腐化したカタログ表示

- [x] `Cover the routing decisions and the stale catalogue view`
- **対象:** `RemoteLockRouting`（分岐 64.7%→85.3%）/ `RemoteAcquireState.fromString` /
  `RemoteCatalogCache.fetch`
- **ルーティング:** remote か否か・どのサーバか・表示名。**間違えてもエラーにならず、別コントローラの
  リソースを黙って掴む**ため実害が大きい。delegated mode の上書きを両方向から、空白がサーバ名として
  扱われないことも検証
- **状態パース:** 新しいサーバが未知の状態を返したら UNKNOWN（＝失敗扱いでビルド停止）。
  例外を投げると前方互換のサーバが「壊れたサーバ」になる
- **カタログキャッシュ:** 既存テストは「キャッシュ空のまま失敗」のみ。重要なのは**一度応答した後に落ちた**
  場合で、「最後に知っていた内容を保つ」か「何も公開していない」と言い始めるかの分かれ目

### T6. 呼ばれていないアクセサの削除

- [x] `Drop a remote lock record accessor nothing calls`
- **対象:** `RemoteLockRecord#getResourceName`
- **内容:** #1055 で追加されて以来、プラグイン・jelly ビュー・テストのいずれからも呼ばれていない（4 行・4 分岐）。
  カバレッジレポートを読んでいて見つけた
- **なぜテストでなく削除か:** テストを書けば数字は上がるが**コードは未使用のまま**で、
  読む人に「見つけられなかった呼び出し元があるはず」と思わせる。`getAcquiredResourceNames` は無傷

### Phase A' の結果

| | 着手前 | 完了後 |
|---|---|---|
| 行 | 78.7% | **88.4%** |
| 分岐 | 63.3% | **72.5%** |
| 未到達行 | 275 | **150** |
| `RemoteLockSession` | 54.8% / 32.4% | **79.0% / 63.2%** |
| `RemoteApiClient` | 69.5% / 53.5% | **84.5% / 59.6%** |

テスト数 435 → **457**（+22）。verify **BUILD SUCCESS・全ゲート ok**（plugin `29c05d3`）。

**残した低カバレッジと理由**: `LeaseRouter`(2 行) / `RemoteRouterAction`(4 行) は `getDynamic` の委譲のみ。
`RemoteApiV1Action.LeaseResource` の heartbeat 410 分岐は **E2E B02 が実物で両方通す**。
`RemoteLockRequest.from` の extra 変換は E2E S10/S14 が実経路で通す。
いずれも「ユニットで足すより E2E が実物で通す方が意味がある」と判断した。

---

## Phase B: 機能追加（LR 画面以外、5 コミット）

### B1. `inversePrecedence` の透過等価

- [x] `Apply inversePrecedence to remotely queued requests`
- **対象:** `LockableResourcesManager#queueRemote()`
- **内容:** local の `queueContext` は `inversePrecedence && priority == 0` のとき **index 0 に挿入**するが、
  `queueRemote` は priority しか見ておらず `inversePrecedence` を参照しない（ワイヤでは運ばれて
  `RemoteLockRequest` に保持されている）。**local と同じ挿入規則を反映**する。
  値は `entry.getLockRequest().isInversePrecedence()` で取得できる
- **注意:** これは「remote 独自ルールの追加」ではなく、**local 規則の未反映を直す**もの
- **テスト:** remote 要求が `inversePrecedence=true` でキュー先頭に入る（local と同じ挿入位置）
- **設計書:** §10.1 対応 1 / §6-8

### B2. 検証層の再設計（Wire → Admission → Canonical）

- [x] `Delegate remote request validation to the canonical validator`
- **対象:** `RemoteApiV1Action`（境界）、`RemoteLockManager#enqueue()`、必要なら `RemoteResolver`
- **内容:**
  - 境界の自前チェック **`MISSING_TARGET` と `INVALID_SELECT_STRATEGY` を削除**（canonical の部分コピーであり、
    前者は `allowEmptyOrNullValues` を無視するため **local が受理する要求を remote が 400 で弾く**破れになっている）
  - `enqueue` を **admission → canonical** の順にし、`LockStepResource.validate(...)` を呼ぶ。
    `IllegalArgumentException` は**そのまま伝播**させ、`RemoteApiV1Action` が catch して
    **400 `INVALID_REQUEST` ＋ `ex.getMessage()`**（record は作らない＝現状の 400 群と同じ門前払い）
  - `extra` も canonical に乗せる（`ExtraResource` → `LockStepResource` を組んで list オーバーロード）
- **実装時の発見:** 境界の `MISSING_TARGET` を外すだけでは足りなかった。**解決側（`enqueue`）が空セレクタを弾く**ため
  `allowEmptyOrNullValues=true` でも 400 のままになる。設計 §3.5 の意図を満たすには
  **local と同じ「何もロックせず本体を実行する no-op リース」を返す**必要があり、`enqueue` にその分岐を追加した。
  また B1 のテスト 1 本（`inversePrecedence` + `priority` でキュー位置を確認するもの）は、
  この変更で**入力自体が 400 になり作成不能**になるため B2 で削除した（B1 コミット時点では有効なので B1 では残す）
- **これで変わる挙動 3 件:** `allowEmptyOrNullValues=true` の無指定が**受理**される／
  `priority != 0 && inversePrecedence` が **400**（§10.1 対応 2）／`resource` と `label` の同時指定が **400**（M1E-2 を閉じる）
- **順序が重要:** admission を先に置くことで **未知/未公開とも一律 404** が維持される（canonical を先に走らせると
  未知 label が 400・未公開が 404 となり存在が漏れる）
- **テスト:** 上記 3 挙動＋未知/未公開が 404 のまま（回帰）＋ `INVALID_REQUEST` のメッセージ
- **設計書:** §3.5 / §10.1

### B3. メンテナンススイッチ "accept new acquires: ON/OFF"

- [x] `Add a maintenance switch for the remote acquire endpoint`
- **対象:** `LockableResourcesManager`（`acceptNewAcquires`、既定 `true`）、`RemoteApiV1Action`、
  `LockableResourcesManager/config.jelly` ＋ `help-acceptNewAcquires.html` ＋ `Messages.properties` ＋ JCasC、
  クライアント側は `RemoteLockSession`
- **内容:**
  - OFF のとき **`POST /acquire` だけが 503 `ACQUIRES_PAUSED`**。`GET /acquire/{lockId}` / heartbeat / release は素通し
  - **クライアントは 503 でリトライ**する（`timeoutForAllocateResource` の範囲内、ポーリング間隔。INFO は 1 回だけ）。
    現状の「acquire 失敗＝即 abort」のままでは要望の目的（B のメンテ中に A が困らない）を満たさない
  - **既にキューにある要求は昇格を続ける**（受理済みは履行し、キューが drain する）
- **未確定（氏に未質問。PR で提示して合意を取る）:** 上記リトライと drain の 2 点。相違があれば PR で差し替える
- **テスト:** OFF で 503／同じ状態で heartbeat・release・GET が成功／ON 復帰で再び受理／既存キューの昇格が止まらない／
  クライアントが 503 でリトライし timeout まで粘る
- **実装時の判断 3 件:** (a) **リトライ中の再起動は fail-closed**。`onResume` は lockId が無いと静かに return するため、
  そのままだとステップが永久待ちになる。`acquirePaused` を見て失敗させる（この時点でサーバ側にロックは存在しない）。
  (b) 既定値は `allowEphemeralResources` と同じ**フィールド初期化子**で表現（同一クラス内の既存パターンに合わせる）。
  (c) 設定項目追加により **JCasC のエクスポート期待値 `casc_expected_output.yml` が不一致**になり既存テストが落ちた。
  期待値・CasC サンプル・アサーションを更新済み（設定を増やすたびに発生するので次回以降も要注意）
- **設計書:** §3.4

### B4. `GET /resources`

- [x] `Add the remote resources discovery endpoint`
- **対象:** `RemoteApiV1Action#getDynamic`（`resources` 分岐を追加）
- **内容:** 公開中の資源一覧と、**サーバ側の受付状態**を 1 回のスナップショットで返す
  - 資源ごと: `name` / `labels` / `description` / **`state`（`FREE` / `LOCKED` / `RESERVED` / `QUEUED`）** /
    `heldByKind`（`LOCAL_BUILD` / `REMOTE_CLIENT` / `ADMIN`）/ `heldByClientId`（REMOTE_CLIENT 時のみ）/
    `since` / `queuedCount`
  - 封筒: **`acceptNewAcquires`**（B3 のスイッチ状態。別エンドポイントに割るとキャッシュ不整合で
    「FREE と表示しつつ受付停止中」の画面が作れてしまうため、同一スナップショットで返す）
  - **ビルド名 / ビルド URL / `reason` / `note` は返さない。** B のジョブ名を A の LR ページ閲覧者に
    出さないため（`RemoteUse` 権限は B 全体の READ とは別物）
  - **メンテ中でも資源状態は真実を返す**（FREE は FREE）。「取得できない」は画面側の表現で伝える
  - 公開フィルタは既存の `getExposeLabels()` を再利用。`remoteApiEnabled=false` では既存 4 本と同型で
    **403 `REMOTE_API_DISABLED`**。ページングは持たない
- **テスト:** exposeLabel フィルタが効く／未公開資源が漏れない／**4 状態が正しく出る**／
  **ビルド名・reason・note が漏れない**／`acceptNewAcquires` が反映される／無効時 403
- **実装メモ:** 公開判定は `RemoteResolver.exposedResources()` に切り出して `isExposed` を再利用（remote 独自判定を増やさない）。
  E2E は S19 が Phase C の計画なので、この時点ではユニットのみ
- **設計書:** §3.1

### B5. 接続ごとの有効／無効（`enabled`）

> **2026-08-10 に追加。** 計画時には無かった項目。C1・C2 の後、**C3 の前**に実装する
> （C3 の `/resources` 取得・表示が「無効な server は対象外」を前提に書けるため）。

- [x] `Let a client disable a configured remote without deleting it`
- **対象:** `RemoteConnection`（`enabled`、既定 `true`、**`@DataBoundSetter`**）、`RemoteConnection/config.jelly`
  ＋ `help-enabled.html`、`RemoteLockRouting`、`LockableResourcesManager#doCheckForcedServerId`、
  `tableRemote/table.jelly`、JCasC（`casc_expected_output.yml` 含む）
- **動機:** B3（サーバ側の「新規貸出を止める」）と対になる、借りる側のスイッチ。現状は設定を消すか URL を壊すしかなく、
  消すと `credentialsId` の紐付けも失われる
- **意味論:**
  - 無効な server を `serverId:` で明示指定 → **即失敗**（ローカルにフォールバックしない）
  - **保持中のリースは切らない**（heartbeat / release は継続。切ると相手側に資源が残る）
  - `forcedServerId` が無効な server を指す → `doCheckForcedServerId` の警告に追加
  - Remote タブで、無効な server に属する保持中エントリにその旨を表示
- **注意:** `@DataBoundConstructor` の引数を増やすと既存 JCasC yaml が壊れるので **setter で足す**。
  **`casc_expected_output.yml` の更新が必須**（B3 で踏んだ罠）
- **テスト:** 無効 server への明示指定が失敗する／保持中リースの heartbeat・release が通る／
  `forcedServerId` が無効を指すときの警告／JCasC の往復
- **設計書:** §4.0 / §7.12

---

## Phase C: 機能追加（LR 画面系、4 コミット）

**最後に回す。** #1035 で体裁が変わった直後であり、[§9.4](./design_01.md) の新旧並走比較で見た目を確認しながら詰める。

### C1. クライアント側レジストリ（表示のデータ源）

- [x] `Track the remote locks this controller holds or waits for`
- **対象:** 新規 `RemoteClientRegistry`（`@Extension`、transient）、`RemoteLockSession` から登録・解除
- **内容:** remote ロックの client 側状態は step ごとの `RemoteLockSession` にしかない。コントローラ横断で集約する
  レジストリを新設する。key = `lockId`、value = `serverId` / 要求内容 / state(QUEUED|ACQUIRED) / 取得済み資源名 /
  `enqueuedAt` / `acquiredAt` / 発信ビルド。**永続化しない**（再起動時は `onResume` から再登録）。
  `Run` は弱参照＋`getFullDisplayName()` のスナップショットを併せ持つ
- **副産物:** M-1（`onResume` で displayTarget が劣化する）が解消する
- **実装時の発見:** `GET /acquire/{lockId}` が**取得済みリソース名を返していなかった**。`lockEnvVars` は `variable`
  指定時しか名前を含まないため、クライアントは「自分が何を掴んでいるか」を知る手段が無い。
  Resources 列に必要なので、レスポンスに `resources` を追加した（後方互換の追加フィールド）
- **テスト:** acquire/release での登録・解除／`onResume` 後の再構築／ビルド削除時に落ちない
- **設計書:** §4.2

### C2. Remote タブ（保持中／待機中の可視化）

- [x] `Show the remote locks on the lockable resources page`
- **対象:** `LockableResourcesRootAction`、`_content.jelly`（タブ追加）、新規 `tableRemote/table.jelly` ＋ `.properties`
- **内容:** #1035 のタブ構成（Overview / Resources / Labels / Queue）に **Remote タブを 1 つ足す**。
  列は Server（`serverId`）/ Request / State / Resources / Requested by / Since。
  **「クライアント側のキャッシュビューであり、リモートの権威状態ではない」旨をタブ内に常時表示**（仕様の明示要件）。
  **操作（cancel / release）は出さない**（Phase 1 は可視化まで）。
  待機中エントリについては、**リモートが受付停止中であることが待機理由なら**それを示す（B3 のリトライと対）
- **暫定判断:** タブにするか Resources の列にするかは **§9.4 の新旧並走比較で最終決定**する。まず (a) タブで作る
- **実装時の発見:** **タブバー全体が「ローカル資源が 1 つ以上ある」条件の内側**にあり、資源ゼロだと Remote タブごと消えていた。
  delegated mode のコントローラは**ローカル資源ゼロが正常**なので、タブバーと空状態の条件を
  「ローカル資源がある **or** remote 関係が設定済み」に変更し、資源ゼロのときは Remote タブを初期表示にした
  （Overview に出すものが無いため）
- **設計書:** §4.3 / §10 Q2 / Q6

### C3. delegated mode の表示（バッジ＋並存＋`/resources` キャッシュ）

- [x] `Show the delegated target's resources next to the local ones`
- **対象:** `_content.jelly`（バッジ）、Remote タブ、`GET /resources` のクライアント側キャッシュ（新規または `RemoteApiClient`）
- **内容:**
  - `forcedServerId` 設定時にページ上部へ **delegated バッジ**を常時表示（ローカル資源が他コントローラからは
    引き続きロック可能である旨も添える）
  - **ローカル資源は隠さない。** リモートの公開資源を**並べて**表示する（[§5.0](./design_01.md) の方針変更）。
    ローカル側には「このコントローラの `lock()` 解決には使われない」と明示する
  - `GET /resources` の結果は **TTL 10s の短期キャッシュ**（状態を含むため 60s では誤情報になる）。取得失敗時は最後に取れた内容＋stale 表示に
    フォールバック（表示は best-effort。fail-closed はロック取得の話）。取得はページ表示スレッドではなく非同期
  - **実装:** `RemoteCatalogCache`（`@Extension`）＋ スナップショット型 `RemoteCatalog`。描画スレッドは HTTP を叩かず、
    古ければバックグラウンド更新を投げるだけ。B5 で無効化された接続は**そもそも取得しない**。`setRemotes` で全破棄
  - **メンテナンス中の表現** — `acceptNewAcquires=false` のとき「リソースは見えるが lock はできない」と示す
    （資源の状態表示は真実のまま変えない）。C4 のサーバ側バナーと対になるクライアント側の表現
- **設計書:** §5.0 / §5.1 / §5.2

### C4. サーバ側の一時停止バナー

- [x] `Show a banner while new remote acquires are paused`
- **対象:** `_content.jelly`（または Overview カード）
- **内容:** `acceptNewAcquires=false` のとき LR ページに一時停止バナーを出す（管理者が戻し忘れないように）
- **B3 と分ける理由:** B3 は API とクライアント挙動、こちらは画面。LR 画面系を後ろに寄せる方針に従う。
  レビュー上まとめたほうが良ければ B3 に畳んでよい
- **設計書:** §3.4

---

## Phase D: ドキュメントメンテ（2 コミット）

### D1. README

- [x] `Document the remote lockable resources feature in the README`（`30a0ed4`）
- **対象:** `README.md`
- **内容:** 現状 **remote 機能への言及がゼロ**（`grep -c -i remote README.md` → 0）。追記するのは 3 点:
  1. **Permissions 表に `RemoteUse` 行**（Implied by: Jenkins.ADMINISTER）。既存表の欠落＝不整合でもある
  2. **`lock(..., serverId:)`** と delegated mode（`forcedServerId`）の説明
  3. **Configuration as Code 例**に remote 系キー（`remoteApiEnabled` / `exposeLabel` / `clientId` /
     `forcedServerId` / `acceptNewAcquires` / `remotes[]`）。テストの `configuration-as-code-remote.yml` から抜粋できる
- **設計書:** §6.2 / §10 Q7

### D2. `remote-api-curl.md`

- [x] `Correct the remote API reference for the shipped behaviour`（`ded92ed`）
- **対象:** `src/doc/examples/remote-api-curl.md`（氏が追加したドキュメント）
- **内容:**
  - 状態表: **`EXPIRED` の誤記を削除**（サーバは返さない。`maxWaitSeconds` 導入時の将来枠と明記）、**`STALE` を追記**
  - `heartbeatIntervalSeconds` が **Phase 1 ではサーバ側で使われない**旨を注記
  - **エラーコード表を更新**（B2 で細分コードが `INVALID_REQUEST` に一本化される。`ACQUIRES_PAUSED` / 503 を追加）
  - `inversePrecedence` の記述を B1 の実装に合わせて更新（現状の「適用されない」記述が実態と合わなくなる）
  - `GET /resources` の節を追加
- **設計書:** §6-2 / §3.5 / §10.1

---

## 並行作業（notes リポジトリ側）

plugin のコミットには含めない。

- [ ] **E2E シナリオ 4 本追加**（`dev/jenkins-env/scenarios/` ＋ `run-e2e.sh` 登録）
  - [ ] S19 `remote-resources-endpoint` — `GET /resources` が exposeLabel 付きのみ返す／未公開が漏れない／
        **保持中資源が `LOCKED` ＋ `heldByKind` で返る／ビルド名・reason・note が漏れていない**
  - [ ] S20 `client-side-remote-view` — A が B の資源を保持中、A の LR ページに出る／解放後に消える
  - [ ] S21 `delegated-mode-page` — `forcedServerId=b` で delegated バッジと B の公開資源が出る／
        **ローカル資源も消えていない**／解除で元に戻る
  - [ ] S22 `remote-maintenance-switch` — B を OFF にすると A の新規 `lock()` が待つ（落ちない）／
        保持中リースは heartbeat・release とも無事／ON 復帰で取得に進む／
        **`GET /resources` の `acceptNewAcquires` が false になり、A の画面に反映される**
- [ ] **設計書の追従** — 実装中に判明した相違を `design_01.md` に反映（特に §3.4 の未確定 2 点、§10 Q6）
- [ ] **PR 本文の作成** — テンプレート準拠に加え、**「#1025 仕様との乖離と、そうした理由」セクション**を含める
      （転記元は設計書 §7.11 の 11 項目）。**issue 本文は更新しない**方針に変更済み（§10 Q8）
- [ ] **#1025 への導線コメント** — PR 提出**後**に「最新仕様は PR #X にある」と短く追記する

---

## 完了条件

- [ ] `dev/run-mvn-verify.sh` — BUILD SUCCESS、全ゲート ok（spotless / spotbugs / checkstyle / pmd）
- [ ] `dev/jenkins-env/run-e2e.sh` — 全 32 シナリオ PASS（S01〜S22 ＋ 境界 B01〜B07 ＋ D01〜D03）
- [ ] `dev/jenkins-env/run-load.sh --preset stress` — overlap 0 / HUNG 0。
      **LR ページが正式な挙動で更新されている状態のまま**計測する（§9.3）。
      `/resources` を **10s 間隔で相互に引く負荷を含める**（§10 Q5 で「含める」に確定。TTL 短縮で頻度が 6 倍）。
      ※ Phase B 時点ではクライアント側キャッシュが未実装のため、この負荷はまだ入っていない（Phase C で追加）
- [ ] **§9.4 の新旧並走比較** — a = 新版 / b = 旧版（現 master）で LR ページを見比べ、Q6 を最終決定。
      PR 用の修正前後スクリーンショットを取得
- [ ] ドキュメント整備 — `docs-e` の ph1-ms2 ミラー（PR 提出までに作成）
- [ ] **PR 本文に乖離セクション**（§7.11）を記載 — issue 本文を直さない代わりの唯一の記録場所になる
- [ ] 直前に `upstream/master` へ追従（マージまたはリベース）し、再検証

---

## 依存関係メモ

```
A1..A5  独立（ただし A2 → A3 の順に入れると 404 の文言調整が 1 回で済む）
A6      独立
A7      B1/B2 の前。B2 が MISSING_TARGET を廃止するので、A7 のテスト期待値は B2 が更新する
T1..T6  Phase A の後・B の前。T1 は T2〜T5 の前提（fixture の表現力）
B1      独立
B2      A2 の後（release まわりのテストと干渉しない順序）
B3      独立。ただし C4 が B3 に依存
B4      C2 / C3 の前提
C1      C2 の前提
C2      C3 の前提（タブの器を先に作る）
C4      B3 の後
D1/D2   すべての実装コミットの後（挙動が確定してから書く）
```

---

## 更新履歴

| 日付 | 内容 |
|---|---|
| 2026-08-14 (3) | **PR #1077 提出**（draft → ready）。GitHub Advanced Security が `ResourcesResource#doIndex` の verb 注釈欠落を CSRF リスクとして指摘。**上流 #1076 が隣の acquire status endpoint で同一指摘を `@GET` 付与＋リフレクション検査テストで解決していた**ため、同じ手当てを踏襲し `[B7]` として積み上げた（PR 提出済みのため amend でなく新規コミット。26 コミットに）。読み取り専用のエンドポイントなので `@RequirePOST` ではなく `@GET` が実態に合う。**ユニットテストは `doIndex` を直接呼ぶため Stapler のディスパッチを通らず、注釈の存在しか確認できない**。実 HTTP 経路での検証は E2E の S19 のみで、32/32 PASS で裏付けた。verify 463/0/1skip。**ci.jenkins.io の windows-21 で `LockStepWithRestartTest.testReserveOverRestart` が失敗するが、#1055 時点からの既知状態**（linux-25 は pass、ローカル linux も pass、本ブランチは当該テスト未変更） |
| 2026-08-14 (2) | **UI キャプチャ作業で本 PR 自身の UI 不具合 5 件を発見・修正**（すべて導入コミットに amend。新規コミットは追加せず、25 コミットのまま）。① `.lr-remote-note`（C2）② `.lr-delegated-badge`（C3）③ `.lr-paused-banner`（C4）の**3 クラスに CSS ルールが 1 行も無かった** — Jenkins のシンボルは `width="512px"` を持つものがあり、サイズ指定の無い親では**アイコンが本文幅いっぱいに描画**される。④ `${%key}` は `MessageFormat` を通るため単独の `'` が引用開始として消費され「this controller**s** own」と表示（`''` に修正）⑤ Jelly がテキストノード先頭の空白を落とし `jenkins-a(35s)` と詰まる（`&#160;` に修正）。**3 層のテストが全て見逃した理由**: DOM には 3 ブロックとも存在し、E2E も内容を検査していた。壊れていたのは見た目だけで、diff・ユニット・E2E のいずれからも到達できない。**キャプチャ基盤 `dev/jenkins-env/capture/`** を新設（docker 内 puppeteer。ハーネスは匿名読み取りを禁止しておりログインが必須、かつタブは `data-lr-tab` の DOM 操作で切り替わるため `chrome --screenshot` では到達不能）。**BEFORE は upstream `148d8eb` を git worktree に切って撮影**し作業ツリーは不変。対比の要点は「#1055 でリモートロックは動いていたが UI 上は完全に不可視だった」こと — 同一状態（`hw-rig-01` を保持中＋1 件待機）で upstream のページは **Locked 0 / Free 2 / 100% Free / Queue items 0** と表示する。最終 sha `111a767` で 4 テスト全緑: verify 462/0/1skip、E2E 32/32、load stress 190/10、timeout-race 92/108（いずれも overlap 0・HUNG 0） |
| 2026-08-14 | **Phase D 完了**（`30a0ed4` D1 / `ded92ed` D2）。これで **Phase 1 M2+M3 の全 25 コミットが揃った**。ドキュメントを実装と突き合わせる過程で、**記述と実装の乖離を 6 件**発見・修正: ①**STALE は自動解放されない**（管理者の明示的解放待ち。理由＝沈黙したクライアントがまだハードを触っている可能性があり、その推測で次の待ち行列に渡すのはロックが防ぐべき当のもの）。D1 の初稿で「60 秒で解放」と書いたのを実装確認で捕捉 ②UI ラベルが想定と相違（**Expose label(s) は複数・空白区切り**、`Forced server ID`、`Accept new acquire requests`）③`heartbeatIntervalSeconds` は**検証後に無視**され、閾値はサーバ側の既定 ④状態表の `EXPIRED` は**サーバが返さない**／`STALE` が欠落 ⑤エラー表が B2 以前（`MISSING_TARGET`）のまま。A7 の `INVALID_FIELD_VALUE`・503 `ACQUIRES_PAUSED`・413 も欠落 ⑥`inversePrecedence` の「remote では適用されない」記述が B1 で陳腐化。加えて **README 既存の `env.var.split(',')` 例が F3 の踏み抜き**そのものだったため、複数リソースでは `V0..Vn` を使う注記を隣に追加（ローカル・remote 共通の挙動なので remote 固有とはしていない） |
| 2026-08-13 | **upstream `148d8eb` へ rebase 後、最終コードで 4 テスト全緑**（plugin `0a96c53`）。verify **462/0/0/1skip・全ゲート ok**（`20260813201913-mvn-verify.md`。457→462 は upstream 由来の増分）、E2E **32/32**（`20260813204301-e2e-test.md`）、load `stress` **192/8・全失敗がクリーンな `LOCK_WAIT_TIMEOUT`・overlap 0・HUNG 0**（`20260813210938-load-test-stress.md`）、load `timeout-race` **95/105・105 件すべてクリーンな `LOCK_WAIT_TIMEOUT`・overlap 0・HUNG 0**（`20260813212257-load-test-timeout-race.md`）。A6 の効きが数値で見える: `timeout-race` の待ち時間 p95 = 60,203ms / max = 60,452ms で、締切 60 秒に対し **200〜450ms 遅れ**の発火（修正前は 59 秒遅れ）。**plugin のコード実装はここで完了**、残るは Phase D のドキュメント 2 コミットのみ。**2026-08-12 stress の重なり 10 件は未解明のまま**（以降 6 回再現なし）。切り分けで「解析の欠陥」「報告側のバグ」「ハーネスの前提」「付与経路の非同期」の 4 仮説を排除した経緯は `LOAD_TEST_SPECIFICATION.md` の CP01/CP02 節に記録。生データは慣例どおり破棄し、再発時にその時点の物証で調査する |
| 2026-08-12 | **Phase A' 完了**（`b2dd553` T1 / `eaf17c9` T2 / `2b92ec9` T3 / `b5d14bb` T4 / `41fc23c` T5 / `29c05d3` T6）。**verify だけが PR に載る層**という理由で、E2E/load より先にユニットを厚くした。jacoco 実測で remote 関連 **行 78.7%→88.4% / 分岐 63.3%→72.5%**、テスト 435→457。最大の穴だった `RemoteLockSession` は分岐 32.4%→63.2%。**`onResume` は 3 層すべてで未到達**だった（E2E/load が停止するのは常にサーバ側で、クライアント再起動のテストが存在しなかった）が、**新規テストが暴いたプラグインのバグはゼロ**で Phase A への押し込みは不要だった。`getResourceName` は #1055 以来呼び出し元が無い死んだコードと判明し、テストではなく削除（T6）。作業中のミス 2 件: `-Dtest='A+B+C'` は surefire の区切りでなくテスト 0 本で BUILD SUCCESS になる偽の緑を検出（カンマに修正）、死んだメソッド削除で `@CheckForNull` が重複しコンパイル不能なコミットを一度作成（amend 済み） |
| 2026-08-11 | **Phase A の A6・A7 完了**（`f82bbf9` A6 / `f624d15` A7）。いずれも #1055 由来で remote 経路にしか存在しない欠陥。A6 = キューに入った remote 要求の allocate timeout に起床が予約されず、期限ではなく保持者の解放時にしか発火しない。A7 = acquire エンドポイントが解釈できない値を既定値に落とし、`quantity` 非数値→全件・`timeoutUnit` 不正→無期限待ちに化ける。**発見は E2E 拡充の副産物**（境界シリーズ B01 と S18 の強化。経緯と証拠は `BOUNDARY_COVERAGE_ANALYSIS.md` §4）。ユニットテストは 2 件とも**本番コードが決してやらないことをテストが代行していた**ため既存テストでは露見しなかった（A6: `checkTimeouts()` の手動呼び出し、A7: そもそも型が JSON 由来という前提の欠落）。**A6・A7 を Phase A の位置へ並べ替え**（B/C 完了後に着手したため cherry-pick で積み直し。A7 は B2 以前のコードに対して書き直し、B2 が `MISSING_TARGET` を廃止する分のテスト期待値更新を B2 に含めた）。並べ替え後のツリーが並べ替え前と**バイト単位で同一**であることを `git diff` で確認済み |
| 2026-08-08 (3) | issue #1025 本文の更新を取りやめ。並行作業と完了条件を「PR 本文に乖離セクションを書く／提出後に #1025 へ導線コメント」に差し替え |
| 2026-08-10 (3) | **Phase C 検証完了。** run-mvn-verify **BUILD SUCCESS 432/0/1skip・全ゲート ok**（`20260810192956-mvn-verify.md`、plugin `aa0c391`）、run-e2e **21/21 PASS**（`20260810200900-e2e-test.md`）、run-load stress **183 SUCCESS / 17 クリーン LOCK_WAIT_TIMEOUT・overlap 0・HUNG 0**（`20260810202423-load-test.md`）。実装で 1 件修正: `RemoteCatalogCache.requestRefresh` の `@SuppressFBWarnings` が不要と SpotBugs に指摘され除去（C3 に畳んだ）。**ハーネス側のバグ 2 件も修正**（いずれも `COMMON_ROOT_DIR` が `dev/jenkins-env` である前提の取り違え）: 未コミット検査の除外パススペックが効かず E2E が自分のレポートで起動拒否／`.deployed-plugin` の参照が 1 階層ずれてレポートの plugin が `unknown` に。**E2E は既存 21 本のみで、S19〜S22 は未着手** |
| 2026-08-10 (2) | **B5・C1〜C4 実装完了。** plugin コミット 5 本（`6bbe86c` B5 / `34c959f` C1 / `b759ab7` C2 / `e68b50d` C3 / `4ddc7d3` C4）。B5 は当初 C2 の後にコミットしたが、**計画順に合わせて B4 の直後へ並べ替え**（Remote タブへの「無効」表示だけは C2 に吸収。ツリー差分ゼロを確認）。B5・C1・C2 は各コミット単体でテストが緑であることを `target/` を消して確認済み |
| 2026-08-10 | **B5（接続ごとの `enabled`）を計画に追加**（設計書 §4.0）。C1・C2 実装済みだが、C3 の前に B5 を入れる。対外的には事前合意を取らず PR 本文で説明する |
| 2026-08-08 (4) | **Phase B（B1〜B4）完了。** plugin コミット 4 本（`bb42b06` / `49c4686` / `4080658` / `ed2f5a9`）。run-mvn-verify **BUILD SUCCESS 412/0/1skip・全ゲート ok**（`20260808135020-mvn-verify.md`）、run-e2e **21/21 PASS**（`20260808140951-e2e-test.md`）、run-load stress **176 SUCCESS / 24 クリーン LOCK_WAIT_TIMEOUT・overlap 0・HUNG 0**（`20260808142517-load-test.md`）。B1〜B4 に実装時の発見を追記。**A5 のテストが Phase B の verify で flaky 発覚**（リモートのキューエントリを解放しないままだったため、ローカル待機ビルドが終了せず teardown が `DirectoryNotEmptyException`）。1 機能 1 コミット原則に従い **A5 に畳んで B1〜B4 を積み直し**（A5 = `2f7d384`） |
| 2026-08-08 (3) | **Phase A（A1〜A5）完了。** plugin コミット 5 本（`575f4fe` / `02fa4ba` / `507f4cb` / `c3347ec` / `43f177d`）。run-mvn-verify **BUILD SUCCESS 401/0/1skip・全ゲート ok**（`20260808102007-mvn-verify.md`。master の 394 から +7）、run-e2e **21/21 PASS**（`20260808104113-e2e-test.md`、作業ツリーを `start.sh --clean --in-place-build` でデプロイして実行）。A3・A5 に実装時の発見を追記。**計画外の追加作業 2 件**: (a) A2 の二重 release ガード（レコード保持により、2 回目の release が別クライアントのロックを解放しうる経路が生まれるため）、(b) `getRemoteLockRecord()` の Jenkins 非依存化（既存の `LockableResourceTest` が Jenkins 無しで `getLockCauseDetail()` を呼ぶため、A1 が `Jenkins.get()` を踏んで落ちた。フル verify で検出） |
| 2026-08-08 (2) | B4 の機能仕様を確定（`GET /resources` が状態と `acceptNewAcquires` を返す）。C2 / C3 / S19 / S22 と負荷の完了条件を追従 |
| 2026-08-08 | 初版。`design_01.md` の確定内容を 15 コミット（A5 + B4 + C4 + D2）に分解 |
