# M1I 設計（Remote lock - Phase 1 / M1I：queued-expiry-poll-404 デグレ対策）

> 起点: `LRR_ISSUE_P1_M1H_queued_expiry_poll_404.md`（高負荷テストで発見した M1H(#52) 由来の回帰）
> ブランチ: `feature/1025-remote-lr-p1-m1`（M1I コミット `e231367`、PR #1055 head `65d8415` の上に積み上げ・amend なし）
> 位置づけ: **M1H 完了・PR #1055 提出後**に、新規構築した高負荷テスト（[[load-test-suite]]）で発見した
> 劣化時の挙動回帰を是正する独立サイクル。挙動変更を 1 点含む（timeout の表面化のみ。ロック正当性は不変）。

## 1. 目的

remote acquire が**リソース枯渇で allocate timeout したとき、`LOCK_WAIT_TIMEOUT` を明示して fail-closed** すること。
回帰前は `timeoutForAllocateResource > 120s` のとき正当な枯渇 timeout が **HTTP 404 →「communication failure /
server may have restarted」**として誤表面化していた（fail-closed は保たれるため正当性バグではないが、誤診断を招く）。

## 2. 真因（起点 issue §5 の要約）

- `RemoteLockManager.maybeScanStale` が terminal record（SKIPPED/FAILED）の保持 TTL（`TERMINAL_TTL_MS=120s`）を
  **`enqueuedAt` 起点**で測っていた。
- timeout 起因の FAILED は `t=timeoutForAllocateResource`（enqueue から）で生成されるため、`timeoutForAllocateResource > 120s`
  だと**生成直後に TTL 超過扱い → 次の掃引で即削除**。以降の `GET /acquire/{lockId}` poll が **404 LOCK_NOT_FOUND** →
  client が `RemoteLockSession` で 404 を「server may have restarted」として fail-closed。
- バグ行自体は最初の #1025 コミット（`4f3577f`）由来の**潜在バグ**。M1H の **#52（B2：poll-keepalive 撤去・QUEUED 期限を
  キュー timeout に一本化）**が、能動 polling 中の QUEUED→FAILED 経路を到達可能にしたことで**観測される劣化として顕在化**した。
- 負荷依存ではない。`timeoutForAllocateResource > TERMINAL_TTL(120s)` で決定的に発火（高負荷テストは stress が偶々 3 分 timeout を使ったため先に踏んだ）。

## 3. 設計（採用 = (A) 最小修正）

### サーバ（本丸）

- `RemoteLockRecord` に `terminalAt`（terminal 遷移時刻）を追加し、`markFailed` / `markSkipped` で `System.currentTimeMillis()` を set。
- `maybeScanStale` の terminal TTL 判定を `now - getEnqueuedAt()` → **`now - getTerminalAt()`** に変更。
- → timeout の長短に関わらず FAILED/SKIPPED 記録が**常に TTL ぶん観測可能**になり、polling client が clean な `LOCK_WAIT_TIMEOUT` を受け取る。404 自体が出なくなる。

### クライアント（安全網）

- `RemoteLockSession` の poll 例外処理で、`RemoteApiException` の **404/410 を、ボディ開始前（QUEUED 中）なら `LOCK_WAIT_TIMEOUT` に正規化**して fail-closed。
- 根拠: lockId を持つ＝admission は POST 時に通過済み。skipIfLocked は POST で同期解決（QUEUED を経ない）。よって**未取得の record が消える=枯渇 timeout 以外あり得ない**ため、404 を timeout と解釈してよい。サーバ側 TTL を過ぎた・パーティション等でも堅牢。

## 4. 代替案と却下理由

| 案 | 内容 | 評価 |
|---|---|---|
| **(A) 採用** | terminal TTL を terminalAt 起点に＋client が poll 404 を timeout 正規化 | 最小・後方互換・取りこぼし窓ゼロ。in-flight PR に最適 |
| (B) | `SKIPPED`/`FAILED` 状態を廃し即削除、404 を request 種別＋既知状態で推論 | end-state は綺麗（TTL 機構ごと消える）だが、404 セマンティクス/状態 enum 変更＝**クロスバージョン互換**（remote は client/server 別版あり得る）・errorCode 拡張性喪失。in-flight PR には重い。別 issue で扱う |

## 5. テスト方針

- 単体: `RemoteLockManagerTest.timedOutRecordRecordsTerminalTimestampAndSurvivesMaintenance`
  （timeout→FAILED で `terminalAt` が enqueue 後に set され、直後の `doRun()`=maybeScanStale で**即削除されない**）。
- E2E: 新規 **S18 `remote-acquire-timeout`**（`m1i-series`）。holder が R を保持中に waiter が
  `timeoutForAllocateResource > 120s`（130s）で remote acquire → 枯渇 timeout。**`errorCode == LOCK_WAIT_TIMEOUT` を厳密 assert**、
  `server may have restarted`/`communication failure`/`HTTP 404` の不在、body 未実行、待機 ≥120s を確認。
  **TTL 境界を突くため timeout > 120s が必須**（短いと FAILED 窓が残り素通り）。fix 前 FAIL / fix 後 PASS の回帰ガード。

## 6. 含まない（M1I スコープ外）

| 項目 | 備考 |
|---|---|
| (B) 状態廃止リデザイン | 別 issue。プロトコル/互換方針を別途設計 |
| クライアント UI / read-only ミラー | Phase 2（issue #1025） |

## 7. 検証

開発サイクル（`作業手順一覧.md`）に従い、`run-mvn-verify.sh`（mvn verify）＋ `run-e2e.sh` を動確の正本とする。

- `dev/run-mvn-verify.sh`（in-place、`mvn clean verify`）で全テスト＋静的ゲート（spotless/spotbugs/checkstyle/pmd/cpd）成功。
- `dev/jenkins-env/run-e2e.sh` 全件 PASS（S18 含む）。
- **デプロイ注意**（[[rlr-build-environment]]）: jhX ボリュームに前回の `.jpi` が残ると ref/plugins seed が上書きされず旧プラグインのまま。
  未コミットの作業ツリー fix を E2E に反映するには `start.sh --clean --in-place-build`。

## 変更ファイル一覧（plugin、コミット `e231367`）

| ファイル | 変更 |
|---|---|
| `remote/RemoteLockRecord.java` | `terminalAt` フィールド＋`getTerminalAt()` 追加、`markFailed`/`markSkipped` で set |
| `remote/RemoteLockManager.java` | `maybeScanStale` の terminal TTL を `getTerminalAt()` 起点に変更 |
| `remote/RemoteLockSession.java` | poll の 404/410 を、ボディ開始前なら `LOCK_WAIT_TIMEOUT` に正規化 |
| `remote/RemoteLockManagerTest.java` | `timedOutRecordRecordsTerminalTimestampAndSurvivesMaintenance` 追加 |

合計 4 ファイル / +73・-1。

## 更新履歴

- 2026-06-22: 初版作成。高負荷テストで発見した queued-expiry-poll-404 回帰（M1H #52 由来・潜在バグは 4f3577f）への
  (A) 最小修正を M1I 開発サイクルとして後付け定義。terminal TTL を terminalAt 起点に＋client 404 正規化、回帰ガード S18 追加。
