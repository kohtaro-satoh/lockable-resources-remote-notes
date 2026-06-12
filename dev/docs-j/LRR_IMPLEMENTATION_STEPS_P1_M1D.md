# M1D Implementation Steps (Remote lock - Phase 1 / M1D)

このファイルは M1D の進捗トラッカーです（設計は `LRR_DESIGN_P1_M1D.md`）。
**真のブリッジ化** — server を lock() の正準パスに通し、機能別残件を構造的に消す。

---

## 背景

M1C 結果（`LRR_RESULT_P1_M1C.md`）の残「真の非等価」3 件（プロパティ env var / ephemeral 自動作成 /
resourceSelectStrategy）は、server が解決・env var 生成を**再実装**しているために機能別に残った。
M1D は再実装を撤去し canonical 委譲＋ env var 共有で一括透過化する。フィルタ（exposeLabel）は
ExtensionPoint として 2 層目に分離。

### 意思決定（2026-06-13, ユーザー協議）

- フィルタ seam は**最初から `ExtensionPoint` 公開**。既定 = exposeLabel。
- 可視性 predicate は `getAvailableResources` の**後方互換オーバーロード**で正準解決へ渡す（B=事前フィルタは
  個数選択が内部で走るため不成立）。
- lock() 返り値は `BodyExecutionCallback.TailCall` の Object パススルーで将来も透過（TailCall を壊さない）。

---

## ステップ一覧

### 0. 事前準備

- [ ] m1d ブランチ作成（m1c ベース、HEAD `2d88834`）
- [ ] `LRR_RESULT_P1_M1C` / `LRR_DESIGN_P1_M1D` / 本書（j+e）整備（notes コミット）

### Step 1: `getAvailableResources` に candidateFilter オーバーロード追加

- `getAvailableResources(structs, logger, strategy, Predicate<LockableResource> candidateFilter)` を追加。
  既存 2 版は `r -> true` で委譲（後方互換）。
- `getFreeResourcesWithLabel(...)` にも predicate を通し、**個数選択の前**に候補を絞る
  （`amount<=0 → 可視候補全部`）。name 分岐は不可視名を弾く。
- local（`start()`）は無改修（既存オーバーロード経由）。

#### 完了条件
- [ ] 実装完了 / [ ] `mvn test` 緑 / [ ] コミット

### Step 2: RemoteResourceExposurePolicy（ExtensionPoint）+ 既定 ExposeLabelPolicy

- `RemoteResourceExposurePolicy extends ExtensionPoint`（`isExposed(resource, request)`）。
- `@Extension ExposeLabelPolicy` = 現行 exposeLabel 挙動（resource が exposeLabel を持てば公開）。
- ブリッジが全 policy を畳んで `Predicate<LockableResource>` を生成するヘルパー。
- docs に「ここに公開制限/allowlist/認可を差し込む」と明記済み（設計 §4）。

#### 完了条件
- [ ] 実装完了 / [ ] `mvn test` 緑 / [ ] コミット

### Step 3: 共有 buildLockEnvVars（local/remote 共通）

- `proceed()` 内のインライン env var 生成を `buildLockEnvVars(variable, name→properties)` に抽出。
- local `proceed()` は抽出関数を呼ぶよう変更（挙動不変）。
- server acquire 時に `name→properties` で呼び、`lockEnvVars`（プロパティ含む）を返す。
- remote の `generateLockEnvVars`（部分実装）を撤去。

#### 完了条件
- [ ] 実装完了 / [ ] `mvn test` 緑 / [ ] コミット

### Step 4: ブリッジ acquire/queue を canonical へ委譲（再実装撤去）

- `RemoteLockRequest → List<LockableResourcesStruct>` アダプタ（`getResources()` 鏡写し）。
- 即時取得・キュー昇格とも `getAvailableResources(structs, strategy, predicate)` 経由に。
- `lockForRemote(available, lockId)` で確定、`buildLockEnvVars` で env var、TailCall は維持。
- 撤去: `resolveRemoteAvailable` / `claimSelector` / `validateRemoteSelectors` 群 / `generateLockEnvVars`。
- 未知ラベル/未存在は terminal をやめ QUEUED（local 等価、§7）。明示拒否は policy の admission に整理。
- RemoteApiV1Action: 解決系の前処理を撤去し、policy admission ＋ canonical 委譲に寄せる。

#### 完了条件
- [ ] 実装完了 / [ ] `mvn test` 緑 / [ ] コミット

### Step 5: テスト整備 + フル回帰

- ユニット: プロパティ env var の remote 透過 / selectStrategy(RANDOM) の remote 反映 / ephemeral 透過
  （allowEphemeralResources）/ ExtensionPoint policy（既定 exposeLabel + `@TestExtension` 差し替え）/
  既存 C-1/C-2/F-1 の回帰維持。M1C の terminal 前提テストは QUEUED 前提へ改訂。
- `stabilize-build.sh`（worktree）でフル `mvn test`。

#### 完了条件
- [ ] テスト整備 / [ ] `mvn test` 件数・0 失敗を記録 / [ ] コミット

### Step 6: E2E メンテ + 全件完走

- 既存シナリオを M1D 挙動に追従（exposeLabel が filter 層へ移ったことの影響を確認）。
- 追加候補: プロパティ env var の remote 伝搬 / RANDOM strategy / ephemeral remote（policy 次第）。
- `run-e2e.sh --clean-start` 全件 PASS、レポート保存。

#### 完了条件
- [ ] E2E メンテ / [ ] 全件 PASS 記録 / [ ] notes コミット

---

## テスト実行方針（M1D）

1. フル回帰は `stabilize-build.sh`（worktree モード）。
2. E2E は最新 `run-e2e.sh` の**全件**を `--clean-start` で完走しレポート保存（サイクル完了条件）。

## 更新履歴

- 2026-06-13: 初版作成。M1D（真のブリッジ化）の実装ステップ計画。
