# M1C 結果（Remote lock - Phase 1 / M1C）

> **対象 plugin ブランチ:** `feature/1025-remote-lockable-resources-p1-m1c`（HEAD `2d88834`）
> **設計:** `LRR_DESIGN_P1_M1C.md` / **手順:** `LRR_IMPLEMENTATION_STEPS_P1_M1C.md` / **元レビュー:** `LRR_REVIEW_P1_M1B.md`
> **位置づけ:** M1B 完了時レビューで発覚した新規問題（C-1/C-2/M-2/M-3）＋追加検出（F-1）の解消サイクルの結果サマリ。

---

## 1. 解消した指摘

| 指摘 | 種別 | 解 | plugin |
|---|---|---|---|
| **C-1** ラベル指定 extra のサイレント欠落 | Critical（fail-open 排他侵害） | 統一セレクタリゾルバで label-extra を完全実装（アトミック・exposeLabel・quantity・重複排除） | `3f1e78a` |
| **C-2** `release()` の QUEUED 昇格競合（孤児ロック） | 並行性 | `release()` を `syncResources` 下で直列化し QUEUED を terminal 化してから unqueue | `3f1e78a` |
| **M-2** extra-only の client/server 非対称 | 軽微 | server が extra-only を受理（local lock() 等価） | `5296b50` |
| **M-3** `consecutivePollFailures` が onResume 未リセット | 軽微 | onResume で 0 リセット | `5296b50` |
| **F-1** label の quantity 未指定 = 全部（"0 = all"） | 透過等価（追加検出） | `claimSelector` でプール全件取得＋POST 既定 1→0 | `2d88834` |
| M-1 onResume の displayTarget 劣化 | 軽微（表示のみ） | **後送り**（リソース名の永続化が必要） | — |

**F-1 の経緯（重要）:** ユーザー指摘「extra が M1A/M1B/M1C と未解決」を機に発覚。`lock(label: X)`（quantity 未指定）は
local では "0 = all"（全マッチ）をロックするのに、remote は M1A 以降 1 個に倒していた。**根本原因はテストが毎回
`quantity: 1/2` を明示し、最頻ケース（既定=all）を一度も突かなかったこと**（C-1/C-2 と同型の検証層の穴）。
教訓は「透過等価テストは既定値/未指定/0/空を必ず突く」。

## 2. 検証結果

| 観点 | 結果 | 証跡 |
|---|---|---|
| ユニット（worktree フル） | **mvn test 375 件 / 0 失敗 / 1 skip**（既知 JENKINS-40787） | `dev/reports/20260612232116-mvn-test.log` |
| E2E（`--clean-start` 全件） | **18 シナリオ 18/18 PASS** | `dev/reports/20260612233944-e2e-test.md` |
| 新規 E2E | S14 `extra-label-resources`（C-1）/ S15 `label-quantity-all`（F-1） | 同上 |
| 新規ユニット | RemoteLockManagerTest 32 / RemoteApiV1ActionTest 11（+合計 15） | — |

S14 CP02: main + label-extra が**同一 lease** でロック（C-1 実証）。
S15 CP02: `lock(label)` quantity 無しが**3 プール全部を単一 lease**でロック（F-1 実証）。

## 3. M1C で残った「真の非等価」— M1D の入口

M1C は**機能別に**潰したが、残件もまた機能別に残った。これは**サーバーが lock() の解決・env var 生成を
再実装している**アーキテクチャに起因する（各意味論次元が独立にドリフトしうる）。M1C 時点の残非等価:

| 残件 | 内容 |
|---|---|
| リソースプロパティ env var | local は `VAR0_<PROP>` まで注入、remote は未対応 |
| ephemeral 自動作成 | local は未存在名を作成、remote は `UNKNOWN_RESOURCE` |
| resourceSelectStrategy | local は SEQUENTIAL/RANDOM、remote は貪欲 SEQUENTIAL のみ |

→ **M1D（真のブリッジ化）** で、解決を canonical `getAvailableResources` に委譲し env var 生成を local と共有
することで、これらを**個別実装せずまとめて透過化**する（`LRR_DESIGN_P1_M1D.md`）。

## 4. 状態

- plugin `feature/...-m1c` HEAD `2d88834`（クリーン）。**push/PR は未**（完璧化後・ユーザー指示待ち）。
- ドキュメント（DESIGN/IMPLEMENTATION_STEPS、j+e）整備済み。レビュー解消表（C-1/C-2/M-2/M-3/F-1）更新済み。

## 更新履歴

- 2026-06-13: 初版作成。M1C（C-1/C-2/M-2/M-3 + F-1）の結果サマリ。M1D への引き継ぎを明記。
