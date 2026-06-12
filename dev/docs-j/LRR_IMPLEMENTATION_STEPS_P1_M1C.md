# M1C Implementation Steps (Remote lock - Phase 1 / M1C)

このファイルは M1C の進捗トラッカーです。
M1B 完了時レビュー（`LRR_REVIEW_P1_M1B.md`）で発覚した新規問題を、
透過等価の徹底により解消します（設計は `LRR_DESIGN_P1_M1C.md`）。

---

## 背景：M1B レビューで発覚した問題

| 指摘 | 重さ | 内容 |
|---|---|---|
| C-1 | Critical（fail-open） | ラベル指定 extra がサーバー側でサイレント欠落（main だけロックして body 実行）。M1A 3-1 と同型。設計書 §4 とも矛盾 |
| C-2 | 並行性 | `release()` が `syncResources` 外で状態判定 → QUEUED 昇格と競合し孤児ロック。M1A 4-5 と同型 |
| M-2 | 軽微 | extra-only リクエストの client/server 非対称（client 許容・server 400） |
| M-3 | 軽微 | `consecutivePollFailures` が onResume でリセットされない |
| M-1 | 軽微（表示のみ） | onResume の QUEUED 再開で displayTarget が lockId に劣化 → **後送り** |

### 意思決定（2026-06-12, AskUserQuestion）

- **C-1: (a) 完全実装**（400 拒否ではなく）。
- 軽微は **M-2・M-3 同梱**、M-1 後送り。

---

## アーキテクチャ変更概要（Step1 の肝）

### M1B 構造（問題あり）

```
即時取得  : RemoteLockManager.tryAcquireRecord     ┐ extra を e.getResource() だけで集計
キュー昇格 : LRM.checkRemoteResourcesAvailable      ┘ → label-extra を両経路で黙って捨てる
                                                       空 exposeLabel の label 解釈も両経路で食い違い
```

### M1C 構造（統一セレクタリゾルバ）

```
LockableResourcesManager に新設（single source of truth）:
  validateRemoteSelectors(req) -> errorCode | null   // 構造妥当性（存在・公開）
  resolveRemoteAvailable(req)  -> List<String> | null // 空き解決（claimedSet で重複排除・アトミック）

即時取得  : RemoteLockManager.tryAcquireRecord  → validate → resolve → lockForRemote / QUEUED / SKIPPED
キュー昇格 : LRM.getNextRemoteEntry             → resolveRemoteAvailable（同一メソッド）
```

- main（resource/label）と各 extra を「セレクタ」として一様に解決。
- label セレクタは exposeLabel フィルタ + quantity、`claimedSet` でセレクタ間重複を排除。
- main + 全 extra が同時取得できる時のみ ACQUIRED（部分ロックなし）。

---

## ステップ一覧

### 0. 事前準備（完了済み）

- [x] M1B 全完了（plugin `02fcfae`、360 件）
- [x] m1c ブランチ作成（m1b ベース）
- [x] `LRR_REVIEW_P1_M1B.md`（j+e）作成（notes `7f5d220`）

### Step 1: C-1 / C-2 — 統一セレクタリゾルバ + release 直列化

**実装:**
- `LockableResourcesManager`: `validateRemoteSelectors` / `validateSelector` / `hasExposedCandidate` /
  `resolveRemoteAvailable` / `claimSelector` を新設。`checkRemoteResourcesAvailable` を廃止し
  `getNextRemoteEntry` を `resolveRemoteAvailable` に切替。
- `RemoteLockManager.tryAcquireRecord`: リゾルバ委譲に書き換え（`tryAcquireAll`/`tryAcquireByLabel`/
  `isExposedResource` を削除）。
- `RemoteLockManager.release`: `syncResources` 下で状態判定、QUEUED は `markFailed("RELEASED")` →
  `unqueueRemote`。解放（`unlockRemoteResources`/`scheduleQueueMaintenance`）はロック外で実行。

**テスト（RemoteLockManagerTest +8）:** label-extra アトミック取得 / busy 時 QUEUED（部分ロックなし）/
main label + extra label の重複排除 / 総数不足で QUEUED / extra label の UNKNOWN_LABEL /
キュー昇格 / extra-only / `releasingQueuedRecordPreventsLaterPromotion`(C-2 回帰)。

#### 完了条件

- [x] 実装完了
- [x] `mvn test` 確認完了（**370 件 / 0 失敗**、`dev/reports/20260612192153-mvn-test.log`）
- [x] コミット済み (`3f1e78a`)

記録: 2026-06-12 実装完了。即時/キューを一本化、空 exposeLabel の挙動差も解消。

