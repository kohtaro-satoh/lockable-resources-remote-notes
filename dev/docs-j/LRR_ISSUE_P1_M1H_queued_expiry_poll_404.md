# LRR-ISSUE (P1M1H): QUEUED 期限切れの acquire ポーリングが 404 になり、正当な枯渇 timeout が「通信失敗」として表面化する

| 項目 | 内容 |
|---|---|
| ID | LRR-ISSUE-P1M1H-queued-expiry-poll-404 |
| 重大度 | **正当性=低**（破綻なし・fail-closed 保持）／ **診断性・運用性=中**（誤診断を招く） |
| 種別 | **ロジックバグ**：terminal record TTL の計測起点誤り（`enqueuedAt` 起点）。当初「client/server timeout 競合（race）」と誤認したが、コード精査で確定真因に訂正（2026-06-22） |
| ステータス | Open（内部 issue 化。修正未着手。真因・修正箇所は特定済み） |
| 発火条件 | **`timeoutForAllocateResource > TERMINAL_TTL_MS（=120s）`** のとき決定的に発生（負荷非依存） |
| マイルストーン | P1M1H 派生（B2 = #52「QUEUED 期限をキュー timeout 一本化」の副作用） |
| 発見手段 | 高負荷テスト G01 `grid-storm` の `stress` プリセット（hold 60s・200 並列、timeout=3 分）。ただし**真因は負荷非依存**で、timeout>120s の E2E 1 本で再現可能（§検出可能性） |
| 発見日 | 2026-06-22 |

---

## 1. 概要

remote acquire が枯渇 timeout で失敗するとき、本来は `LOCK_WAIT_TIMEOUT` を明示して fail-closed すべきだが、
**`timeoutForAllocateResource > 120s` のとき、サーバが FAILED 記録を保持できず即削除してしまい**、
クライアントの状態ポーリングが 404 を受けて「server may have restarted / communication failure」として fail-closed する。
いずれも fail-closed（body 未実行・整合性保持）で**破綻ではない**が、正当な timeout が通信失敗として誤表示される。

- **系統 A（クリーン・本来あるべき姿）**: クライアントの poll が FAILED 記録の存在中に当たり、
  `state=FAILED, errorCode=LOCK_WAIT_TIMEOUT` を受領 →「lock 待ち timeout」と明示。
- **系統 B（バグ発現）**: FAILED 記録が即削除され、クライアントの `GET /acquire/{lockId}` が
  **HTTP 404 LOCK_NOT_FOUND** → `RemoteApiException`（「server may have restarted」）で fail-closed。
  **正当な枯渇 timeout が「通信失敗」と誤表示**される。

実測（stress, timeout=3 分>120s）9 失敗中 **6 件が B / 3 件が A**。B が多数なのは下記 §5 の TTL バグで FAILED 窓が
ほぼ潰れるため。残る 3 件 A は「markFailed 〜 次の掃引で remove までの掃引間隔ぶんの隙間」を poll が拾った差。
**この A/B の揺れだけが timing 依存で、主因は決定的な TTL バグ**（race ではない）。

---

## 2. 影響

- **正当性は保たれる**（重要）: 相互排他違反 0・デッドロック/HUNG 0・失敗ジョブの body 実行 0。
  fail-closed 設計どおりで、二重取得や phantom lock は発生しない。**「高負荷で remote LR が破綻しない」要件は満たす。**
- **診断性・運用性の粗**: 系統 B では、本来「キュー枯渇で待ち timeout した」だけなのに、ログ・例外が
  `Remote API communication failure: GET /acquire/{id}` と出る。運用者は**ネットワーク/インフラ障害と誤診断**しやすい。
- **signal の不整合**: 同じ「枯渇 timeout」が A（LOCK_WAIT_TIMEOUT）と B（404→通信失敗）で**別物に見える**。
  リトライ方針・アラート分類・SLO 集計などを誤らせる。

---

## 3. 再現環境・条件

- ハーネス: `dev/jenkins-env/run-load.sh --preset stress`（= 200 並列 / ITER3 / **hold 60s** / lock timeout 3 分 / job timeout 15 分 / loopback OFF=純クロス）。
- 構成: 4 コントローラー（a/b/c/d）が server/client 兼用、各 50 リソース（40 exposed）、`pool` ラベルで quantity 選択。
- 前提: lock ステップに `timeoutForAllocateResource: 3, timeoutUnit: 'MINUTES'` を正しく指定（※ `timeout:`/`unit:` は無効パラメータで黙殺される点に注意。本 issue の観測は正しい param 指定後）。
- 枯渇条件: 1 サーバあたり exposed 40・remote qty2 ⇒ 供給 40 に対し需要が約 2.5×、かつ hold 60s で
  待ち時間が lock timeout 180s に到達 ⇒ 一部 acquire が timeout する。

該当 run（エビデンス出所）:

```
run id   : 20260622083826  (preset=stress)
reports  : dev/reports/20260622083826-load-test/grid-storm/   ※将来削除され得るため下記に証跡を内包
```

---

## 4. エビデンス（証跡内包）

