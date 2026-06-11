# M1B Implementation Steps (Remote lock - Phase 1 / M1B)

このファイルは M1B の進捗トラッカーです。
M1A の全体レビュー（`LRR_REVIEW_P1_M1A.md`）と 2026-06-11 の意思決定を受け、
remote LR の透過等価化に向けてドラスティックに再設計します。

---

## 背景：M1A → M1B への方向転換

### レビューで発覚した中核問題

| 問題 | 内容 |
|---|---|
| 3-1 | `extra` がサーバー側でサイレントに欠落（部分ロックで body 実行） |
| 3-2 | `lockEnvVars` 結合文字がスペース（local はカンマ）→ 透過等価でない |
| 3-3 | `remoteLockedBy` が transient → 再起動で remote lock 消失（↓意思決定参照） |
| 3-4 | client 側に `onResume()` がなく QUEUED ハング |
| 3-5 | STALE ロックの管理者解放手段がない |
| 4-1 | 1 回の通信失敗でジョブ即失敗 |
| 4-2 | キュー意味論が local と別物（priority/timeout 等が非実装） |
| 4-3 | remote release が local 待機者を起こさない |
| 5-1 | 全エンドポイントが `Jenkins.READ` のみ |
| 5-2 | credentialsId 未設定時に匿名リクエストを送る |

### 意思決定（2026-06-11）

| 問題 | 決定 |
|---|---|
| **A. extra** | M1B で実装する（サーバー側パース + `tryAcquireAll` 活用） |
| **B. heartbeat 失敗** | ログ警告のみ・ジョブ継続。client 側に timeout 概念は持ち込まない（ジョブ timeout は Jenkins job 設定で） |
| **C. poll 失敗** | リトライ継続。lockId 不整合（server 再起動後の 404/410）でエラー終了 |
| **D. onResume** | QUEUED 中の再起動 → ポーリング再開。ACQUIRED 中の再起動 → body 挙動に委ねる（server 側は fail-close でロック保持） |
| **E. キュー等価** | `RemoteLockManager` の独立キューを廃止。`LockableResourcesManager` の既存キューにリモートリクエストを `RemoteQueueEntry` として投入し、priority/timeout/FIFO を統一 |
| **F. STALE 解放** | 最低限の UI 追加（Force Release ボタン） |
| **3-3 再起動** | `remoteLockedBy` は transient のまま（設計通り）。Jenkins 再起動で remote lock は消失する。これは「起動前に解消することになっている」運用であり、既知の制約として文書化する |

### M1B の設計思想

```
remote 機能は「時間的遅延」と「ネットワーク障害時の fail-close」を除けば、
ローカルリソースと透過等価であるのが大前提。
修正方針は「安全に振る」ではなく「透過等価に全振り」。
```

---

## アーキテクチャ変更概要（Step3 の肝）

### M1A 構造（問題あり）

```
Remote POST /acquire
    → RemoteLockManager (独自 ConcurrentHashMap + 1秒 tick)
         ↓ tryAcquireQueued() が独自に資源チェック
         ↓ priority/timeout/FIFO 未実装
    LockableResourcesManager のキューとは無関係
```

### M1B 構造（透過等価）

```
Remote POST /acquire
    → RemoteLockManager.enqueue()
         → RemoteQueueEntry を生成
         → LockableResourcesManager.queueRemote(entry)
              ↓ queuedContexts と同列で priority ソート
              ↓ proceedNextContext() が統一的に処理
              ↓ priority/timeout/FIFO は LRM の既存ロジックが担う
         → 即時取得を試みる（空きあれば QUEUED → ACQUIRED）

Remote POST /lease/{lockId}/release
    → RemoteLockManager.release(lockId)
         → LockableResourcesManager.unlockRemoteResources()
              ↓ freeResources() 相当
              ↓ while (proceedNextContext()) { } → local + remote 両方の待機者を起こす
              ↓ scheduleQueueMaintenance()
```

