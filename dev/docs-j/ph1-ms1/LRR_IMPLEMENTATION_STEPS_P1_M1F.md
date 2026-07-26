# M1F Implementation Steps (Remote lock - Phase 1 / M1F)

このファイルは M1F の進捗トラッカーです（設計は `LRR_DESIGN_P1_M1F.md`）。
**M1E レビュー指摘の選別対応** — ネットワークブリッジのトランスポート/境界層の堅牢化（L-b/L-c/L-d）のみ実施。
lock() ロジック由来の穴（M1E-1 ほか）は観点により意図的に残置し、設計 §4 に明文化。

---

## 背景

`LRR_REVIEW_P1_M1E.md` の指摘を、ユーザー確定の観点「lock() 既存ロジックに乗り、ネットワークブリッジ由来以外の
remote 独自判定を増やさない」で選別。実施 = L-b/L-c/L-d（ブリッジ堅牢化）。残置 = M1E-1/M1E-2/M1E-3/L-a/L-e。

---

## ステップ一覧

### 0. 事前準備

- [x] m1f ブランチ作成（m1e ベース、HEAD `5d956de`）= `feature/1025-remote-lockable-resources-p1-m1f`
- [x] `LRR_DESIGN_P1_M1F` / 本書（j+e）整備、README 索引更新（後述）

### Step 1: L-b — remote base URL のスキーム検証

- [x] `RemoteConnection.validate()` に `isHttpUrl` 検査を追加（非 http(s) → `IllegalArgumentException`）。
- [x] `RemoteConnection.DescriptorImpl` を `@Extension` 化し `doCheckUrl`（`FormValidation`）を追加。
- [x] 共有ヘルパ `isHttpUrl`（trim ＋ 小文字 ＋ `http(s)://` prefix）。
- テスト: `RemoteConnectionTest`
  - [x] `testValidateAcceptsHttpsUrl`（https を受理）
  - [x] `testValidateRejectsNonHttpUrl`（`file:` / `ftp:` / スキーム無しを拒否）
  - [x] `testDoCheckUrl`（http/https=OK、file/空/null=ERROR）

### Step 2: L-c — POST ボディサイズ上限

- [x] `RemoteApiV1Action` に `MAX_BODY_CHARS = 1 MiB` ＋ private `PayloadTooLargeException`（`IOException`）。
- [x] `parseJsonBody` で累積文字数が上限超過時に `PayloadTooLargeException` を投げる。
- [x] POST ハンドラで `PayloadTooLargeException` を先に catch → **413 `PAYLOAD_TOO_LARGE`**（既存 `INVALID_JSON` 400 は維持）。
- テスト: `RemoteApiV1ActionTest`
  - [x] `acquireWithOversizedBodyReturns413`（>1 MiB ボディ → 413 `PAYLOAD_TOO_LARGE`）

### Step 3: L-d — POST の FAILED → 4xx 写像一般化

- [x] POST `/acquire` の `FAILED` 分岐を一般化: `UNKNOWN_*` は 404、それ以外は **400 `ACQUIRE_FAILED`**（errorCode 優先）。
- [x] 202 フォールスルー経路を封鎖。
- 防御的変更（現状 `MISSING_TARGET` は境界で到達不能）。既存 404 テスト（`UNKNOWN_RESOURCE`/`UNKNOWN_LABEL`）が一般化分岐を回帰カバー。

### Step 4: ドキュメント — 残置懸念の明文化

- [x] 設計 §4 に M1E-1 / M1E-2 / M1E-3 / L-a / L-e を「意図的に残置する懸念」として記録（再議論防止）。
- [x] `LRR_REVIEW_P1_M1E.md`（j+e）に M1F 対応バナーを追記（実施/残置の対応表）。
- [x] README レビュー索引・Status を更新。

### Step 5: ビルド・E2E・コミット

- [x] `dev/stabilize-build.sh`（worktree、コミット済み HEAD `6319f12` をビルド）で mvn フル成功 = **382 / 0 失敗 / 1 skip**。
  - `dev/reports/20260614104134-mvn-test.log`（BUILD SUCCESS）。
- [x] `dev/jenkins-env/run-e2e.sh --clean-start` 全件成功 = **20/20 PASS**（既存 20 シナリオの回帰。新規シナリオなし）。
  - `dev/reports/20260614105955-e2e-test.md`。
- [x] plugin commit `6319f12`。古いレポート（M1E 分）を削除し最新ひとつずつに整理。notes commit は本ステップで実施。

---

## 変更ファイル一覧（plugin）

| ファイル | 変更 |
|---|---|
| `RemoteConnection.java` | L-b: `validate()` スキーム検査、`isHttpUrl`、`@Extension DescriptorImpl.doCheckUrl` |
| `actions/RemoteApiV1Action.java` | L-c: `MAX_BODY_CHARS`/`PayloadTooLargeException`/`parseJsonBody` 上限・413 マップ。L-d: `FAILED`→4xx 一般化 |
| `RemoteConnectionTest.java` | L-b テスト 3 件 |
| `actions/RemoteApiV1ActionTest.java` | L-c テスト 1 件 |

## E2E 方針

M1F は HTTP 境界/トランスポート層の堅牢化のみで、lock() の振る舞い・透過等価・公開意味論を変えない。
**新規 E2E シナリオは追加せず、既存 20/20 の回帰維持で十分**とする（L-b/L-c/L-d はユニットで直接カバー済み）。
