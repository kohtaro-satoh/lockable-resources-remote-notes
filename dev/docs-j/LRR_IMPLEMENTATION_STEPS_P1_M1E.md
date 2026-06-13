# M1E Implementation Steps (Remote lock - Phase 1 / M1E)

このファイルは M1E の進捗トラッカーです（設計は `LRR_DESIGN_P1_M1E.md`）。
**M1D レビュー解消＋意図的単純化** — 未知/未公開を一律 404 で拒否、公開フィルタを exposeLabel 単一に割り切る。

> 命名注記: `作業手順一覧.md` は「作業計画 = `LRR_IMPLEMENTATION_PLAN_XX_YYY.md`」と記すが、既存 5 マイルストーン
> （M1/M1A/M1B/M1C/M1D）と cycle 完了条件は `LRR_IMPLEMENTATION_STEPS_*` を使用しているため、整合のため本書も
> `STEPS` を踏襲する（手順書側の表記ゆれ。必要ならユーザー指示で改名）。

---

## 背景

M1D 完了レビュー（`LRR_REVIEW_P1_M1D.md`）の H-1（未公開/未存在名での ephemeral 量産・永続化＝新規リグレッション）と
M-2（公開 `ExtensionPoint` の過剰）を解消する。canonical 委譲（M1D の成果）は保持し、M1C の再実装（`claimSelector` 等）は
復活させない。実質「M1C の admission 検証（404）＋ M1D の正準解決」の合成。

### 意思決定（2026-06-13, ユーザー確定）

- **H-1 = (a)＋API 流拒否**: remote 解決経路の `createResource` を撤去。未存在/未公開は **一律 404**
  （`UNKNOWN_RESOURCE` / `UNKNOWN_LABEL`）。busy（公開済み・ロック中）は従来どおり 202 QUEUED で peer 解放待ち。
- **M-2 = 単純化**: `RemoteResourceExposurePolicy` / `ExposeLabelPolicy` を削除し exposeLabel フィルタへ。
  `getAvailableResources(..., Predicate)` シームは保持（label quantity=all に必要・local 無改修）。allowlist/認可は P1+（YAGNI）。
- **exposeLabel 複数対応**: 空白区切りのラベル集合として解釈し OR 公開（R のラベル ∩ exposeLabel 集合 ≠ ∅）。
  単一値は後方互換。「要求ラベル AND exposeLabel(集合)」は generic Predicate で吸収＝local の判定ロジック無改修（設計 §4-3）。
- **L-3/L-4/L-5**: env var 1 本化／不正 strategy は 400／テスト拡充。

---

## ステップ一覧

### 0. 事前準備

- [x] m1e ブランチ作成（m1d ベース、HEAD `819daa0`）= `feature/1025-remote-lockable-resources-p1-m1e`
- [x] `LRR_DESIGN_P1_M1E` / 本書（j+e）整備、`LRR_REVIEW_P1_M1D` に M1E 対応バナー、README 索引更新

### Step 1: M-2 単純化（exposeLabel フィルタ）＋ exposeLabel 複数ラベル対応

- `RemoteResourceExposurePolicy.java` / `ExposeLabelPolicy.java` を削除。
- **exposeLabel 複数対応**: `getExposeLabels()` を追加（`exposeLabel` String を `split("\\s+")` ＋ fixEmpty で集合化）。
  `getExposeLabel()` / setter は不変（後方互換）。
- `availableForRemote` を `RemoteResourceExposurePolicy.visibilityFor(req)` から **exposeLabel 集合の OR predicate** に変更:
  `r -> !Collections.disjoint(r.getLabelsAsList(), exposeLabels)`（exposeLabels 空 → `r -> false`）。
- `getAvailableResources(..., Predicate)` / `getFreeResourcesWithLabel(..., Predicate)` のシームは維持（local 無改修）。
- import 整理（`RemoteResourceExposurePolicy` 参照除去）。
- config UI: `config.jelly` のヘルプ／`config.properties` のタイトルを「空白区切りで複数可」に更新（textbox 自体は不変）。

#### 完了条件
- [x] 実装完了 / [ ] コンパイル緑（policy 参照が残っていない）/ [ ] 単一値の後方互換を確認 / [ ] コミット

### Step 2: H-1 解消（createResource 撤去 ＋ 404 admission）

- `addRemoteStruct` の `createResource(resource)` 呼び出しを撤去。
- `validateRemoteSelectors(req)` / `validateSelector` / `hasExposedCandidate` を **exposeLabel ベースで復活**
  （`ExtensionPoint` ではなく exposeLabel 直参照。main ＋各 extra を検証、未存在/未公開 → `UNKNOWN_RESOURCE` /
  公開候補 0 のラベル → `UNKNOWN_LABEL`、セレクタ非在 → null）。
- `RemoteLockManager.enqueue` の `synchronized` 先頭で `validateRemoteSelectors` を呼び、errorCode があれば
  `record.markFailed(errorCode)` して return（`toRemoteStructs` に進まない＝作成も解決もしない）。