`RemoteQueueEntry` はキュー処理に必要なデータを持つ:
- `requiredResources: List<LockableResourcesStruct>` — expose チェック済み資源リスト
- `priority: int` — `RemoteLockRequest.priority` から
- `timeoutDeadlineMillis: long` — `RemoteLockRequest.timeoutForAllocateResource` から
- `candidates: List<String>` — `getAvailableResources()` の結果（transient）
- `onAcquired(resourcesToLock)` — `record.markAcquired()` を呼ぶコールバック
- `onTimeout()` — `record.markFailed("LOCK_WAIT_TIMEOUT")` を呼ぶ

`LockableResourcesManager.proceedNextContext()` は local と remote の両キューを
**統一 priority** で処理するよう拡張する:

```
getNextQueuedContext()  → local の次候補
getNextRemoteEntry()    → remote の次候補
→ priority 比較して高い方を処理
```

---

## ステップ一覧

### 0. 事前準備（完了済み）

- [x] M1A Step 0〜6 全完了（plugin `c782c28`、347 件テスト）
- [x] E2E 全 12 シナリオ成功（`run-e2e.sh`、2026-06-11）
- [x] レビュー結果を `dev/docs-j/LRR_REVIEW_P1_M1A.md` に記録
- [x] M1B 意思決定を本ファイルに記録

---

### 1. 小修正群（透過等価の前提条件）

**目的:**
M1A のレビューで発覚した小バグ群を先に修正して、Step2 以降の基盤を整える。

#### 1-a. lockEnvVars 結合文字修正

- `RemoteLockManager.generateLockEnvVars()` の `String.join(" ", names)` を
  `String.join(",", names)` に修正（local `LockStepExecution.proceed()` と等価化）
- `LRR_DESIGN_P1_M1A.md` §3 の仕様例も修正（`"resource1 resource2"` → `"resource1,resource2"`）

#### 1-b. exposeLabel Javadoc 修正

- `LockableResourcesManager.exposeLabel` フィールドの Javadoc「When empty or null all
  resources are eligible.」を削除（実挙動は「empty = 全リソース非公開」）
- 正しい説明「When empty or null, no resources are exposed（opt-in）」に置き換える

#### 1-c. credentialsId 未設定 = 匿名リクエスト（変更なし）

- 空文字 `credentialsId` = 認証不要サーバー向けの匿名リクエストは正規ユースケースのため変更しない
- 非空 `credentialsId` が解決できない場合は既存コードが `AbortException` を正しく投げる（既実装・変更不要）

#### 1-d. forcedServerId バリデーション実装

- `LockableResourcesManager.Descriptor` に `doCheckForcedServerId()` を追加
  (`forcedServerId` が設定されているが `remotes` に存在しない場合は warning)
- `setForcedServerId()` でも即時チェックし、不整合なら警告ログ

#### 完了条件

- `mvn test -Dtest=LockStepRemoteTest,RemoteLockManagerTest,LockableResourcesManagerRemoteConnectionTest`
- `mvn test` 全件 BUILD SUCCESS

- [ ] 実装完了
- [ ] `mvn test` 確認完了
- [ ] コミット済み

記録:

---

### 2. extra 実装

**目的:**
`lock(resource: 'r1', extra: [{resource: 'r2'}], serverId: 'b')` を remote でも正しく
アトミックロックできるようにする。M1A では `extra` がサーバー側で無視されていた。

#### 実装内容

**`RemoteApiV1Action.AcquireRouter.doIndex()`:**
- `lockRequestJson.optJSONArray("extra")` をパースして `List<RemoteLockRequest.ExtraResource>` を構築
- `resource` と `label` の両方 null の `ExtraResource` エントリを 400 で拒否
- `RemoteLockRequest` コンストラクタに extra を渡す

**`RemoteApiV1Action` の expose チェック拡張:**
- extra 内の resource-based エントリも exposeLabel チェックを通す
  （expose されていない resource が extra に含まれていれば 404 UNKNOWN_RESOURCE）
