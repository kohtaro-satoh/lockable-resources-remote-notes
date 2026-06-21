# M1H 設計（Remote lock - Phase 1 / M1H：PR #1055 CI 指摘対応）

> 起点レビュー: `LRR_REVIEW_P1_M1H.md`
> ブランチ: `feature/1025-remote-lr-p1-m1`（M1H 開始時 HEAD = `5136daa`、base `master` = `87c4a7e`）
> 位置づけ: **M1G（純リファクタ）完了・PR #1055 提出後**に本家 CI が提起した security 4 件と master ドリフトへの是正サイクル。
> M1G とは独立した開発サイクルであり、M1H のみ「意図的な挙動変更（B2）」を 1 点含む。

## 1. 目的

PR #1055 をマージ可能・CI クリーンにする。対象は (a) `github-advanced-security[bot]` の security 4 件、(b) master 同期。

## 2. security 是正（#49/#50/#51 — 機械的）

Stapler web メソッドの CSRF/権限ハードニング。挙動意味論は不変。

| # | 対象 | 是正 |
|---|---|---|
| 49/51 | `RemoteConnection.DescriptorImpl#doCheckUrl` | `@POST`（`org.kohsuke.stapler.verb.POST`）＋ `Jenkins.get().checkPermission(Jenkins.ADMINISTER)` を付与。`RemoteConnection/config.jelly` の `url` フィールドに `checkMethod="post"` |
| 50 | `LockableResourcesManager#doCheckForcedServerId` | `@POST` のみ付与（ADMINISTER チェックは既設）。`LRM/config.jelly` の `forcedServerId` に `checkMethod="post"` |

> jelly の `checkMethod="post"` は、@POST 化でフォーム検証リクエストが POST になるための対応（無指定だと GET 検証が
> 405 になり検証が壊れる）。

## 3. #52 是正 = B2（挙動変更・本サイクルの核）

**決定（起点レビュー §5 参照）:** `GET /acquire/{lockId}` を純 read 化し、QUEUED の生存性をサーバ側キュー timeout に一本化する。

### 設計上の根拠

- 状態遷移（QUEUED→ACQUIRED、timeout 失敗）は元々 GET に非依存。サーバ側ローカルロジック（`proceedNextContext` /
  1 秒 `PeriodicWork` / `RemoteQueueEntry` の deadline）が所有。
- GET の `touchPoll` 副作用は「QUEUED の見捨てクライアント GC」専用で、`timeoutForAllocateResource == 0`（無限待ち）の
  時しか実効が無い。

### 変更内容

- `RemoteApiV1Action.AcquireStatusResource#doIndex`: `touchPoll(lockId)` 呼び出しを除去（GET=純 read）。`REMOTE` 権限
  チェックと API 有効判定は残す。
- `RemoteLockManager`: `touchPoll(String)` / `getQueuePollExpiryMs()` / `DEFAULT_QUEUE_POLL_EXPIRY_MS` を撤去。
  `maybeScanStale` の **QUEUED 分岐（`QUEUE_EXPIRED`）を撤去**。ACQUIRED の STALE 判定と terminal TTL 掃除は残す。
- `RemoteLockRecord`: `lastPolledAt` / `polled()` / `getLastPolledAt()` を撤去。
- QUEUED の期限は `RemoteQueueEntry.timeoutDeadlineMillis`（= `timeoutForAllocateResource`）に一本化。

### 受容するトレードオフ（明文化）

`timeoutForAllocateResource == 0`（無限待ち）かつクライアント死亡時の QUEUED 枠の ~60 秒早期回収を失う。QUEUED 中は
リソース非保持（枠のみ）、昇格後は ACQUIRED heartbeat-STALE が回収するため安全。ローカル `lock()`（timeout 無し）と整合。

### 代替案と却下理由

| 案 | 内容 | 評価 |
|---|---|---|
| B1 | GET 純 read＋keepalive を POST `/lease` heartbeat に寄せ、QUEUED から heartbeat 開始 | 速い GC を維持・REST も綺麗だが、QUEUED 中に poll+heartbeat の 2 チャネルが走り改修が大きい。不採用 |
| **B2（採用）** | GET から `touchPoll` 除去＝純 read、QUEUED 期限をサーバ側キュー timeout に一本化 | 最小・設計観（遷移はサーバ側ローカルロジック所有）に最も忠実・#52 が自然消滅 |
| B3 | status GET を POST 化 | 症状治療・read を mutation にする・非 RESTful。却下 |