- `RemoteApiV1Action` POST `/acquire`: enqueue 後、`record.state == FAILED && errorCode ∈ {UNKNOWN_RESOURCE,
  UNKNOWN_LABEL}` を **404** にマップ（それ以外は従来どおり 202）。

#### 完了条件
- [x] 実装完了 / [ ] 未存在/未公開 → 404・リソース未作成を確認 / [ ] busy → 202 QUEUED 維持を確認 / [ ] コミット

### Step 3: 軽微（L-3 / L-4）

- **L-3**: `RemoteQueueEntry.onAcquired` を `LockableResourcesManager.remoteLockEnvVars(variable, resources)` 経由に統一。
- **L-4**: POST 境界で未知 `resourceSelectStrategy` を **400 `INVALID_SELECT_STRATEGY`** として弾く。
  `parseSelectStrategy` の寛容フォールバックは安全網として残置。

#### 完了条件
- [x] 実装完了 / [ ] コミット

### Step 4: テスト整備（L-5）

- M1D の「unknown→QUEUED」前提テストを **「unknown→404（terminal）」前提に改訂**:
  - `enqueueQueuesWhenResourceDoesNotExist` → 未存在名 acquire が 404/FAILED `UNKNOWN_RESOURCE`、
    **かつ当該名のリソースが作成・残存していない**ことをアサート（H-1 直撃の回帰）。
  - `enqueueQueuesForUnknownLabel` → `UNKNOWN_LABEL`。
  - `RemoteApiV1ActionTest` の「未公開 → 202 QUEUED」を **「→ 404」**に戻す（一律 404）。
- policy 削除に伴うテスト整理（`RemoteResourceExposurePolicy` を参照するテストがあれば exposeLabel ベースへ）。
  exposeLabel フィルタ（`unexposedNamedResourceStaysQueued` 相当）を **「未公開 → 404」**に改める。
- 追加: selectStrategy（`RANDOM`）の remote 反映 / QUEUED→昇格経路でのプロパティ env var（`onAcquired`）/
  不正 strategy → 400。
- **exposeLabel 複数対応**: `exposeLabel = "gpu license"` で gpu/license いずれかを持つリソースが公開され、
  どちらも持たないリソースは未公開→404 になること（OR 公開）。単一値の後方互換も明示的にアサート。
- `stabilize-build.sh`（worktree）でフル `mvn test`、レポート保存。

#### 完了条件
- [x] テスト改訂・追加完了 / [ ] `mvn test` 緑（件数・0 失敗・`dev/reports/…-mvn-test.log`）/ [ ] コミット

### Step 5: E2E メンテ + 全件完走

- 既存シナリオは M1E 挙動で全件 PASS（exposeLabel 単一化・404 化の影響確認）。
  特に S08（label-env-vars）/ S14 / S15 / S16 が exposeLabel 単一フィルタで不変であること。
- 追加: **S17 `remote-unknown-rejected`**（`m1e-series`）— 未存在/未公開リソースの acquire が **404** で返り、
  **サーバーのリソース一覧が増えていない**（ephemeral 非作成）ことを実環境で実証。
- `run-e2e.sh --clean-start` 全件 PASS、レポート保存。

#### 完了条件
- [x] E2E メンテ（S17 追加 + run-e2e 登録 + 仕様 j+e）/ [ ] 全件 PASS（`dev/reports/…-e2e-test.md`）/ [ ] notes コミット

### Step 6: ドキュメント最終化 + サイクル完了

- `LRR_RESULT_P1_M1E`（j+e）作成、`LRR_REVIEW_P1_M1D` に解消表（H-1/M-2/L-3/L-4/L-5）追記、
  E2E 仕様（S17 / `m1e-series`、j+e）反映、README 索引更新、docs-e 全同期。
- plugin / notes をコミット（Co-Authored-By なし・push しない）。

#### 完了条件
- [x] `*_M1E.md`（DESIGN/STEPS/RESULT、j+e）整備 / [ ] mvn フル緑 / [ ] E2E 全件 PASS / [ ] 解消表・索引更新

---

## テスト実行方針（M1E）

1. フル回帰は `stabilize-build.sh`（worktree モード）。`mvn test` は M1E で変更したコードを網羅。
2. E2E は最新 `run-e2e.sh` の**全件**を `--clean-start` で完走しレポート保存（サイクル完了条件）。
3. サイクル完了条件は [[rlr-cycle-definition-of-done]]: `*_M1E.md`（j+e）＋ stabilize-build フル ＋ run-e2e 全件。

## 更新履歴

- 2026-06-13: 初版作成。M1E（M1D レビュー解消＋単純化）の実装ステップ計画。実装は未着手（レビュー後に開始）。
- 2026-06-14: 全 Step 完了。plugin `5d956de`。mvn 378 / 0 失敗（`dev/reports/20260614002216-mvn-test.log`）、
  E2E 20/20 PASS（S17 追加、`dev/reports/20260614004015-e2e-test.md`）。docs（DESIGN/STEPS/RESULT、j+e）整備、
  `LRR_REVIEW_P1_M1D` 解消表更新、README 索引・Status 更新済み。
