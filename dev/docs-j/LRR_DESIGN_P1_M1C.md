# Remote Lockable Resources 仕様書（Phase 1 / M1C）

> **出典:** [jenkinsci/lockable-resources-plugin #1025](https://github.com/jenkinsci/lockable-resources-plugin/issues/1025)
> **前提文書:** `LRR_DESIGN_P1_M1B.md`（M1B 仕様）。本書は M1B からの差分＋現行真実を定義する。
> **背景:** `LRR_REVIEW_P1_M1B.md`（2026-06-12 M1B 完了時レビュー）で発覚した新規問題への対応
> **対象スコープ:** Phase 1 M1C（M1B 残不整合の解消）

---

## 目次

1. [M1C の位置づけ](#1-m1c-の位置づけ)
2. [意思決定の記録](#2-意思決定の記録)
3. [統一セレクタリゾルバ（中核）](#3-統一セレクタリゾルバ中核)
4. [release の直列化（孤児ロック排除）](#4-release-の直列化孤児ロック排除)
5. [extra-only リクエストの受理](#5-extra-only-リクエストの受理)
6. [onResume の poll 予算リセット](#6-onresume-の-poll-予算リセット)
7. [スコープ整理（M1C の含む/含まない）](#7-スコープ整理m1c-の含む含まない)

---

## 1. M1C の位置づけ

M1B 完了後に改めて全体レビュー（`LRR_REVIEW_P1_M1B.md`）を実施したところ、M1B が中核ゴールに
掲げた「extra の完全実装」と「透過等価」を、自ら破る不整合が残っていた。M1C はこれらを
M1B と同じ思想 —**「安全に倒す」ではなく「透過等価に全振り」**— で解消する。

| レビュー指摘 | 重さ | M1C の解 |
|---|---|---|
| C-1 ラベル指定 extra のサイレント欠落 | Critical（fail-open） | 統一セレクタリゾルバで完全実装（§3） |
| C-2 `release()` の QUEUED 昇格競合（孤児ロック） | 並行性 | `syncResources` 下で terminal 化してから unqueue（§4） |
| M-2 extra-only の client/server 非対称 | 軽微 | server が extra-only を受理（§5） |
| M-3 `consecutivePollFailures` が onResume でリセットされない | 軽微 | onResume で 0 リセット（§6） |
| M-1 onResume の displayTarget 劣化 | 軽微（表示のみ） | **後送り**（リソース名の永続化が必要。§7） |

---

## 2. 意思決定の記録

2026-06-12 のレビュー後協議で確定（`AskUserQuestion`）:

| # | 論点 | 決定 |
|---|---|---|
| C-1 | ラベル extra | **(a) 完全実装する**（400 拒否ではなく）。M1B 設計書 §4 が「サポート」と記載済みであり、透過等価の原則とも整合する |
| C-2 | release 競合 | `release()` を `syncResources` 下に入れ、QUEUED を terminal 化（`errorCode: RELEASED`）してから unqueue。QUEUE_EXPIRED 側（M1B §6）と同じ直列化を release にも適用 |
| 軽微 | 同梱範囲 | **M-2・M-3 を同梱**。M-1 は表示のみ・機能影響なしのため後送り |

---

## 3. 統一セレクタリゾルバ（中核）

### M1B の問題構造

M1B の取得ロジックは、即時取得（`RemoteLockManager.tryAcquireRecord`）とキュー昇格時の空き判定
（`LockableResourcesManager.checkRemoteResourcesAvailable`）で**二重に書かれ**、どちらも extra を
`e.getResource()` だけで集計していた。結果、**label 指定の extra エントリは両経路で黙って捨てられ**、
main だけロックして body が走る fail-open が生じた。さらに、空 exposeLabel 時の label 解釈が
即時経路（「公開なし → UNKNOWN_LABEL」）とキュー経路（「フィルタせず全許可」）で食い違っていた。

### M1C 構造：セレクタの一本化

取得対象を「**セレクタの集合**」として捉え直す。セレクタは次のいずれか:

- **named** … `resource` 名で 1 個指定
- **label** … `label` + `quantity` で公開リソースから N 個

main（`resource` か `label`）と各 `extra` エントリは、どれも 1 セレクタである。
これを `LockableResourcesManager` の 2 メソッドに集約し、即時取得とキュー昇格の**両方が同じ
ロジックを通る**ようにする（single source of truth）。

```text
validateRemoteSelectors(req) -> errorCode | null      // 構造妥当性（存在・公開）
    named : fromName(name) != null（公開は POST 境界で担保）
    label : exposeLabel と一致する候補が 1 件以上（空 exposeLabel は opt-in＝公開なし）
    → 失敗時 UNKNOWN_RESOURCE / UNKNOWN_LABEL（terminal FAILED）

resolveRemoteAvailable(req) -> List<String> | null    // 現時点の空き解決
    各セレクタを「空き かつ 未claim かつ（label なら公開）」リソースに割り当て
    label セレクタは quantity 個を貪欲取得（SEQUENTIAL）
    claimedSet で**セレクタ間の重複取得を排除**（main label x1 + extra label x1 → 別個 2 個）
    全セレクタ充足 → 全名を返す（アトミック）。1 つでも不足 → null（QUEUED/SKIPPED）
```

- 即時取得: `validateRemoteSelectors`（terminal 判定）→ `resolveRemoteAvailable`
  （非 null なら `lockForRemote` で一括ロック＋ACQUIRED、null なら QUEUED か SKIPPED）。
- キュー昇格: `getNextRemoteEntry` が各 QUEUED エントリに `resolveRemoteAvailable` を適用し、
  充足した最初のもの（priority 降順）を昇格。

### 等価性・アトミック性

- **label-extra が local `lock()` と等価に**ロックされる（M1B §4 の記載どおりに実装が追いついた）。
- main + 全 extra は**全部まとめて取得できる時だけ** ACQUIRED（部分ロックは発生しない）。
- 空 exposeLabel 時の label 解釈を**即時/キューで統一**（どちらも「公開なし＝UNKNOWN_LABEL」）。
- `quantity` と重複排除により、同一ラベルを複数セレクタが要求しても**別個のリソース**を割り当てる。

---

## 4. release の直列化（孤児ロック排除）

### M1B の競合（C-2）

`RemoteLockManager.release()` は `records.remove()` 後、**ロックを取らずに**状態を読んで分岐していた。
QUEUED レコードの release と、別スレッドの昇格（`proceedRemoteEntry`、`syncResources` 下、
`entry.isValid()==QUEUED` を見る）が交差すると、リソースが remote ロックされたまま record が
map から消える孤児ロックが生じた（再起動まで回復不能）。これは M1A 4-5（release と tick の競合）と同型。

### M1C の解

`release()` 全体を `synchronized (LockableResourcesManager.syncResources)` で囲み、QUEUED 分岐では
**先に `record.markFailed("RELEASED")`（terminal 化）してから `unqueueRemote`** する。terminal 化すれば
`getNextRemoteEntry` の `entry.isValid()` が false になり昇格が構造的に排除される。

- `syncResources` は再入可のため、`unlockRemoteResources` のネスト呼び出しは問題ない。
- ただし `unlockRemoteResources` / `scheduleQueueMaintenance`（Jenkins Queue ロックに触れる）は
  **`syncResources` の外**で呼ぶ（解放対象名だけをロック下で確定し、解放はロック解除後）。
- QUEUE_EXPIRED 側（M1B §6）は既に同型の再チェックを持っており、release 側もこれに揃えた。

---

## 5. extra-only リクエストの受理

local `lock(extra: [...])`（main の resource/label なし）は妥当である
（`LockStepResource.validate` は `hasExtra` を no-target ルールの例外にしている）。
M1B では client がこれを許容する一方、server の `POST /acquire` が `400 MISSING_TARGET` を返す
非対称があった。M1C では **server も extra-only を受理**する（`resource`/`label`/`extra` のいずれか
非空であればよい）。リゾルバは main セレクタ不在を no-op として扱い、extra セレクタ群を解決する。

---

## 6. onResume の poll 予算リセット

`consecutivePollFailures` は永続化されるため、再起動前に積み上がったカウンタが onResume 後に
引き継がれ、再起動後の poll リトライ予算（~60 秒）が目減りし得た。M1C では onResume の
ポーリング再開時に **`consecutivePollFailures = 0`** にリセットする（再起動は poll 失敗ではない）。

---

## 7. スコープ整理（M1C の含む/含まない）

### 含む（M1C）

| 項目 | 内容 |
|---|---|
| label-extra の完全実装 | 統一セレクタリゾルバ（§3）。即時/キューを一本化、アトミック、重複排除、exposeLabel |
| 空 exposeLabel の挙動統一 | 即時/キューとも「公開なし＝UNKNOWN_LABEL」 |
| release の直列化 | `syncResources` 下で QUEUED terminal 化 → unqueue（§4） |
| extra-only 受理 | server が main なし＋extra ありを受理（§5） |
| poll 予算リセット | onResume で `consecutivePollFailures=0`（§6） |

### 含まない（M1C スコープ外）

| 項目 | 備考 |
|---|---|
| M-1 onResume の displayTarget 劣化 | 表示のみ・機能影響なし。リソース名の永続化が必要なため後送り |
| リソースプロパティ env var の remote 伝搬 | M1B 同様、非対応のまま |
| `resourceSelectStrategy` の厳密実装 | 貪欲 SEQUENTIAL のまま（M1B 同様） |

---

## 更新履歴

- 2026-06-12: 初版作成。M1B 完了時レビュー（`LRR_REVIEW_P1_M1B.md`）の C-1/C-2/M-2/M-3 を
  解消する M1C（透過等価の徹底）を定義。M-1 は後送り。