## 4. master 同期

`feature/1025-remote-lr-p1-m1` を `upstream/master`（`8f03dbf`：#1056 crowdin bump / #1057 BOM bump）へ rebase。
コンフリクト無し（`pom.xml` は別ハンク、`merge-tree`・実マージ dry-run ともクリーン＝起点レビュー §2）。

## 5. テスト方針

- `RemoteLockManagerTest` の poll-keepalive 2 本（`queuePollExpiryMs` 利用・`QUEUE_EXPIRED` 期待）を撤去/置換:
  - `queuedRecordExpiresViaQueueTimeout`: QUEUED が `RemoteQueueEntry` の timeout（`timeoutForAllocateResource`）で失効し、
    `LOCK_WAIT_TIMEOUT` になる。失効後はリソースを掴まない。駆動は `checkTimeouts()`（→ proceedNextContext → getNextRemoteEntry）。
  - `queuedRecordWithoutTimeoutSurvivesWithoutPolling`: timeout 無し＋無ポーリングで `doRun()` を繰り返しても QUEUED が
    失効しない（poll-keepalive GC 撤去の回帰ガード）。`find()`（GET 状態経路）が純 read であることも確認。release で昇格も維持。
- `RemoteConnectionTest`: `doCheckUrl` が ADMINISTER を要求するため `@WithJenkins` 化。非 admin が `AccessDeniedException`
  になる `testDoCheckUrlRequiresAdmin` を追加（#49 のカバレッジ）。`doCheckForcedServerId` は既設 `@WithJenkins` テストで維持。
- B2 のみ挙動変更のため、E2E は既存全件の回帰維持で確認（無限待ち＋死亡クライアントの早期回収はシナリオ化対象外＝受容トレードオフ）。

## 6. 含まない（M1H スコープ外）

| 項目 | 備考 |
|---|---|
| 新機能・新 E2E シナリオ | CI 是正サイクルのため追加しない |
| クライアント UI / read-only ミラー | Phase 2（issue #1025） |
| B1（QUEUED heartbeat 化） | 速い GC 維持案。今回は B2 採用のため不実施 |

## 7. 検証

開発サイクル（`作業手順一覧.md`）に従い、`run-mvn-verify.sh`（mvn verify）＋ `run-e2e.sh` を動確の正本とする。

- `dev/run-mvn-verify.sh`（in-place、`mvn clean verify`）で全テスト＋静的ゲート（spotless/spotbugs/checkstyle/pmd/cpd）成功。
- `dev/jenkins-env/run-e2e.sh` 全件 PASS（挙動回帰確認）。
- master 同期（rebase）後、`dev/run-mvn-verify.sh` を再実行し、新 BOM（#1057）込みで全テスト＋ゲート成功を確認。

## 変更ファイル一覧（plugin）

| ファイル | 変更 |
|---|---|
| `RemoteConnection.java` | `doCheckUrl` に @POST＋ADMINISTER、import 追加 |
| `RemoteConnection/config.jelly` | `url` に `checkMethod="post"` |
| `LockableResourcesManager.java` | `doCheckForcedServerId` に @POST、import 追加 |
| `LockableResourcesManager/config.jelly` | `forcedServerId` に `checkMethod="post"` |
| `actions/RemoteApiV1Action.java` | `doIndex` の `touchPoll` 除去（GET 純 read） |
| `remote/RemoteLockManager.java` | poll-keepalive 一式・QUEUED 期限分岐 撤去 |
| `remote/RemoteLockRecord.java` | `lastPolledAt`/`polled()`/`getLastPolledAt()` 撤去 |
| `remote/RemoteLockManagerTest.java` | poll-keepalive 2 本を置換（queue-timeout 失効 / 純 read 生存） |
| `RemoteConnectionTest.java` | `doCheckUrl` を @WithJenkins 化、非 admin 権限テスト追加 |
| `pom.xml` | rebase で BOM bump（#1057）を取り込み |

## 更新履歴

- 2026-06-20: 初版作成。PR #1055 の CI security 4 件（#49–52）＋master 同期に対応する M1H 開発サイクルを定義。
  #49/#50/#51 は機械的ハードニング、#52 は B2（GET 純 read 化・poll-keepalive 撤去・QUEUED 期限をキュー timeout に一本化）。
