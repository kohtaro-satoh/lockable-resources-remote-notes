# M1F 結果（Remote lock - Phase 1 / M1F）

> **対象 plugin ブランチ:** `feature/1025-remote-lockable-resources-p1-m1f`（HEAD `6319f12`）
> **設計:** `LRR_DESIGN_P1_M1F.md` / **手順:** `LRR_IMPLEMENTATION_STEPS_P1_M1F.md` / **レビュー:** `LRR_REVIEW_P1_M1E.md`
> **位置づけ:** M1E レビュー指摘の選別対応 — ネットワークブリッジのトランスポート/境界層の堅牢化（L-b/L-c/L-d）のみ実施。
>   lock() ロジック由来の穴（M1E-1 ほか）は観点により意図的に残置し、設計 §4 に明文化。

---

## 1. 達成したこと

`LRR_REVIEW_P1_M1E.md` の指摘を、ユーザー確定の観点「**lock() 既存ロジックに乗り、ネットワークブリッジ由来以外の
remote 独自判定を増やさない**」で選別。**ブリッジ堅牢化 3 点のみ実施**し、lock() ロジック由来の穴は残置（再議論防止の明文化）。

| 指摘 | 区分 | M1F での対応 |
|---|---|---|
| **L-b** url スキーム未検証 | ブリッジ堅牢化 | ✅ 実施。`RemoteConnection.validate()` が非 http(s)（`file:`/`ftp:`/スキーム無し）を `IllegalArgumentException` で拒否。`DescriptorImpl` を `@Extension` 化し `doCheckUrl` で UI 即時検証。判定は共有 `isHttpUrl` |
| **L-c** POST ボディ上限なし | ブリッジ堅牢化 | ✅ 実施。`parseJsonBody` に文字数上限 `MAX_BODY_CHARS=1 MiB`。超過で `PayloadTooLargeException`→ **413 `PAYLOAD_TOO_LARGE`**（既存 `INVALID_JSON` 400 は維持） |
| **L-d** FAILED→202 フォールスルー | ブリッジ堅牢化 | ✅ 実施。POST `/acquire` の `FAILED` は `UNKNOWN_*`→404、それ以外→**400 `ACQUIRE_FAILED`**。202 成功フォールスルーを封鎖（防御的） |
| **M1E-1** 昇格経路 `fromNames(create=true)` の ephemeral 再生成 | lock() ロジック由来 | ⏸ **意図的に残置**。`create=true` は canonical の name 解決そのもの。remote だけ `create=false` にするのはブリッジ由来でない remote 独自判定の追加＝観点に反する。狭く・非 fail-open・孤児 1 個収束のため受容。設計 §4 に明文化 |
| **M1E-2** resource+label 同時指定 | local 由来・非 fail-open | ⏸ 残置（candidateFilter が公開強制でバイパス無し） |
| **M1E-3** lease 所有者非検証 | 設計上 | ⏸ 残置（多テナント時 P1+） |
| **L-a** setRemotes eager save | 無害 | ⏸ 残置（`configure()` の BulkChange でアトミック） |
| **L-e** getExposeLabels 毎回 split | 性能のみ | ⏸ 残置 |

> admission（unknown→404）は remote 終端ポリシーとして**維持**。実施 3 点は HTTP 境界/トランスポートに閉じ、
> lock() ロジック・canonical 委譲・透過等価の意味論には無干渉（透過等価の挙動は M1E から不変）。

## 2. 設計の要点（残置懸念の確定）

- **M1E-1 は「直さない」をユーザーと確定**（2026-06-14）。理由は「lock() 既存ロジックに乗る」観点。`fromNames(create=true)` は
  local の on-demand ephemeral 機能と同一コードパスで、remote だけ別扱いにするのは観点に反する。発火条件は狭く（exposed・busy・
  QUEUED 中に admin 削除）、fail-open ではなく、孤児は名前あたり 1 個に収束。設計 §4 に「将来この観点を変える時のみ canonical
  シームに `create` フラグを通す案を再検討」と記録。
- M1E-2 / M1E-3 / L-a / L-e も残置理由を設計 §2・§4 に明文化（再議論防止）。

## 3. 検証結果

| 観点 | 結果 | 証跡 |
|---|---|---|
| ユニット（worktree フル） | **mvn test 382 件 / 0 失敗 / 0 エラー / 1 skip**（M1E 378 + 新規 4） | `dev/reports/20260614104134-mvn-test.log` |
| E2E（`--clean-start` 全件） | **20 シナリオ 20/20 PASS**（既存回帰維持。新規シナリオなし） | `dev/reports/20260614105955-e2e-test.md` |
| 新規ユニット | L-b: https 受理・file/ftp/スキーム無し拒否・`doCheckUrl`（`RemoteConnectionTest` 3 件）／ L-c: >1 MiB ボディ→413（`RemoteApiV1ActionTest` 1 件） | 同上 |

> M1F は HTTP 境界/トランスポートのみの変更で lock() 挙動・透過等価・公開意味論を変えないため、**新規 E2E シナリオは追加せず
> 既存 20/20 の回帰維持で十分**とした（L-b/L-c/L-d はユニットで直接カバー）。L-d の非 `UNKNOWN_*` 分岐は現状到達不能（境界の
> `MISSING_TARGET` チェックで先に弾かれる）防御的変更で、既存 `UNKNOWN_RESOURCE`/`UNKNOWN_LABEL` の 404 テストが一般化分岐を回帰カバー。

## 4. 状態

- plugin `feature/...-m1f` HEAD `6319f12`（クリーン）。**push/PR は未**（完璧化後・ユーザー指示待ち）。
- ドキュメント（DESIGN/IMPLEMENTATION_STEPS/本書、j+e）整備済み。`LRR_REVIEW_P1_M1E`（j+e）に M1F 対応バナー追記済み。
  README 索引・Status・ブランチ一覧更新済み。
- レポートは最新ひとつずつに整理（`20260614104134-mvn-test.log` / `20260614105955-e2e-test.md`）。

## 更新履歴

- 2026-06-14: 初版作成。M1F（ブリッジ堅牢化 L-b/L-c/L-d）の結果サマリ。mvn 382 / E2E 20/20。M1E-1 は意図的残置。
