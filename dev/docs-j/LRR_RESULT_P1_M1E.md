# M1E 結果（Remote lock - Phase 1 / M1E）

> **対象 plugin ブランチ:** `feature/1025-remote-lockable-resources-p1-m1e`（HEAD `5d956de`）
> **設計:** `LRR_DESIGN_P1_M1E.md` / **手順:** `LRR_IMPLEMENTATION_STEPS_P1_M1E.md` / **レビュー:** `LRR_REVIEW_P1_M1D.md`
> **位置づけ:** M1D レビュー解消（H-1 / M-2）＋意図的単純化 — 未知/未公開は一律 404、公開フィルタは exposeLabel（複数ラベル）単一。

---

## 1. 達成したこと

M1D 完了レビューの指摘を、canonical 委譲（M1D の成果）を保持したまま解消した。M1C の再実装
（`claimSelector` 等）は復活させず、**「M1C の admission 検証（404）＋ M1D の正準解決」の合成**で実現。

| M1D レビュー指摘 | M1E での解 |
|---|---|
| **H-1【Medium / 新規リグレッション】** 未公開/未存在名で ephemeral 量産・永続化 | ✅ 解消。解決経路の `createResource` を撤去。`enqueue` 先頭の exposeLabel 集合ベース admission（`validateRemoteSelectors`）で未存在/未公開を `markFailed(UNKNOWN_*)` → POST が **一律 404**。busy（公開済み）は従来どおり 202 QUEUED。**S17 で「404＋サーバーに ephemeral 非作成」を実環境実証**（`no_ephemeral=NOT_CREATED=true`） |
| **M-2【Low–Med / 設計過剰】** 公開 ExtensionPoint の AND 固定・差し替え不可 | ✅ 解消。`RemoteResourceExposurePolicy` / `ExposeLabelPolicy` を削除し **exposeLabel 単一フィルタ**へ。あわせて **exposeLabel を複数ラベル（空白区切り集合・OR 公開）**対応に（`getExposeLabels`）。allowlist/認可は P1+（YAGNI） |
| **L-3** env var 生成の重複 | ✅ `RemoteQueueEntry.onAcquired` を `LockableResourcesManager.remoteLockEnvVars` に統一（即時取得経路と同一） |
| **L-4** 不正 resourceSelectStrategy のサイレント既定化 | ✅ POST 境界で **400 `INVALID_SELECT_STRATEGY`**（`parseSelectStrategy` の寛容フォールバックは安全網として残置） |
| **L-5** テスト穴 | ✅ unknown→404＋**リソース非作成**回帰 / unexposed→404 / 複数 exposeLabel OR / QUEUED→昇格経路の env var / 不正 strategy 400 を追加。S17（E2E）追加 |

## 2. 設計の要点（懸念事項の確定）

- **意図的非等価:** 「未知/未公開 → 一律 404」は local の「QUEUED で待つ」を**意図的に置き換える**（small-scale 前提・
  存在秘匿・ephemeral 汚染回避・API 慣習）。設計書 §6 に再議論防止の注記。「公開済みだが busy → QUEUED」は透過等価のまま維持。
- **local 無改修（複数 exposeLabel との両立）:** 「要求ラベル X AND（exposeLabel のいずれか）」は、local の単一ラベル一致
  （`getResourcesWithLabel`）を無改修のまま、canonical が持つ **generic な `Predicate` シーム**に remote 層が
  exposeLabel 集合の OR predicate を差し込んで成立させる。exposeLabel の知識は remote 層に閉じ、local の判定ロジックには
  混入しない（設計書 §4-3、再議論防止）。フィルタは個数選択の前に効くため `quantity` 未指定（=可視マッチ全部）も正しい。

## 3. 検証結果

| 観点 | 結果 | 証跡 |
|---|---|---|
| ユニット（worktree フル） | **mvn test 378 件 / 0 失敗 / 0 エラー / 1 skip**（既知 JENKINS-40787） | `dev/reports/20260614002216-mvn-test.log` |
| E2E（`--clean-start` 全件） | **20 シナリオ 20/20 PASS** | `dev/reports/20260614004015-e2e-test.md` |
| 新規 E2E | S17 `remote-unknown-rejected`（404＋ephemeral 非作成） | 同上 |
| 新規/改訂ユニット | unknown→404＋非作成 / unexposed→404 / 複数 exposeLabel OR / 昇格経路 env var / 不正 strategy 400 | RemoteLockManagerTest・RemoteApiV1ActionTest |

> 補足: 初回フル mvn は無関係な local 再起動テスト `LockStepWithRestartTest.lockOrderRestart` がビルド高負荷で
> 180s タイムアウト（実時間 182s）したが、**単独再実行で 7.4s PASS** を確認、フル再実行でも 22s で PASS。M1E 変更とは無関係な
> 負荷起因フレーク。最終レポート `20260614002216-mvn-test.log` は 378/0/0 で BUILD SUCCESS。

S17 検証: `build result=FAILURE`（404 で即時失敗＝ハングしない）/ コンソールに `HTTP 404`・`UNKNOWN_RESOURCE` /
lock body 未実行 / **`NOT_CREATED=true`（サーバーに ephemeral 未作成＝H-1 解消の実証）**。

## 4. 状態

- plugin `feature/...-m1e` HEAD `5d956de`（クリーン）。**push/PR は未**（完璧化後・ユーザー指示待ち）。
- ドキュメント（DESIGN/IMPLEMENTATION_STEPS/本書、j+e）整備済み。E2E 仕様に S17/`m1e-series`（j+e）反映済み。
  README 索引・Status 更新済み。`LRR_REVIEW_P1_M1D` に解消表追記済み。

## 更新履歴

- 2026-06-14: 初版作成。M1E（404 admission＋複数 exposeLabel）の結果サマリ。mvn 378 / E2E 20/20。