- label-based extra エントリ: exposeLabel と一致する候補が 0 件なら 404 UNKNOWN_LABEL

**テスト:**
- `RemoteApiV1ActionTest`: extra-resource を含む POST /acquire が 202 で処理されること
- `RemoteApiV1ActionTest`: extra に expose されていないリソースが含まれると 404
- `RemoteLockManagerTest`: resource + extra の同時ロック/解放（既存 `tryAcquireAll` 経由）
- `LockStepRemoteTest`: `extra` 付き DSL を remote で実行して body が成功すること

#### 完了条件

- resource + extra のアトミックロックが機能すること
- expose チェックが extra にも適用されること
- `mvn test` 全件 BUILD SUCCESS

- [ ] 実装完了
- [ ] `mvn test` 確認完了
- [ ] コミット済み

記録:

---

### 3. RemoteLockManager → LRM キューブリッジ再設計

**目的:**
`RemoteLockManager` の独立キューを廃止し、remote リクエストを
`LockableResourcesManager` の既存キューに統合する。
priority / timeout / FIFO / local-remote 公平性を全部 LRM の既存ロジックに委ねる。

#### 新規クラス: `remote/RemoteQueueEntry.java`

```
RemoteQueueEntry {
    RemoteLockRecord record;              // コールバック対象
    List<LockableResourcesStruct> requiredResources;  // expose 済み資源リスト
    int priority;
    long timeoutDeadlineMillis;
    transient List<String> candidates;   // getAvailableResources() キャッシュ

    boolean isValid()            → record.getState() == QUEUED
    boolean isTimedOut()         → deadline 超過チェック
    void onAcquired(resourcesToLock) → record.markAcquired(names, lockEnvVars)
    void onTimeout()             → record.markFailed("LOCK_WAIT_TIMEOUT")
    int getPriority()
    long getTimeoutDeadlineMillis()
    String getResourceDescription()
}
```

exposeLabel チェック済みリソースリストを POST /acquire 時に解決して渡すことで、
キュー処理中の再チェックを不要にする。

#### `LockableResourcesManager` の変更

```java
// 新フィールド（transient: Jenkins 再起動で消える、remote lock と同じライフサイクル）
private transient final List<RemoteQueueEntry> remoteQueueEntries = new ArrayList<>();

// 新メソッド
void queueRemote(RemoteQueueEntry entry)          // priority ソートして追加
void unqueueRemote(String lockId)                 // lockId で検索して削除
boolean lockForRemote(List<LockableResource> resources, String lockId, String reason)
void unlockRemoteResources(List<String> resourceNames, String lockId)
// → freeResources() 相当 + while(proceedNextContext()) + save() + scheduleQueueMaintenance()

// 変更: proceedNextContext()
// 既存の getNextQueuedContext() と新設の getNextRemoteEntry() を比較して
// priority が高い方を先に処理
private boolean proceedNextContext() {
    QueuedContextStruct nextLocal = getNextQueuedContext();
    RemoteQueueEntry nextRemote = getNextRemoteEntry();
    
    if (nextLocal == null && nextRemote == null) return false;
    
    if (shouldPickRemote(nextLocal, nextRemote)) {
        processRemoteEntry(nextRemote);  // lockForRemote() + entry.onAcquired()
    } else {
        processLocalEntry(nextLocal);    // 既存の lock() + LockStepExecution.proceed()
    }
    return true;
}

private boolean shouldPickRemote(local, remote) {
    if (local == null) return remote != null;
    if (remote == null) return false;
    return remote.getPriority() > local.getPriority();
}
```

**`getNextRemoteEntry()`** は `getNextQueuedContext()` のミラー:
- timeout チェック → `entry.onTimeout()`、リストから除去
- `getAvailableResources(entry.requiredResources)` → 空きチェック
- 空きがあれば entry を返す

#### `RemoteLockManager` の変更

