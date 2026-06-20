# M1H 結果（Remote lock - Phase 1 / M1H：PR #1055 CI 指摘対応）

> 設計: `LRR_DESIGN_P1_M1H.md` / 手順: `LRR_IMPLEMENTATION_STEPS_P1_M1H.md` / 起点レビュー: `LRR_REVIEW_P1_M1H.md`
> ブランチ: `feature/1025-remote-lr-p1-m1`（M1H コミット `7c3b325`、`upstream/master` = `8f03dbf` へ rebase 後）

## 概要

PR #1055 提出後に本家 CI が提起した **security 警告 4 件**（`github-advanced-security[bot]`）と **master ドリフト**への
是正サイクル。#49/#50/#51 は Stapler web メソッドの CSRF/権限ハードニング（挙動意味論不変）、#52 は **B2**＝
`GET /acquire/{lockId}` を純 read 化（poll-keepalive 撤去、QUEUED 期限をサーバ側キュー timeout に一本化）という
**意図的な挙動変更 1 点**。ユーザーが懸念した「master コンフリクト」は実在せず、rebase での取り込みのみで解消。

## 実施内容

### security 是正

| # | 対象 | 是正 |
|---|---|---|
| 49/51 | `RemoteConnection.DescriptorImpl#doCheckUrl` | `@POST`＋`Jenkins.get().checkPermission(Jenkins.ADMINISTER)` 付与、`RemoteConnection/config.jelly` の `url` に `checkMethod="post"` |
| 50 | `LockableResourcesManager#doCheckForcedServerId` | `@POST` 付与（ADMINISTER は既設）、`LRM/config.jelly` の `forcedServerId` に `checkMethod="post"` |
| 52 | `RemoteApiV1Action.AcquireStatusResource#doIndex` | **B2**: `touchPoll` 除去で GET 純 read 化 |

### #52 = B2 の撤去対象

- `RemoteApiV1Action.doIndex`: `touchPoll(lockId)` 呼び出しを除去（`REMOTE` 権限・API 有効判定は残置）。
- `RemoteLockManager`: `touchPoll(String)` / `getQueuePollExpiryMs()` / `DEFAULT_QUEUE_POLL_EXPIRY_MS` /
  `maybeScanStale` の QUEUED 分岐（`QUEUE_EXPIRED`）を撤去。ACQUIRED STALE 判定・terminal TTL は残置。
- `RemoteLockRecord`: `lastPolledAt` / `polled()` / `getLastPolledAt()` を撤去。
- QUEUED 期限は `RemoteQueueEntry.timeoutDeadlineMillis`（= `timeoutForAllocateResource`）に一本化。

**受容トレードオフ**: `timeoutForAllocateResource == 0`（無限待ち）＋クライアント死亡時の QUEUED 枠の ~60 秒早期回収を喪失
（QUEUED はリソース非保持、昇格後は ACQUIRED heartbeat-STALE が回収＝安全。ローカル `lock()` timeout 無しと整合）。

## 差分（plugin、コミット `7c3b325`）

| ファイル | 変更 |
|---|---|
| `RemoteConnection.java` | `doCheckUrl` に @POST＋ADMINISTER（import 2 追加） |
| `RemoteConnection/config.jelly` | `url` に `checkMethod="post"` |
| `LockableResourcesManager.java` | `doCheckForcedServerId` に @POST（import 追加） |
| `LockableResourcesManager/config.jelly` | `forcedServerId` に `checkMethod="post"` |
| `actions/RemoteApiV1Action.java` | `doIndex` の `touchPoll` 除去（GET 純 read） |
| `remote/RemoteLockManager.java` | poll-keepalive 一式・QUEUED 期限分岐 撤去（-49 行相当） |
| `remote/RemoteLockRecord.java` | `lastPolledAt`/`polled()`/`getLastPolledAt()` 撤去 |
| `RemoteConnectionTest.java` | `doCheckUrl` テストを @WithJenkins 化、`testDoCheckUrlRequiresAdmin` 追加 |
| `remote/RemoteLockManagerTest.java` | poll-keepalive 2 本を `queuedRecordExpiresViaQueueTimeout` / `queuedRecordWithoutTimeoutSurvivesWithoutPolling` に置換 |

合計 9 ファイル / +87・-109（純減＝撤去主体）。

## master 同期（rebase）

- `feature/1025-remote-lr-p1-m1` を `upstream/master`（`8f03dbf`：#1056 crowdin bump / #1057 BOM bump `6549...`→`6585...`）へ rebase。
- **コンフリクト無し**（4/4 自動 replay）。`pom.xml` は BOM bump（master・行 73-74）と credentials 依存追加（PR・行 88）が別ハンクで両立。
- rebase 後 4 コミット: `913e3a5`(phase1) / `f8feeae`(spotless) / `ac49db9`(spotbugs) / `7c3b325`(M1H security)。

## 検証

開発サイクル（`作業手順一覧.md`）に従い、`run-mvn-verify.sh`（mvn verify）＋ `run-e2e.sh` を動確の正本とする。

- **mvn verify（rebase 前・in-place）: BUILD SUCCESS / 383 件・0 失敗・1 skip**、spotless/spotbugs(effort=Max,
  threshold=Low)/checkstyle/pmd/cpd 全 ok（`dev/reports/20260620220250-mvn-verify.md`）。新規テスト（doCheckUrl 権限・
  queue-timeout 失効・GET 純 read 生存）も緑。
- **E2E: 20/20 PASS / fail 0**（`dev/reports/20260620222354-e2e-test.md`、作業ツリーを `start.sh --in-place-build` でビルド）。
  B2 が依存する **S13 stale-admin-release**（ACQUIRED heartbeat-STALE 回収）も緑＝撤去した QUEUED poll-GC の代替経路が実環境で機能。
- **mvn verify（rebase 後・新 BOM #1057・コミット済み HEAD `7c3b325`・作業ツリー clean）: BUILD SUCCESS / 383 件・0 失敗・
  0 エラー・1 skip**、全ゲート ok（`dev/reports/20260621082011-mvn-verify.md`）。＝新 BOM 取り込み後も回帰なしを確認（動確の正本）。

> `mvn test` では漏れる CI ゲート（spotless/spotbugs 等）をローカルで通過（[[jenkinsci-ci-mvn-verify]]）。

## コミット

- plugin: `feature/1025-remote-lr-p1-m1` = `7c3b325`（M1H 単一コミット、`upstream/master 8f03dbf` の上）。**push なし**（提出時に force push）。
- notes: 本ステップで commit（REVIEW/DESIGN/STEPS/RESULT j+e、README 索引/Status、レポート）。Co-Authored-By なし。

## 残課題・次

- B1（QUEUED 段階での heartbeat 化による速い GC 維持）は不採用のまま。無限待ち＋死亡クライアントの早期回収が将来必要になれば再検討。
- メンテナレビュー（PR #1055、mergeState BLOCKED=REVIEW_REQUIRED）と force push は別ステップ。クライアント UI は Phase 2（issue #1025）。
