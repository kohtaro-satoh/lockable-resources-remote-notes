# Remote LR 開発活動 レビュー（Phase 1 / M1E 完了時点・master 全面差分）

> **レビュー日:** 2026-06-14
> **対象 plugin 差分:** `master`（`863ea4d`）..`feature/1025-remote-lockable-resources-p1-m1e`（HEAD: `5d956de`）の**全面差分**
>   （43 ファイル / +5256・-43。mvn 378 件成功・E2E 20/20）
> **対象ドキュメント:** `dev/docs-j/`（LRR_DESIGN_P1_M1E / LRR_IMPLEMENTATION_STEPS_P1_M1E / LRR_RESULT_P1_M1E / E2E_TEST_SPECIFICATION）、
>   `LRR_REVIEW_P1_M1D.md`（前サイクルレビュー）、`memo.txt`（ユーザー確認事項）
> **観点:** 元構想（[#1025](https://github.com/jenkinsci/lockable-resources-plugin/issues/1025)）／M1E の中核目標「M1D レビュー H-1・M-2 の解消＋意図的単純化」の達成度／
>   exposeLabel 集合（OR）公開と canonical 委譲の整合／**M1D で指摘した H-1（ephemeral 量産）クラスが完全に閉じたか**／新規リグレッションの有無
> **方法:** M1A/M1B/M1D と同じ方法論。フルビルド（~17 分）は再実行せず、`5d956de` の全面差分とコードを静的精読。
>   テスト件数（378）/ E2E（20/20）は記録レポートを信頼するが実在を確認した（`dev/reports/20260614002216-mvn-test.log` =
>   `Tests run: 378, Failures: 0, Errors: 0, Skipped: 1`、`dev/reports/20260614004015-e2e-test.md`、作業ツリーは `5d956de` でクリーン）。

---

## M1F での対応（2026-06-14 更新）

本レビューの指摘を、ユーザー確定の観点「**lock() 既存ロジックに乗り、ネットワークブリッジ由来以外の remote 独自判定を増やさない**」で
選別し、M1F サイクルを実施（`LRR_DESIGN_P1_M1F.md` / `LRR_IMPLEMENTATION_STEPS_P1_M1F.md`、plugin ブランチ
`feature/1025-remote-lockable-resources-p1-m1f`、m1e ベース）。

| 指摘 | 区分 | M1F 対応 |
|---|---|---|
| **M1E-1**（昇格経路 `fromNames(create=true)` の ephemeral 再生成） | lock() ロジック由来 | **意図的に残置**。`create=true` は canonical の name 解決そのもので、remote だけ `create=false` にするのは「ブリッジ由来でない remote 独自判定の追加」＝観点に反する。狭く・非 fail-open・孤児 1 個収束のため受容。設計 §4 に明文化（再議論防止） |
| **M1E-2**（resource+label 同時指定のセレクタ不整合） | local 由来・非 fail-open | **残置**（candidateFilter が公開強制でバイパス無し。remote 独自判定を足さない） |
| **M1E-3**（lease 操作の所有者非検証） | 設計上 | **残置**（多テナント時 P1+） |
| **L-b**（url スキーム未検証） | ブリッジ堅牢化 | **実施**: `RemoteConnection.validate()` で非 http(s) 拒否＋`doCheckUrl` |
| **L-c**（POST ボディ上限なし） | ブリッジ堅牢化 | **実施**: 1 MiB 上限→413 `PAYLOAD_TOO_LARGE` |
| **L-d**（FAILED→202 フォールスルー） | ブリッジ堅牢化 | **実施**: `FAILED`（非 `UNKNOWN_*`）→400 `ACQUIRE_FAILED` |
| **L-a**（setRemotes eager save） | 無害（BulkChange でアトミック） | **残置** |
| **L-e**（getExposeLabels 毎回 split） | 性能のみ | **残置** |

> admission（unknown→404）は remote 終端ポリシーとして**維持**（撤去しない）。実施 3 点はいずれも HTTP 境界/トランスポートに
> 閉じ、lock() ロジック・canonical 委譲・透過等価には無干渉。**M1E-1 は「直さない」ことをユーザーと確定**（設計 §4）。

---

## 目次

1. [総評](#1-総評)
2. [M1E で良くなった点](#2-m1e-で良くなった点)
3. [指摘事項](#3-指摘事項)
   - [M1E-1（Low–Medium）昇格経路に admission 再検証が無く、QUEUED 中に削除された名前指定リソースが ephemeral として再生成され孤児化する](#m1e-1)
   - [M1E-2（Low）resource と label を同時指定した時、admission は resource を見るが解決は label を使う（セレクタ優先順位の不整合）](#m1e-2)
   - [M1E-3（Low / 設計上）lease 操作は REMOTE 権限のみで認可し、lockId 所有者を検証しない](#m1e-3)
4. [軽微 / nits](#4-軽微--nits)
5. [memo.txt のユーザー確認事項への回答（透過等価の確定）](#5-memotxt-のユーザー確認事項への回答透過等価の確定)
6. [テスト / 検証層の評価](#6-テスト--検証層の評価)
7. [推奨アクション（優先順）](#7-推奨アクション優先順)

---

## 1. 総評

**M1E はサイクルの宣言した目的（M1D レビュー H-1・M-2 の解消と意図的単純化）を、設計どおり高品質に達成している。**
M1D レビューで「**透過等価を名乗るには塞ぐべき一点**」とした H-1（未存在/未公開名で ephemeral を量産・永続化）は、

- **解決経路から `createResource` を撤去**（`addRemoteStruct` は検証済みの名前だけを `LockableResourcesStruct` に渡す）、
- **`enqueue` の `syncResources` 区間先頭に admission（`validateRemoteSelectors`）を追加**し、未存在/未公開を一律 404
  （`UNKNOWN_RESOURCE` / `UNKNOWN_LABEL`）で**即時拒否**、

の 2 段で、**即時取得経路では完全に閉じている**（H-1 直撃テスト `enqueueRejectsUnknownResourceAndCreatesNothing` が「FAILED かつ `fromName` が null」を実証）。
M-2（公開判定 ExtensionPoint の AND 固定・差し替え不可）も、`RemoteResourceExposurePolicy` / `ExposeLabelPolicy` の SPI を撤去し
**exposeLabel 単一概念**へ割り切ることで解消。あわせて exposeLabel を**空白区切りのラベル集合（OR 公開）**に拡張した設計は、
「要求ラベル AND（exposeLabel のいずれか）」を **canonical の generic `Predicate` シームに閉じ込め、local の単一ラベル一致を一切改修しない**
（§4-3）という分離が正しく実装されており、local 無改修の証跡（375→378 緑、local 系の挙動不変）も保たれている。
M1D の中核成果（canonical 委譲・共有 env var・並行性の単一 `syncResources` 区間）は後退なく維持され、M1C の再実装
（`claimSelector` 等）は復活していない。**「M1C の admission（404）＋ M1D の正準解決」の合成**という設計意図に忠実である。

**ただし「H-1 クラスが完全に閉じた」と言い切るには、もう一経路だけ残る（M1E-1）。**
admission は **`enqueue` の入口（即時取得時）だけ**で行われ、QUEUED → 昇格の経路（`getNextRemoteEntry` → `availableForRemote`）では
**再検証されない**。昇格時の解決は canonical の name 分岐 `fromNames(..., /*create*/ true)` を通るため、
**QUEUED 中に admin が対象リソースを削除すると、昇格スキャンが当該名を ephemeral として再生成**してしまう（直後に
exposeLabel フィルタが弾くので**ロックはされず孤児として永続**する）。即時取得経路で塞いだ H-1 と**同じクラス**の残渣であり、
発火条件は狭い（exposed かつ busy で QUEUED 中のリソースを admin が削除）・影響は限定的（名前あたり孤児 1 個・上限なしではない）だが、
**設計書 §3-4 の「昇格時は candidateFilter が弾き続ける」という記述は、その前段で `fromNames(create=true)` が実体を作る副作用を見落としている。**

結論として、**M1E は設計・実装・テストの本筋で成功**しており、即時取得という主経路では H-1 は解決済み。
残るのは M1E-1（昇格経路の admission 再検証欠落）一点で、これは PR 前に塞ぐか、少なくとも既知の限界として明文化すべきである。
それ以外の指摘（M1E-2 / M1E-3 / nits）はいずれも fail-open（排他保証の侵害）ではなく、優先度は低い。

---

## 2. M1E で良くなった点

- **H-1 を即時取得経路で構造的に閉じた。** `createResource` の撤去＋ admission の二段で、
  「remote 要求がサーバー上に新規 ephemeral を作る」経路を入口で断った。`addRemoteStruct` は
  `// No ephemeral creation here … (H-1, M1E)` と意図をコメント化し、`toRemoteStructs` の Javadoc も
  「resolved by name only (no ephemeral creation)」と明記。**検証は `enqueue` 内（単一ソース・正しい `syncResources` ロック下）**で、
  HTTP 404 マップだけを境界（`RemoteApiV1Action`）が担う層化は、M1C の「境界で別途 `fromName` チェック」の二重化を避けており適切。
- **公開フィルタを exposeLabel 単一概念へ単純化。** SPI（`ExtensionPoint`・AND 畳み込み・「未登録なら全公開」デッドパス）を全撤去。
  `isExposed(r) = !disjoint(r.labels, exposeLabels)` という 1 行述語に集約され、M-2 の「差し替え不可なのに差し替え可能と書いてある」
  という文書・実装の乖離が**概念ごと消えた**（YAGNI の正しい適用）。
- **exposeLabel の集合化（OR 公開）を canonical へ漏らさず実装。** `getExposeLabels()` は `split("\\s+")` で集合化（`getExposeLabel()` は不変・後方互換）。
  「要求ラベル AND exposeLabel(集合)」は **remote 層の `availableForRemote` が組む `r -> isExposed(r, exposeLabels)` predicate に 100% 閉じ**、
  canonical（`getAvailableResources` / `getFreeResourcesWithLabel`）は generic な `Predicate` を 1 つ受けるだけで exposeLabel を知らない。
  フィルタは**個数選択の前**（`candidates.removeIf(...)`）に効くので `quantity 0 = 可視マッチ全部` が正しく成立。
  local 呼び出しは `r -> true` を渡すため**挙動完全不変**。テスト `multipleExposeLabelsAreOredForExposure`（`"gpu license"` で
  gpu-1/lic-1 は ACQUIRED、other-1 は `UNKNOWN_RESOURCE`）が OR 公開を直接ピン留め。
- **L-3 解消（env var 1 本化）。** `RemoteQueueEntry.onAcquired` がインライン構築をやめ、即時取得と同じ
  `LockableResourcesManager.remoteLockEnvVars(variable, resources)` 経由に統一。`buildLockEnvVars` を即時/昇格/local が共有し、
  `VAR0_<PROP>` まで透過。
- **L-4 解消（不正 selectStrategy）。** POST 境界で未知 strategy を **400 `INVALID_SELECT_STRATEGY`** で弾く（local の「不正値は拒否」と整合）。
  `parseSelectStrategy` の寛容フォールバックは安全網として保持。テスト `RemoteApiV1ActionTest` がカバー。
- **意図的非等価の明文化。** 「未存在/未公開 → 即時 404」（local は QUEUED で待つ）を**設計判断として確定・再議論しない**と
  設計書 §6 に記録。これは M1A 以来の「『作ったものが宣言どおりか』の検証層の穴」を、admission の単一ソース化で塞いだ姿でもある。
- **検証証跡の実在を確認。** mvn 378/0 失敗（M1D の 375 から +3、H-1 回帰・未公開拒否・OR 公開・selectStrategy・昇格 env var を追加）、
  E2E 20/20（S17「未知 acquire → 404 ＋ ephemeral 非作成 `NOT_CREATED=true`」を追加）。レポートは現存、ツリーは `5d956de` でクリーン。

---

## 3. 指摘事項

<a id="m1e-1"></a>
### M1E-1【Low–Medium／堅牢性 — H-1 クラスの昇格経路残渣】QUEUED 中に削除された名前指定リソースが昇格スキャンで ephemeral 再生成・孤児化する

**症状:** exposed かつ現在 busy な名前指定リソース R に対する remote acquire は admission を通って **QUEUED** になる（正しい）。
この QUEUED 中に admin が R を構成から削除すると、その後の昇格スキャン（`getNextRemoteEntry`、1 秒 tick）が
**R を `LockableResource` として再生成し、`config` に永続化**する。再生成された R は exposeLabel を持たないため直後の
candidateFilter（`isExposed`）に弾かれ `available=null` → QUEUED のまま据え置かれるが、**作られた ephemeral は誰にもロックされず回収されない**。

**経路:**

1. admission（`validateRemoteSelectors`）は **`enqueue` の入口でのみ**実行される（`RemoteLockManager.enqueue`、`syncResources` 区間先頭）。
   QUEUED 後の昇格には**再検証が無い**。
2. 昇格は `proceedNextContext` → `getNextRemoteEntry` → `availableForRemote(entry.getStructs(), …)` →
   `getAvailableResources(structs, …, candidateFilter)`。name 指定の struct は enqueue 時に
   `new LockableResourcesStruct(names, label, quantity)` で構築され、`required` に**解決済み `LockableResource` を保持**する
   （`LockableResourcesStruct.java:90-99`、`fromName` で構築時に解決）。
3. R を削除すると、`struct.required` は**マネージャから外れた孤児 `LockableResource`** を握り続ける。
   `getAvailableResources` の name 分岐は `available = fromNames(getResourcesNames(required), /*create*/ true)`
   （`LockableResourcesManager.java:1738` 付近）を呼ぶため、**存在しなくなった名前を `create=true` で再生成**（`allowEphemeralResources` 既定 `true`）。
4. 続く `available.stream().anyMatch(r -> !candidateFilter.test(r))` が再生成された無ラベル ephemeral を弾き `available=null` → QUEUED 据え置き。
   **ephemeral は残存**（次 tick 以降は既存ヒットで再生成されないため孤児 1 個に収束。`QUEUE_EXPIRED` 後も config に残り、再起動耐性あり）。

**なぜ指摘するか:**

- **M1E が「閉じた」と宣言した H-1 と同じクラス**（公開もロックもされない ephemeral がサーバーに永続化）が、即時取得経路では塞がれた一方、
  **昇格経路に残っている**。即時経路は admission と同一 `syncResources` 内で存在保証されるため安全だが、昇格経路は時間差で admin 削除が割り込み得る。
- **設計書 §3-4 の記述と実態がずれる。** §3-4 は「昇格時の candidateFilter が弾き続け最終的に `QUEUE_EXPIRED` に縮退する」とするが、
  *弾く前に* `fromNames(create=true)` が実体を作る副作用に触れていない。
- ただし **fail-open ではない**（誤ったロックは一切付与されない）、発火条件は狭く（exposed・busy・QUEUED 中の admin 削除）、孤児は名前あたり 1 個に収束する。
  よって重大度は **Low–Medium**（H-1 本体の Medium より低い）。

**修正方針（いずれか。安価なのは (a)）:**

- **(a) 昇格時に admission を再検証する（推奨）。** `getNextRemoteEntry` が解決を試みる前に
  `validateRemoteSelectors(entry.getLockRequest())` を再実行し、`!= null` なら当該 entry を `markFailed`（例: 既存の `QUEUE_EXPIRED`
  もしくは新コード `TARGET_GONE`）して `toRemove` に積む。再生成の前段で弾けるので ephemeral を作らず、§3-4 の記述とも一致する。
- **(b) remote の name 解決を `create=false` で行うシームを足す。** canonical の name 分岐が `create` を選べるよう
  もう一段オーバーロードを切り、remote からは `false` を渡す。ただし (a) より変更面が広い。
- **回帰テスト（L 級）を併せて追加:** 「name 指定で QUEUED → admin が当該リソース削除 → 昇格 tick 後に当該名の `fromName` が null のまま
  （再生成されていない）」をアサート。現状の昇格系テストは削除割り込みを突いていない。

<a id="m1e-2"></a>
### M1E-2【Low／整合性 — fail-open ではない】resource と label を同時指定した時、admission は resource を、解決は label を見る

`validateSelector` は **resource を先に判定**し、resource があれば label を見ない（`resource != null` 分岐で return）。
一方 `getAvailableResources` は **label があれば label 分岐**を優先し、name を無視する（canonical 既存挙動）。
したがって `{resource:"<exposed>", label:"<some>"}` のような両指定要求では、**admission は resource の公開で通過するが、実際の解決は label で行われる**。

- **排他・公開の安全性は保たれる。** 解決の label 分岐も candidateFilter（`isExposed`）を通すため、**未公開リソースがロックされることはない**（バイパス不成立）。
- ただし「admission が検証したセレクタ」と「解決が使うセレクタ」が食い違うのは**意味的に不整合**で、エラー時の挙動が直感に反し得る
  （resource は公開だが label 側に候補が無い → admission 通過後に `availableForRemote` が null → QUEUED）。
- local lock() も resource と label の同時指定は label 優先で resource を無視するため、**この曖昧さ自体は local 由来**。
  境界（`RemoteApiV1Action` POST）で「resource と label の同時指定は 400 で拒否」するか、`validateSelector` を
  「両指定時は両方を検証」に揃えると整合する。重大度 **Low**。

<a id="m1e-3"></a>
### M1E-3【Low／設計上の確認】lease 操作（heartbeat / release）は REMOTE 権限のみで認可し、lockId 所有者を検証しない

`POST /lease/{lockId}/heartbeat` と `/release` は `LockableResourcesRootAction.REMOTE` 権限のみをチェックし、
**呼び出し元 clientId が当該 lockId の取得者かを確認しない**。lockId は UUID（capability）なので通常は他者が知り得ないが、
**REMOTE 権限を持つ別クライアントが lockId を入手すれば、他クライアントのロックを release / heartbeat できる**。

- 小規模・相互信頼の CI/CD という想定ユーザー（設計の前提）では**許容範囲**で、これは既存（M1A/M1B）の信頼モデル
  （トラストバウンダリ＝REMOTE 権限）そのもの。M1E の新規問題ではない。
- 多テナントに広げる場合は「record.clientId と呼び出し元 clientId の一致」を lease 操作で検証する余地がある（P1+ 候補）。
  本サイクルでは**既知の設計上の選択として記録**するに留める。重大度 **Low（設計確認）**。

---

## 4. 軽微 / nits

| # | 内容 | 重さ | 場所 |
|---|---|---|---|
| L-a | `setRemotes` だけが binding 途中で `save()` を呼ぶ（他の `setExposeLabel`/`setClientId`/`setForcedServerId`/`setRemoteApiEnabled` は呼ばない）。GlobalConfiguration の最終 `save()` で上書きされるため害は無いが、フォーム束縛途中の eager save は不整合で、CasC 経由でも不要な早期保存を生む。1 本化（setter では save しない）を推奨 | 低（一貫性） | `LockableResourcesManager.setRemotes` |
| L-b | `RemoteConnection.validate()` は serverId / url の非空のみ検査し、**url のスキーム（http/https）を検証しない**。`file:` 等でも通る（`RemoteApiClient.resolve` は `URI.create` で素通り）。admin 設定値なので低リスクだが、`doCheckUrl`（FormValidation）で http(s) を要求すると親切 | 低（堅牢性） | `RemoteConnection` |
| L-c | `RemoteApiV1Action.parseJsonBody` は POST ボディを**上限なく読み切る**（`while read`）。認証済み（REMOTE 権限）前提なので実害は低いが、巨大ボディで OOM を誘発し得る。`Content-Length` 上限 or 読み取りバイト上限を設けると安全網になる | 低（DoS 安全網） | `RemoteApiV1Action.parseJsonBody` |
| L-d | `RemoteApiV1Action` POST で `enqueue` が `UNKNOWN_*` 以外の理由で `FAILED` を返すと（実質 `MISSING_TARGET` だが境界の `MISSING_TARGET` チェックで到達不能）、**FAILED 状態を 202 で返す**フォールスルーになる。現状到達不能だが、防御的に「FAILED は 4xx」へ寄せると将来の追加コードに強い | 低（防御） | `RemoteApiV1Action` POST 末尾の分岐 |
| L-e | `getExposeLabels()` は呼び出しごとに `split` で集合を再構築する（昇格スキャンで毎 tick × 候補数）。small-scale では無視できるが、`exposeLabel` の setter でキャッシュしておく手もある（任意） | 低（性能） | `LockableResourcesManager.getExposeLabels` |

---

## 5. memo.txt のユーザー確認事項への回答（透過等価の確定）

ユーザーの `memo.txt` の確認事項は M1E の核心そのものなので、コード実態に基づき確定回答する（再議論防止）。

> **Q. remote からのリソース要求は「lock() パラメータ ＋ さらに exposeLabel が AND でついた」と解釈できるか。**

**A. できる。** これは M1E の設計（設計書 §4-3）であり、コードでも厳密にそうなっている:

- 解決は canonical `getAvailableResources` に委譲され、**唯一の remote 固有差分は `candidateFilter = r -> isExposed(r, exposeLabels)`**
  を**個数選択の前**に候補プールへ適用する点だけ（`getFreeResourcesWithLabel` の `candidates.removeIf(...)`）。
- すなわち「ラベル一致（または name 一致）」＝従来の単一ラベル一致（無改修）と「exposeLabel(集合) のいずれかを持つ」＝可視性フィルタの **AND**。
  exposeLabel の AND/OR ロジックは remote 層に閉じ、local の意味論には混入しない。

memo.txt の具体例（res1: `dev1` / res2: `dev1 exposed` / res3: `dev1 exposed` / res4: `dev2 exposed`、すなわち exposeLabel=`exposed`）に対する実装挙動:

| 要求 | admission（`validateRemoteSelectors`） | 結果 | memo の期待 | 一致 |
|---|---|---|---|---|
| `lock(resource:'res1')` | res1 は `exposed` を持たない → `UNKNOWN_RESOURCE` | **404** | http 404 | ✓ |
| `lock(resource:'res2')` | res2 は `exposed` を持つ → 通過。空きなら ACQUIRED / busy なら QUEUED | **202（ACQUIRED/QUEUED）** | QUEUED | ✓ |
| `lock(label:'dev1')` | `hasExposedCandidate('dev1', {exposed})` = res2/res3 が該当 → 通過。`dev1`∧`exposed` の可視候補から確保 | **202（ACQUIRED/QUEUED）** | QUEUED | ✓ |

> **補足（memo の「もともとの lock は label をひとつしか渡せない」）:** そのとおりで、local の単一ラベル一致は無改修のまま。
> remote は「要求ラベル X（単一）AND exposeLabel(集合・OR)」を可視性フィルタで吸収するので、**local に複数ラベル AND を埋め込む必要は無い**。
> exposeLabel を**複数**にできるのは「公開する側のマーカー集合」であって、要求側のラベルは依然 1 つ。両者は別軸（§4-3 の分離）。

> **memo の「remote 経由の ephemeral はつぶせた」について:** 即時取得経路では**そのとおり**（H-1 解消・テスト実証済み）。
> ただし昇格経路に同クラスの残渣が 1 つある（**M1E-1**）。「完全につぶせた」と言うには M1E-1 の対処が必要。

---

## 6. テスト / 検証層の評価

- **M1D レビューで指摘したテスト穴は概ね埋まった。** H-1 直撃（`enqueueRejectsUnknownResourceAndCreatesNothing`：FAILED かつ `fromName==null`）、
  未公開名拒否（`unexposedNamedResourceIsRejected`）、exposeLabel の OR 公開（`multipleExposeLabelsAreOredForExposure`）、
  不正 selectStrategy の 400（`RemoteApiV1ActionTest`）、昇格経路の env var、E2E S17（実環境で `NOT_CREATED=true`）まで網羅。
  [[rlr-equivalence-test-defaults]] の「既定値/未指定/0/空を突く」教訓に沿っている。
- **唯一の穴は M1E-1 の経路。** 「name 指定で QUEUED → 当該リソースを admin 削除 → 昇格 tick → 再生成されていないこと」を突くテストが無い。
  M1E-1 を (a) で塞ぐ際に併せて追加すべき（§3 M1E-1 の回帰テスト案）。
- E2E 仕様（`E2E_TEST_SPECIFICATION.md`）にも、余裕があれば M1E-1 の「QUEUED 中削除でリソースが増えない」シナリオを将来タグで追記推奨。

---

## 7. 推奨アクション（優先順）

1. **M1E-1 を塞ぐ**（推奨は (a)：`getNextRemoteEntry` の解決前に `validateRemoteSelectors` を再実行し、不可なら entry を terminal-mark）。
   即時取得で閉じた H-1 を**昇格経路でも閉じ**、設計書 §3-4 の記述と実装を一致させる。併せて回帰テストを追加。
   **これで「remote 経由の ephemeral は（全経路で）つぶせた」と名乗れる。**
2. **設計書 §3-4 を実態に合わせて修正**（「昇格時は candidateFilter が弾く」の前段で `fromNames(create=true)` が再生成し得る点と、その対処を明記）。
   M1E-1 を (a) で塞いだ後は「昇格時にも admission を再検証する」と更新。
3. **M1E-2**（resource+label 同時指定のセレクタ不整合）は任意。境界で 400 拒否、または `validateSelector` を両検証に揃える。fail-open ではないため優先度低。
4. **M1E-3 / L-a〜L-e** は後送り可。M1E-3 は「lease 操作の所有者検証は P1+（多テナント時）」として notes に記録。L-b（url スキーム検証）/ L-c（ボディ上限）は安全網として安価。
5. メモリ／notes の M1E 記述に「M1E-1 を残課題として登録」を追記（[[remote-lock-project-state]]）。

> **総括:** M1E は M1D レビューの 2 大指摘（H-1・M-2）を設計どおり解消し、exposeLabel 集合（OR）公開という実用的拡張を
> **canonical を汚さず**に入れた、低リスクで効果の大きいサイクルである。即時取得という主経路で H-1 は閉じ、テストも厚い。
> 残るは **M1E-1（昇格経路の admission 再検証欠落による ephemeral 再生成）** 一点 ―― 狭く・fail-open ではないが、
> 「H-1 クラスを全経路で閉じた」と宣言するには対処（または明文化）が要る。これを片付ければ M1E は PR 品質に到達する。

---

## 更新履歴

- 2026-06-14: 初版作成。`master`(`863ea4d`)..M1E(`5d956de`) の全面差分（43 ファイル / +5256）を静的精読。
  M1D レビュー H-1・M-2 の解消（即時取得経路）と exposeLabel 集合（OR）公開・canonical 委譲の整合をアーキテクチャの成功と評価。
  新規指摘 M1E-1（昇格経路の admission 再検証欠落 → 削除済みリソースの ephemeral 再生成・孤児化、H-1 同クラスの残渣、Low–Medium）を検出。
  M1E-2（resource+label 同時指定のセレクタ不整合・Low・非 fail-open）、M1E-3（lease 操作の所有者非検証・設計上）、nits L-a〜L-e を付記。
  memo.txt のユーザー確認事項（remote 要求 = lock() ＋ exposeLabel AND か）に「Yes」と確定回答し、具体例の挙動一致を表で実証。
