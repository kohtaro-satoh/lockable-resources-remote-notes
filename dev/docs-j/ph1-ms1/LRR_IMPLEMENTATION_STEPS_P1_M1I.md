# M1I 実装手順（Remote lock - Phase 1 / M1I：queued-expiry-poll-404 デグレ対策）

> 設計: `LRR_DESIGN_P1_M1I.md` / 起点: `LRR_ISSUE_P1_M1H_queued_expiry_poll_404.md`
> ブランチ: `feature/1025-remote-lr-p1-m1`（M1I 開始時 HEAD `65d8415` = PR #1055 head）

### Step 1: サーバ — terminal 遷移時刻の記録

- [x] `RemoteLockRecord.java`: `terminalAt`（volatile long）フィールド＋`getTerminalAt()` を追加
- [x] `markFailed` / `markSkipped` で `this.terminalAt = System.currentTimeMillis()` を set

### Step 2: サーバ — terminal TTL の起点を修正

- [x] `RemoteLockManager.maybeScanStale`: SKIPPED/FAILED の削除判定を `now - getEnqueuedAt()` → **`now - getTerminalAt()`** に変更
- [x] 意図をコメントで明記（timeout > TTL でも FAILED を TTL ぶん保持＝poll で観測可能）

### Step 3: クライアント — poll 404 の正規化

- [x] `RemoteLockSession.pollStatus`: `RemoteApiException` の 404/410 を、**`!bodyStarted` なら `LOCK_WAIT_TIMEOUT`** として `finishFailure`
- [x] ボディ開始後（取得済み lease の消失）は従来どおり「server may have restarted」を維持
- [x] メッセージを系統 A（FAILED 状態受領）と揃え `errorCode=LOCK_WAIT_TIMEOUT` を出力

### Step 4: テスト

- [x] 単体: `RemoteLockManagerTest.timedOutRecordRecordsTerminalTimestampAndSurvivesMaintenance`
  （timeout→FAILED で `terminalAt` が enqueue 後に set、`doRun()` で即削除されない）
- [x] E2E: `scenarios/remote-acquire-timeout.sh`（S18）新規。`run-e2e.sh` に登録（`M1I_SCENARIOS` / `m1i-series` / `all` / IDS / usage）
- [x] `E2E_TEST_SPECIFICATION.md` に S18（P1M1I）を追記

### Step 5: ビルド・検証・commit

- [x] `dev/run-mvn-verify.sh`（in-place、`mvn clean verify`）成功 → `dev/reports/20260622120114-mvn-verify.md`（384/0/1skip・全ゲート ok）
  ※ spotless 違反は `spotless:apply` で整形後に再 verify
- [x] コンテナへ反映: `start.sh --clean --in-place-build`（jhX volume の旧 .jpi が ref seed を上書きする罠を回避）
- [x] S18 単体: fix 前 FAIL（404/通信失敗）/ fix 後 PASS（`LOCK_WAIT_TIMEOUT`）を確認
- [x] `dev/jenkins-env/run-e2e.sh` 全件 PASS → `dev/reports/20260622123929-e2e-test.md`（21/21）
- [x] plugin commit `e231367`（`65d8415` の上に積み上げ・amend なし・Co-Authored-By なし）
- [x] notes commit（load スイート＋issue＋S18 / reports 最新3種）。**push しない**
- [ ] 本サイクル文書（DESIGN/STEPS/RESULT j+e、README 索引）を notes commit

## 変更ファイル一覧（plugin）

| ファイル | 変更 | 状態 |
|---|---|---|
| `remote/RemoteLockRecord.java` | `terminalAt`＋getter、markFailed/markSkipped で set | 実装済 |
| `remote/RemoteLockManager.java` | terminal TTL を terminalAt 起点に | 実装済 |
| `remote/RemoteLockSession.java` | poll 404/410 を LOCK_WAIT_TIMEOUT 正規化 | 実装済 |
| `remote/RemoteLockManagerTest.java` | terminalAt 機構テスト追加 | 実装済 |