- **削除**: `tryAcquireQueued()` のロジック（LRM のキューに移行）
- **変更**: `doRun()` は `maybeScanStale()` のみ（STALE 判定・TERMINAL TTL 清掃は継続）
- **変更**: `enqueue()`:
  1. `RemoteLockRecord` を生成（QUEUED 状態）
  2. `lockRequest` から `LockableResourcesStruct` リストを解決（expose チェック込み）
  3. `RemoteQueueEntry` を生成
  4. `synchronized(syncResources)` で即時取得を試みる
     - 空きあり → `lockForRemote()` + `record.markAcquired()` → QUEUED 飛ばして ACQUIRED
     - `skipIfLocked=true` で空きなし → `record.markSkipped()`
     - 空きなし → `LRM.queueRemote(entry)` で QUEUED
  5. `records.put(lockId, record)` は変わらず（ACQUIRED も QUEUED も保持）
- **変更**: `release()`:
  1. `records.remove(lockId)` は変わらず
  2. ACQUIRED/STALE なら `LRM.unlockRemoteResources(names, lockId)` を呼ぶ
     （`scheduleQueueMaintenance()` が内部で呼ばれる）
  3. QUEUED なら `LRM.unqueueRemote(lockId)` を呼ぶ

#### テスト

- `RemoteLockManagerTest`: release 後に local pipeline の lock が取れることを確認
- `RemoteLockManagerTest`: priority が高い remote entry が local entry より先に処理されること
- `RemoteLockManagerTest`: `timeoutForAllocateResource` で FAILED になること
- `LockStepRemoteTest`: 既存テスト全件（regression）

#### 完了条件

- remote release が local 待機者を起こすこと
- priority が unified であること
- `mvn test` 全件 BUILD SUCCESS（稲妻ビルド → stabilize-build.sh）

- [ ] 実装完了
- [ ] `mvn test` 確認完了
- [ ] コミット済み

記録:

---

### 4. heartbeat/poll リトライ（fail-close 維持・ジョブ継続）

**目的:**
- heartbeat 失敗はログ警告のみ、ジョブは継続する（B 案: client 側 timeout なし）
- poll 失敗は指数バックオフでリトライ。lockId 不整合（server 再起動後の 404/410）でエラー終了
- server が再起動した場合、client は lockId 不整合を検知してエラー終了できる

#### 実装内容

**heartbeat ループ (`startRemoteHeartbeat()` 内の lambda):**
```
try {
    client.heartbeatLease(remote, authorizationHeader, lockId);
} catch (Exception ex) {
    // fail-close: log warning, keep running
    LOGGER.log(Level.WARNING, "Remote heartbeat failed (continuing): ...", ex);
    // NOTE: do NOT call finishRemoteFailure()
}
```

**poll ループ (`pollRemoteStatus()`):**
- `RemoteApiException` で HTTP 4xx/5xx/IOException → 以前は即 `finishRemoteFailure()`
- 変更: 通信失敗は `consecutivePollFailures` カウンタを増加、閾値未満はスキップ継続
- 閾値: `STALE_THRESHOLD_MS` と揃える（デフォルト 60 秒 / 3 秒 interval = 20 回）
- `status.getState() == FAILED` + `errorCode == "LOCK_NOT_FOUND"` → エラー終了（lockId 不整合）
- HTTP 404/410 は lockId 不整合と判断 → エラー終了

**新フィールド:**
```java
private volatile int consecutivePollFailures = 0;
private static final int MAX_CONSECUTIVE_POLL_FAILURES = 20; // ≈60 秒
```

#### 完了条件

- heartbeat が失敗しても body が継続すること
- poll が一時的に失敗しても ACQUIRED までポーリングが継続すること
- 404 で `finishRemoteFailure` が呼ばれること
- `mvn test` 全件 BUILD SUCCESS

- [ ] 実装完了
- [ ] `mvn test` 確認完了
- [ ] コミット済み

記録:

---

### 5. onResume 実装（client 側再起動からの復帰）

**目的:**
local-A 側が再起動した際に remote フローが適切に再開または後処理される。

#### 挙動設計

