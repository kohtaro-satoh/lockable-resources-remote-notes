# M1H 実装手順（Remote lock - Phase 1 / M1H：PR #1055 CI 指摘対応）

> 設計: `LRR_DESIGN_P1_M1H.md` / 起点レビュー: `LRR_REVIEW_P1_M1H.md`
> ブランチ: `feature/1025-remote-lr-p1-m1`（M1H 開始時 HEAD `5136daa`）

### Step 1: security #49/#51（doCheckUrl）

- [x] `RemoteConnection.java`: `doCheckUrl` に `@org.kohsuke.stapler.verb.POST` を付与
- [x] 同メソッド先頭に `Jenkins.get().checkPermission(Jenkins.ADMINISTER)` を追加
- [x] `RemoteConnection/config.jelly`: `url` の `<f:textbox/>` を `<f:textbox checkMethod="post"/>` に
- [x] import 追加（`jenkins.model.Jenkins`、`org.kohsuke.stapler.verb.POST`）

### Step 2: security #50（doCheckForcedServerId）

- [x] `LockableResourcesManager.java`: `doCheckForcedServerId` に `@POST` を付与（ADMINISTER は既設）
- [x] `LRM/config.jelly`: `forcedServerId` の `<f:textbox .../>` に `checkMethod="post"` を追加
- [x] import 追加（`org.kohsuke.stapler.verb.POST`）

### Step 3: security #52 = B2（GET 純 read）

- [x] `RemoteApiV1Action.java`: `doIndex` の `RemoteLockManager.get().touchPoll(lockId);` を除去（コメントも整理し純 read を明記）
- [x] `RemoteLockManager.java`: `touchPoll(String)` メソッド撤去
- [x] `RemoteLockManager.java`: `getQueuePollExpiryMs()` ＋ `DEFAULT_QUEUE_POLL_EXPIRY_MS` 撤去
- [x] `RemoteLockManager.java`: `maybeScanStale` の QUEUED 分岐（`QUEUE_EXPIRED`）撤去。ACQUIRED STALE / terminal TTL は残置
- [x] `RemoteLockRecord.java`: `lastPolledAt` / `polled()` / `getLastPolledAt()` 撤去、関連コメント整理
- [x] `src/main` に poll-keepalive 残存参照なしを grep 確認

### Step 4: テスト

- [x] `RemoteLockManagerTest`: poll-keepalive 2 本（`queuePollExpiryMs` 利用、`QUEUE_EXPIRED` 期待）を撤去
- [x] 追加: `queuedRecordExpiresViaQueueTimeout`（`checkTimeouts()` 駆動・`LOCK_WAIT_TIMEOUT`・失効後リソース非取得）
- [x] 追加: `queuedRecordWithoutTimeoutSurvivesWithoutPolling`（無ポーリングでも QUEUED 維持・`find()` 純 read・release で昇格）
- [x] `RemoteConnectionTest`: `testDoCheckUrl` を `@WithJenkins` 化、`testDoCheckUrlRequiresAdmin`（非 admin → AccessDeniedException）追加

### Step 5: ビルド・検証・同期・commit

- [x] `dev/run-mvn-verify.sh`（in-place、`mvn clean verify`）成功 → `dev/reports/20260620220250-mvn-verify.md`（383/0/1skip・全ゲート ok）
- [x] `dev/jenkins-env/run-e2e.sh` 全件 PASS → `dev/reports/20260620222354-e2e-test.md`（20/20）
- [x] plugin commit ＋ `feature/1025-remote-lr-p1-m1` を `upstream/master`（`8f03dbf`）へ rebase（コンフリクト無し・4/4 replay）
- [ ] rebase 後 `dev/run-mvn-verify.sh` 再実行（新 BOM #1057 込み）成功 → `dev/reports/*-mvn-verify.md` 確認
- [ ] docs-e 同期（REVIEW/DESIGN/STEPS/RESULT）、`LRR_RESULT_P1_M1H.md` 作成、README 索引/Status 更新
- [ ] notes commit（Co-Authored-By なし）。**push しない**

## 変更ファイル一覧（plugin）

| ファイル | 変更 | 状態 |
|---|---|---|
| `RemoteConnection.java` | `doCheckUrl` に @POST＋ADMINISTER | 実装済 |
| `RemoteConnection/config.jelly` | `url` に `checkMethod="post"` | 実装済 |
| `LockableResourcesManager.java` | `doCheckForcedServerId` に @POST | 実装済 |
| `LockableResourcesManager/config.jelly` | `forcedServerId` に `checkMethod="post"` | 実装済 |
| `actions/RemoteApiV1Action.java` | `doIndex` の `touchPoll` 除去 | 実装済 |
| `remote/RemoteLockManager.java` | poll-keepalive 一式・QUEUED 期限分岐 撤去 | 実装済 |
| `remote/RemoteLockRecord.java` | `lastPolledAt`/`polled()`/`getLastPolledAt()` 撤去 | 実装済 |
| `remote/RemoteLockManagerTest.java` | poll-keepalive 2 本を置換 | 実装済 |
| `RemoteConnectionTest.java` | `doCheckUrl` を @WithJenkins 化・非 admin 権限テスト追加 | 実装済 |
| `pom.xml` | rebase で BOM bump（#1057）を取り込み | 未（Step 5） |