### Step 2: M-2 / M-3 — extra-only 受理 + poll 予算リセット

**実装:**
- `RemoteApiV1Action`（POST /acquire）: extra が非空なら main なしでも受理（`MISSING_TARGET` を
  `resource && label && !hasExtra` のときだけに変更。メッセージも `..., extra` に更新）。
- `LockStepExecution.onResume`: QUEUED 再開時に `consecutivePollFailures = 0`。

**テスト（RemoteApiV1ActionTest +2）:** HTTP 経由の label-extra 取得（C-1 を API 層でも実証）/
extra-only 取得（202）。

#### 完了条件

- [x] 実装完了
- [x] `mvn test` 確認完了（370 件に含む、上記ログ）
- [x] コミット済み (`5296b50`)

記録: 2026-06-12 実装完了。extra-only は local lock() 等価。

### Step 3: E2E S14 + 全件回帰

**実装:**
- `dev/jenkins-env/scenarios/extra-label-resources.sh`（S14, P1M1C）新設。
  resource + label 指定 extra が**単一 lease**でロックされること（C-1 の核心）を CP02 で直接検証。
- `run-e2e.sh` に S14 / `m1c-series` を登録。E2E 仕様（j+e）に S14/P1M1C を追記。

#### 完了条件

- [x] シナリオ + 登録 + 仕様（j+e）（notes `109771f`）
- [x] **`run-e2e.sh --clean-start` 全 17 件 PASS**（`dev/reports/20260612201703-e2e-test.md`、2026-06-12）
- [x] レポートを `dev/reports/` に保存し結果を記録

記録: 2026-06-12 完了。**全 17 シナリオ 17/17 PASS（pass=17 fail=0 skip=0）**。
S14 の CP02 で main(R1) と label-extra(GPU) が**同一 lease**（`8d4068ae…`）でロックされ、
完了後に両方解放されることを実証（C-1 の核心）。S10〜S13・D01〜D03 含む既存全件も回帰クリア。

### Step 4 (follow-up F-1): label quantity 未指定 = マッチ全部

ユーザー指摘「extra 問題が M1A/M1B/M1C と解決していない」を受けた追加調査で発覚した
**長年の非等価**。`lock(label: X)`（quantity 未指定）は local では「0 = all」で全部ロックするのに、
remote は M1A 以降 1 個に倒していた（`claimSelector` の `?: 1`、POST `optInt("quantity", 1)`）。
毎テストが quantity を明示していたため C-1/C-2 と同じく検証層を素通りしていた。

**実装:**
- `LockableResourcesManager.claimSelector`: label セレクタで `quantity<=0` のとき、公開候補プール
  全件を need とする（local `getRequiredAmount` の「0 = all」と等価）。`quantity > プール` は QUEUED 据置。
- `RemoteApiV1Action`（POST /acquire）: main/extra とも `optInt("quantity", 1)` → `0`。

**テスト:** ユニット（RemoteLockManagerTest）bare-label 全取得 / 全空くまで QUEUED→全取得 /
bare-label-extra 全取得 / quantity>プールで QUEUED、（RemoteApiV1ActionTest）quantity 無し POST で全取得。
E2E **S15 `label-quantity-all`** 追加（`m1c-series`）。

#### 完了条件

- [x] 実装完了
- [x] `mvn test` 確認完了（**375 件 / 0 失敗 / 1 skip**、`dev/reports/20260612232116-mvn-test.log`）
- [x] コミット済み (`2d88834`)
- [x] E2E S15 を含む**全 18 件 18/18 PASS**（`dev/reports/20260612233944-e2e-test.md`）

記録: 2026-06-12 実装完了。extra/label の最後の非等価次元を解消。
S15 CP02 で `lock(label)`（quantity 無し）が 3 プール全部を**単一 lease**（`f37ff5e8…`）で
ロックし完了後に全解放を実証。mvn 375 件・E2E 18/18 とも回帰クリア。

---

## テスト実行方針（M1C）

1. フル回帰は `stabilize-build.sh`（worktree モード）で `mvn test` 全件（VS Code jdt.ls 競合回避）。
2. E2E は最新 `run-e2e.sh` の**全件**（一部 series だけでなく）を `--clean-start` で通し、
   レポートを保存する（サイクル完了条件）。

---

## 更新履歴

- 2026-06-12: 初版作成。M1C（C-1/C-2/M-2/M-3 解消）の実装手順とステップ記録。
- 2026-06-12: follow-up F-1（label quantity 未指定 = 全部）を Step 4 として追加。
  ユーザー指摘で発覚した extra/label の最後の非等価次元を解消。E2E S15 追加。