| 再起動時の状態 | 再起動後の挙動 |
|---|---|
| **QUEUED 中**（`remoteLockId` あり、`remoteBodyStarted == false`） | ポーリングループを再開。server 側は引き続き queue 待ちのため整合 |
| **ACQUIRED 中**（`remoteBodyStarted == true`） | body は Jenkins が中断済み。`releaseRemoteLockBestEffort()` を呼んで server 側の lease を解放。Step失敗で終了 |

#### 実装内容

**`LockStepExecution` に `onResume()` を追加:**
```java
@Override
public void onResume() {
    if (remoteLockId == null || remoteLockId.isEmpty()) {
        // local flow: onResume does nothing for LockStepExecution normally
        return;
    }
    if (remoteBodyStarted) {
        // body was interrupted by restart — release and fail
        releaseRemoteLockBestEffort();
        getContext().onFailure(new AbortException(
            "Jenkins restarted during remote lock body execution (serverId="
            + remoteServerId + ", lockId=" + remoteLockId + "). "
            + "Remote lock released best-effort."));
        return;
    }
    // Re-arm polling (credentials must be re-resolved from context)
    try {
        LockableResourcesManager lrm = LockableResourcesManager.get();
        RemoteConnection remote = findRemoteConnectionOrFail(lrm, remoteServerId);
        String authorizationHeader = resolveAuthorizationHeader(remote);
        RemoteApiClient client = new RemoteApiClient();
        Run<?, ?> run = getContext().get(Run.class);
        String displayTarget = remoteLockId; // best-effort display
        startRemotePolling(remote, authorizationHeader, client, run, displayTarget);
    } catch (Exception ex) {
        getContext().onFailure(ex);
    }
}
```

#### 完了条件

- QUEUED 中に再起動してもポーリングが再開されること（`LockStepRemoteTest` で確認）
- ACQUIRED 中再起動後に release が呼ばれること
- `mvn test` 全件 BUILD SUCCESS

- [ ] 実装完了
- [ ] `mvn test` 確認完了
- [ ] コミット済み

記録:

---

### 6. STALE 管理者解放 UI

**目的:**
STALE 状態の remote lock をリソース一覧画面から管理者が解放できるようにする。
fail-close 設計のもと「気づいて手動解放」を実現可能にする。

#### 実装内容

**`LockableResource` に `isRemoteLockStale()` を追加:**
```java
public boolean isRemoteLockStale() {
    if (remoteLockedBy == null) return null;
    RemoteLockRecord record = RemoteLockManager.get().find(remoteLockedBy);
    return record != null && record.getState() == RemoteLockState.STALE;
}
```

**`table.jelly` の Action 列に Force Release ボタンを追加:**
```xml
<j:when test="${resource.remoteLockedBy != null}">
  <l:hasPermission permission="${it.UNLOCK}">
    <button
      data-action="release-remote-lock"
      data-lock-id="${resource.remoteLockedBy}"
      class="jenkins-button jenkins-button--tertiary jenkins-!-destructive-color ..."
      tooltip="${%btn.releaseRemoteLock}"
    >
      <l:icon src="symbol-lock-open-outline plugin-ionicons-api" />
    </button>
  </l:hasPermission>
</j:when>
```

**`LockableResourcesRootAction` に `doReleaseRemoteLock()` を追加:**
- UNLOCK 権限チェック
- `RemoteLockManager.get().release(lockId)` を呼ぶ
- `LockableResourcesManager.scheduleQueueMaintenance()`
- JSON でレスポンス

**JS ハンドラ（既存の `lockable-resources-action-button` パターンに追従）:**
- `data-action="release-remote-lock"` を JS で拾って AJAX POST

**`table.properties` / `table.properties_ja` にキー追加:**
- `btn.releaseRemoteLock=Force Release Remote Lock`

#### 完了条件

- STALE 状態のリソースに Force Release ボタンが表示されること
- ボタン押下で `remoteLockedBy` がクリアされ、local 待機者が起きること
- UNLOCK 権限なしでは表示されないこと
- `mvn test` 全件 BUILD SUCCESS