### 4.1 結果サマリ（metrics.json 抜粋）

```
builds=200  results={SUCCESS: 191, FAILURE: 9}
overlap_violations=0   hung=0           ← 整合性は完全保持
失敗 9 件すべて fail-closed（body 実行マーカー 0 件）
queue_wait_ms: p50=3901.5  p95=167373.7  p99=179262.3  max=182276   ← 約 180s(=3分)で打ち切り
```

### 4.2 失敗 9 件の分類（コンソール errorCode で判定）

| build | 系統 | 表面化 |
|---|---|---|
| d#251 | **A** | `errorCode=LOCK_WAIT_TIMEOUT`（クリーン） |
| c#248 | **A** | `errorCode=LOCK_WAIT_TIMEOUT` |
| c#244 | **A** | `errorCode=LOCK_WAIT_TIMEOUT` |
| c#214 | **B** | `GET /acquire/{id}` → HTTP 404 → RemoteApiException（通信失敗） |
| b#217 | **B** | 同上 |
| c#245 | **B** | 同上 |
| b#229 | **B** | 同上 |
| c#246 | **B** | 同上 |
| c#236 | **B** | 同上 |

→ **A=3 件 / B=6 件**。高負荷では B（404→通信失敗）が多数。

### 4.3 系統 A の証跡（クリーン: d#251、逐語抜粋）

```
Trying to acquire remote lock on [Label: pool, Quantity: 2] (serverId=a)
Remote acquire enqueued (serverId=a, lockId=ecdbace2-b375-4ca1-9ed6-5993dfa96162)
ERROR: Remote acquire failed (serverId=a, lockId=ecdbace2-b375-4ca1-9ed6-5993dfa96162, state=FAILED, errorCode=LOCK_WAIT_TIMEOUT, message=null)
Finished: FAILURE
```

### 4.4 系統 B の証跡（粗い: c#214、逐語抜粋）

```
Trying to acquire remote lock on [Label: pool, Quantity: 2] (serverId=a)
Remote acquire enqueued (serverId=a, lockId=0a2c23c9-6e43-44c2-bc4f-48cb94bbb2c4)
... (QUEUED ポーリング中にサーバ側 record が期限切れで消滅) ...
org.jenkins.plugins.lockableresources.remote.RemoteApiException: Remote API request failed: GET /acquire/0a2c23c9-6e43-44c2-bc4f-48cb94bbb2c4/ returned HTTP 404
Also:   org.jenkinsci.plugins.workflow.actions.ErrorAction$ErrorId: d6c859c4-b052-4c40-bda8-7ecb4567739d
Caused: org.jenkins.plugins.lockableresources.remote.RemoteApiException: Remote API communication failure: GET /acquire/0a2c23c9-6e43-44c2-bc4f-48cb94bbb2c4/
Finished: FAILURE
```

> 観測ポイント: enqueue は成功（QUEUED）、その後の状態ポーリングが 404 になり、
> 「正当な枯渇 timeout」が **`Remote API request failed ... HTTP 404` ＋ `communication failure`** として表面化している。

---

## 5. 根本原因（確定）

**terminal record の保持 TTL を「terminal になった時刻」ではなく「enqueue 時刻」起点で測っているため、
timeout 起因の FAILED 記録が生成直後に期限超過扱いとなり即削除される。**

- **タイムスタンプ** — `RemoteLockRecord`（[RemoteLockRecord.java](../../../lockable-resources-plugin/src/main/java/org/jenkins/plugins/lockableresources/remote/RemoteLockRecord.java)）:
  `enqueuedAt` を生成時に 1 回 set するのみ。`markFailed()` は**終端遷移の時刻を記録しない**（terminalAt 相当が無い）。

- **掃引** — `RemoteLockManager.maybeScanStale`（[RemoteLockManager.java:228-230](../../../lockable-resources-plugin/src/main/java/org/jenkins/plugins/lockableresources/remote/RemoteLockManager.java)）。
  `TERMINAL_TTL_MS = 120s`:
  ```java
  } else if (state == SKIPPED || state == FAILED) {
      if (now - record.getEnqueuedAt() > TERMINAL_TTL_MS) {   // ← enqueue 起点（バグ）
          records.remove(record.getLockId());
      }
  }
  ```

- **時系列**（`timeoutForAllocateResource = 180s`）:
  1. enqueue（t=0）→ QUEUED
  2. キュー timeout（t=180s）→ `RemoteQueueEntry.onTimeout`→`markFailed("LOCK_WAIT_TIMEOUT")`。FAILED 化（削除しない）
  3. 次の `maybeScanStale`：`now - enqueuedAt = 180s > 120s` が**生成直後から真** → **即 `records.remove`**
  4. 以降の `GET /acquire/{lockId}` は record 不在 → **404 LOCK_NOT_FOUND**

  → 本来 120s あるはずの「FAILED を返す猶予窓」が、`timeoutForAllocateResource(180s) > TERMINAL_TTL(120s)` のとき
  **生成時点でゼロ**になる。だから系統 B（404）が支配的。`timeoutForAllocateResource ≤ 120s` なら窓が
  `120 − timeout` 秒残るので系統 A（clean）になり**発現しない**。

