# M1I 結果（Remote lock - Phase 1 / M1I：queued-expiry-poll-404 デグレ対策）

> 設計: `LRR_DESIGN_P1_M1I.md` / 手順: `LRR_IMPLEMENTATION_STEPS_P1_M1I.md` / 起点: `LRR_ISSUE_P1_M1H_queued_expiry_poll_404.md`
> ブランチ: `feature/1025-remote-lr-p1-m1`（M1I コミット `e231367`、PR #1055 head `65d8415` の上）

## 概要

新規構築した高負荷テスト（[[load-test-suite]]、`run-load.sh` stress）で発見した回帰
（正当な remote acquire 枯渇 timeout が `timeoutForAllocateResource > 120s` のとき 404/「communication failure」として
誤表面化）への (A) 最小修正サイクル。terminal record の保持 TTL を terminal 遷移時刻起点に修正し、クライアントの
poll 404 を `LOCK_WAIT_TIMEOUT` に正規化。回帰ガードとして E2E S18 を追加。

## 実施内容

| 層 | 変更 |
|---|---|
| サーバ | `RemoteLockRecord` に `terminalAt`（markFailed/markSkipped で set）。`RemoteLockManager.maybeScanStale` の terminal TTL を `getTerminalAt()` 起点に |
| クライアント | `RemoteLockSession` の poll 404/410 を、ボディ開始前なら `LOCK_WAIT_TIMEOUT` に正規化（安全網） |
| テスト | 単体 `timedOutRecordRecordsTerminalTimestampAndSurvivesMaintenance`、E2E `S18 remote-acquire-timeout`（`m1i-series`） |

## 差分（plugin、コミット `e231367`）

| ファイル | 変更 |
|---|---|
| `remote/RemoteLockRecord.java` | `terminalAt`＋`getTerminalAt()`、markFailed/markSkipped で set |
| `remote/RemoteLockManager.java` | `maybeScanStale` の terminal TTL を terminalAt 起点に |
| `remote/RemoteLockSession.java` | poll 404/410 を LOCK_WAIT_TIMEOUT 正規化 |
| `remote/RemoteLockManagerTest.java` | terminalAt 機構テスト追加 |

合計 4 ファイル / +73・-1。

## 検証

開発サイクル（`作業手順一覧.md`）に従い、`run-mvn-verify.sh`（mvn verify）＋ `run-e2e.sh` を動確の正本とする。

- **mvn verify（in-place、コミット済み HEAD `e231367`）: BUILD SUCCESS / 384 件・0 失敗・0 エラー・1 skip**、
  spotless/spotbugs(effort=Max, threshold=Low)/checkstyle/pmd/cpd 全 ok（`dev/reports/20260622120114-mvn-verify.md`）。
  新規単体（terminalAt 機構）も緑。※初回は spotless 違反 → `spotless:apply` 後に再 verify で green。
- **E2E: 21/21 PASS / fail 0**（`dev/reports/20260622123929-e2e-test.md`）。新規 **S18 remote-acquire-timeout** ＋既存 20 件、回帰なし。
- **S18 が回帰ガードとして機能**: fix を含まない旧プラグイン（jhX volume の残存 .jpi）では **FAIL**（404/communication failure）、
  `start.sh --clean --in-place-build` で fix を反映後は **PASS**（`errorCode=LOCK_WAIT_TIMEOUT`、body 未実行、待機 153s）。
- **サーバ retention を Groovy probe で直接確認**: 短 timeout（1s）で QUEUED→FAILED 後、`terminalAt-enqueuedAt≈1520ms`、
  `doRun()`（maybeScanStale）で**即削除されず RETAINED**。

> `mvn test` では漏れる CI ゲート（spotless/spotbugs 等）をローカルで通過（[[jenkinsci-ci-mvn-verify]]）。

## コミット

- plugin: `feature/1025-remote-lr-p1-m1` head `e231367`「Report a remote acquire timeout as LOCK_WAIT_TIMEOUT, not a 404 failure」
  （`65d8415` の上に**積み上げ・amend なし**＝PR #1055 の提出済み hash を変えない）。**push なし**（合図時に実施）。
- notes: load スイート＋issue＋S18（`b6e0583`）、reports 最新3種（`dfcb8d8`）、本サイクル文書（DESIGN/STEPS/RESULT j+e、README）。Co-Authored-By なし。

## 残課題・次

- **(B) 状態（SKIPPED/FAILED）廃止リデザイン**は別 issue（クロスバージョン互換・拡張性の設計が必要）。本サイクルは (A) で閉じる。
- メンテナレビュー（PR #1055）と force push は別ステップ。クライアント UI は Phase 2（issue #1025）。