- [ ] 実装完了
- [ ] `mvn test` 確認完了
- [ ] コミット済み

記録:

---

### 7. テスト拡張・回帰固定

**目的:**
M1B の全機能を回帰テストとして固定する。
M1A のテストが全件 regression pass であることを確認する。

#### 追加テスト対象

**`RemoteLockManagerTest`:**
- release 後に local pipeline context が起きること（4-3 修正確認）
- priority = 10 の remote entry が priority = 0 の local entry より先に処理されること
- `timeoutForAllocateResource` 超過で `FAILED` (LOCK_WAIT_TIMEOUT) になること
- STALE → `release()` で resources が free になること

**`LockStepRemoteTest`:**
- `extra` 付き DSL が remote で成功すること
- heartbeat 失敗してもジョブが継続すること（mock server で 410 を返す）
- poll 失敗後のリトライで最終的に ACQUIRED になること
- onResume: QUEUED 状態で再起動相当のポーリング再開

**`RemoteApiV1ActionTest`:**
- `extra` 含む lockRequest が 202 で受理されること
- `extra` に expose されていないリソースが含まれると 404
- `credentialsId` 未設定時の挙動（クライアント側 AbortException）

#### 完了条件

- 追加テスト全件成功
- M1A 全 347 件 regression pass
- `mvn test` (stabilize-build.sh) BUILD SUCCESS、レポートを `dev/reports/` に保存

- [ ] 実装完了
- [ ] `mvn test` 確認完了
- [ ] コミット済み

記録:

---

### 8. E2E 追加シナリオ

**目的:**
M1B の安全主張を裏付けるシナリオを E2E ハーネスに追加する。

#### 追加シナリオ

| ID | スクリプト名 | 検証内容 |
|---|---|---|
| S10 | `extra-resources` | extra 付きリモートロックが B でアトミックに取得/解放されること |
| S11 | `heartbeat-resilience` | heartbeat 失敗中も body が継続し、完了後に release されること |
| S12 | `priority-ordering` | priority が高い remote entry が local entry より先にロックを取れること |
| S13 | `stale-admin-release` | STALE になったロックを UI Force Release で解放でき、待機者が起きること |

#### 完了条件

- 追加 4 シナリオが PASS
- M1A 12 シナリオ回帰確認（`./run-e2e.sh --only all`）
- `dev/reports/` にレポート保存

- [ ] 実装完了
- [ ] E2E 確認完了
- [ ] コミット済み（notes リポジトリ）

記録:

---

## テスト実行方針（M1B）

1. 各ステップ完了後に `mvn test -Dtest=<対象テスト>` で単体確認
2. 各コミット前に `./dev/stabilize-build.sh`（worktree モード）で全件確認
3. テスト件数が減少していないこと（regression）を必ず確認
4. E2E は Step 8 で `./run-e2e.sh` を実行

## コミット運用ルール（M1B）

- 1 ステップ 1 コミットを基本
- コミットメッセージ例:
  - Step 1: `fix(remote-lock): lockEnvVars comma separator, exposeLabel javadoc (M1B)`
  - Step 2: `feat(remote-lock): extra resources support in remote acquire (M1B)`
  - Step 3: `refactor(remote-lock): integrate RemoteLockManager into LRM queue (M1B)`
  - Step 4: `fix(remote-lock): heartbeat/poll retry resilience (M1B)`
  - Step 5: `feat(remote-lock): onResume support for remote lock step (M1B)`
  - Step 6: `feat(remote-lock): admin force-release UI for STALE locks (M1B)`
  - Step 7: `test(remote-lock): M1B regression and new coverage`
  - Step 8: `chore(e2e): add M1B scenarios (extra, resilience, priority, stale-release)`

## 現在ステータス

- 計画作成日: 2026-06-11
- 起点ブランチ: `feature/1025-remote-lockable-resources-p1-m1a`（HEAD: `c782c28`）
- **Step 0: 完了 ✅**
- Step 1〜8: 未着手