- **404 → 通信失敗の表面化**: record 不在で `AcquireStatusResource` は 404 LOCK_NOT_FOUND を返し
  （[RemoteApiV1Action.java](../../../lockable-resources-plugin/src/main/java/org/jenkins/plugins/lockableresources/actions/RemoteApiV1Action.java)）、
  client は poll の 404/410 を「server may have restarted」として即 fail-closed する
  （[RemoteLockSession.java:234-248](../../../lockable-resources-plugin/src/main/java/org/jenkins/plugins/lockableresources/remote/RemoteLockSession.java)）。
  ＝ 正当な枯渇 timeout が「通信失敗 / サーバ再起動」と誤表示される。

> 当初この issue を「client allocate-timeout と server queue timeout の race」と記述したが**誤り**。
> client 側に独自 allocate-timeout は無く（QUEUED の間 3s 間隔で無限 poll、[RemoteLockSession.java:186](../../../lockable-resources-plugin/src/main/java/org/jenkins/plugins/lockableresources/remote/RemoteLockSession.java)）、
> 真因は上記 TTL 起点バグ。残る A/B の揺れは「markFailed〜次回掃引まで」の隙間のみ。

---

## 6. 修正案（候補）

**主因が特定済みなので、第一選択は TTL 起点の修正。**

1. **terminal 遷移時刻起点で TTL を測る**（**推奨・本丸**）:
   `RemoteLockRecord` に `terminalAt`（または `failedAt`/`skippedAt`）を追加し、`markFailed`/`markSkipped` で set。
   `maybeScanStale` を `now - record.getTerminalAt() > TERMINAL_TTL_MS` に変更（フォールバックで `max(enqueuedAt, terminalAt)`）。
   → timeout の長短に関わらず FAILED 記録が常に 120s 生存し、polling client が必ず clean な `LOCK_WAIT_TIMEOUT`（系統 A）を受け取る。404 自体が出なくなる。

2. （補強）**client が poll の 404 LOCK_NOT_FOUND を timeout として正規化**:
   `RemoteAcquireStatus(state=FAILED, errorCode=LOCK_WAIT_TIMEOUT)` に倒す。ただし本物のサーバ再起動と
   区別できないため、1 の補助にとどめる。

3. （任意）**404 の errorCode 細分化**: 「timeout 由来の不在」と「未知 lockId」を別コードで返す。

> ※ 4.4 の `Caused:` 内部ラップ順序は修正時に確定。observable は「枯渇 timeout が 404/通信失敗で出る」点で変わらない。

---

## 8. 検出可能性（E2E で捕捉可能・負荷非依存）

本 issue は **負荷依存ではなく `timeoutForAllocateResource > TERMINAL_TTL_MS(120s)` で決定的に発火**するため、
E2E スケール（holder 1・waiter 1）で再現・回帰ガードできる。

- **再現する E2E**: holder が resource を保持 → waiter が `timeoutForAllocateResource > 120s`（例 130s）で remote acquire →
  待たされて timeout → **`errorCode == LOCK_WAIT_TIMEOUT` を厳密 assert**。本バグがあると 404/「server may have restarted」になり assert 失敗で検出。
- **見逃す書き方（注意）**: timeout を**短く（<120s）**設定すると FAILED 窓が残り clean な A になって PASS してしまう。
  回帰テストは**必ず timeout > TERMINAL_TTL** を使う（または TTL を一時的に下げる）。
- 既存 E2E が見逃した理由: そもそも timeout シナリオが無く、境界（TTL）を突いていなかった
  （`rlr-equivalence-test-defaults` と同型の取りこぼし）。
- 高負荷テストが先に見つけたのは、`stress` が偶々 timeout=3 分（>120s）を使ったため。負荷は必須条件ではない。

---

## 7. 非対象・補足

- これは**正当性（correctness）バグではない**。相互排他・fail-closed・終端性は保たれている
  （`stress` 実測: overlaps 0・HUNG 0・body 実行 0）。本 issue は**診断性・signal 一貫性**の改善。
- `timeout:`/`unit:` を lock ステップに渡しても無効（`Unknown parameter` 警告で黙殺＝0=無限待ち）。
  正しくは `timeoutForAllocateResource` / `timeoutUnit`。本 issue とは別の運用上の注意点。
- 関連仕様: 高負荷テスト全体は `dev/docs-j/LOAD_TEST_SPECIFICATION.md`（検証実績・finding 節）。

---

## 付録: 関連 run 一覧（同日）

| run id | preset | 規模 | 結果 | 備考 |
|---|---|---|---|---|
| 20260622072853 | full(loopback OFF) | 200 | 200/200 COMPLETED | lock timeout 未修正（無限待ち）・timeout 未発生 |
| 20260622082344 | stress(timeout 未修正) | 200 | 200/200 COMPLETED | 待ち max 238s でも無限待ちのため成功 |
| **20260622083826** | **stress(timeout 修正後)** | **200** | **191/9** | **本 issue の出所（A=3 / B=6）** |
