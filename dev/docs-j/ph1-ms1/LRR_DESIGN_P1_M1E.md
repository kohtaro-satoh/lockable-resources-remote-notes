# Remote Lockable Resources 仕様書（Phase 1 / M1E）

> **出典:** [jenkinsci/lockable-resources-plugin #1025](https://github.com/jenkinsci/lockable-resources-plugin/issues/1025)
> **前提文書:** `LRR_DESIGN_P1_M1D.md`（M1D 仕様＝真のブリッジ化）/ `LRR_RESULT_P1_M1D.md`（M1D 結果）/ `LRR_REVIEW_P1_M1D.md`（M1D レビュー）
> **対象スコープ:** Phase 1 M1E（**M1D レビュー解消＋意図的単純化** — 未知/未公開は API 流に 404 拒否、公開フィルタは exposeLabel（複数ラベル可）に割り切り）

---

## 目次

1. [M1E の位置づけ](#1-m1e-の位置づけ)
2. [設計判断：透過等価の境界を引き直す](#2-設計判断透過等価の境界を引き直す)
3. [H-1 解消：ephemeral 量産の遮断＋404 admission](#3-h-1-解消ephemeral-量産の遮断404-admission)
4. [M-2 解消：exposeLabel 単一フィルタへ単純化](#4-m-2-解消exposelabel-単一フィルタへ単純化)
5. [軽微（L-3 / L-4 / L-5）](#5-軽微l-3--l-4--l-5)
6. [真の非等価＋意図的非等価（再議論防止）](#6-真の非等価意図的非等価再議論防止)
7. [撤去 / 変更 / 残すコード](#7-撤去--変更--残すコード)
8. [スコープ整理](#8-スコープ整理)

---

## 1. M1E の位置づけ

M1D（真のブリッジ化）は「server が lock() 意味論を再実装する」のをやめ canonical 委譲に移すという**本筋で成功**した。
ただし完了レビュー（`LRR_REVIEW_P1_M1D.md`）で 2 件の課題が出た:

- **H-1【新規リグレッション】**: 「未知→QUEUED」へ転換するため POST 境界の存在/公開チェックを撤去した副作用で、
  RemoteUse クライアントが**未存在リソース名を投げるだけで永続 ephemeral を量産**できる（`createResource` が
  公開フィルタの前に走り、作られたリソースは公開もロックもされず回収もされない）。
- **M-2【設計過剰】**: 公開判定を `RemoteResourceExposurePolicy`（`ExtensionPoint`）として一般化したが、
  AND 固定＋既定常駐で「差し替え」が効かず、small-scale 想定には**過剰**だった。

M1E は **remote LR の想定ユーザー＝小規模 CI/CD 環境**を再確認し、次の 2 つの設計転換で両課題を解く:

1. **未知/未公開は API 流に 404 で即時拒否**（`UNKNOWN_RESOURCE` / `UNKNOWN_LABEL`、ステータスは一律 404）。
   → M1D の「未知→QUEUED（local 透過等価）」を**意図的に巻き戻す**（理由は §2・§6）。
2. **公開フィルタは exposeLabel に割り切る**（`ExtensionPoint` SPI を撤去し概念を 1 つに）。あわせて exposeLabel を
   **複数ラベル（空白区切り集合・OR 公開）**対応にして実用上の柔軟性を確保（§4）。

> **重要:** M1E は機能追加ではなく「境界の引き直しと単純化」のサイクル。canonical 委譲（M1D の成果）は保持し、
> M1C の再実装（`claimSelector` 等）は**復活させない**。実質「M1C の admission 検証（404）＋ M1D の正準解決」の合成。

## 2. 設計判断：透過等価の境界を引き直す

M1D は「透過等価は**可視サーフェスの内側**で成立すればよい」とした（M1D §2）。M1E はこの原則を一歩進め、
**「そのクライアントがロックし得ないリソース（未存在・未公開）」は透過等価の対象外**と明確化する。理由:

- 「未存在・未公開」は **local lock() に存在しない概念**（local には公開フィルタが無い）。よって「local がどうするか」を
  基準にする意味がなく、**remote 固有の admission（受付可否）問題**として API 流に扱うのが正しい。
- local の「未知リソースは QUEUED で待つ（資源は後から増え得る）」を remote に写すと、**H-1 の ephemeral 量産**と
  **無期限 QUEUED ＋ poll 占有**を生む。small-scale 環境ではメリットが無く、コストだけが乗る。
- API として「ロック対象が無い」は 404 が自然（REST 慣習）。一律 404 で**存在秘匿（enumeration 防止）**も兼ねる。

一方、「**公開済みだが現在ロック中（busy）**」は別物で、これは**透過等価の対象＝QUEUED**（peer の解放待ち）。
これこそ remote lock の本質的価値なので維持する。境界は次のとおり:

| 入力（acquire 要求） | M1D 挙動 | **M1E 挙動** |
|---|---|---|
| 未存在のリソース名 | ephemeral 作成→隠蔽→QUEUED（H-1） | **404 `UNKNOWN_RESOURCE`**（作成しない） |
| 存在するが未公開のリソース名 | 隠蔽→QUEUED | **404 `UNKNOWN_RESOURCE`**（一律 404・存在秘匿） |
| 公開候補 0 のラベル | 隠蔽→QUEUED | **404 `UNKNOWN_LABEL`** |
| 公開済み・現在 busy | QUEUED | **QUEUED（202）** ← 維持（peer 解放待ち） |
| 公開済み・空きあり | ACQUIRED | ACQUIRED ← 維持 |

> ステータスは**一律 404**（未存在/未公開を区別しない＝秘匿）。errorCode（`UNKNOWN_RESOURCE` / `UNKNOWN_LABEL`）は
> クライアント自身が送った種別の区別のため残す（新たな情報漏洩にはならない）。

## 3. H-1 解消：ephemeral 量産の遮断＋404 admission

### 3-1. remote 解決経路から `createResource` を撤去

`addRemoteStruct`（`LockableResourcesManager`）の `createResource(resource)` 呼び出しを削除する。
これで remote 要求が**サーバー上に新規 ephemeral を作ることはなくなる**。検証済み（=存在）の名前だけが
`LockableResourcesStruct` の `fromName` 解決に乗り、canonical の `fromNames(create=true)` も既存名には no-op なので
**新規作成を一切誘発しない**。

### 3-2. admission 検証（exposeLabel ベース）を `enqueue` 内に追加

`enqueue` の `synchronized (syncResources)` 区間の**先頭**で、main ＋各 extra セレクタを検証する:

```text
errorCode = validateRemoteSelectors(req):   // exposeLabel 集合ベース、ExtensionPoint なし
  resource 指定 → fromName(resource) が存在し exposeLabel のいずれかを持つか
                   無ければ "UNKNOWN_RESOURCE"
  label 指定    → label と（exposeLabel のいずれか）を併せ持つ候補が 1 つ以上あるか
                   無ければ "UNKNOWN_LABEL"
  セレクタ非在  → null（extra-only の main 等。検証なし）
errorCode != null → record.markFailed(errorCode); return    // terminal、toRemoteStructs に進まない
```

`validateRemoteSelectors`（および補助 `validateSelector` / `hasExposedCandidate`）は **M1C の実装を
exposeLabel ベースで復活**させる（M1D で撤去したもの。ただし `ExtensionPoint` ではなく exposeLabel 直参照）。
`syncResources` 下で呼ぶので resources / exposeLabel の読みは整合。

### 3-3. 404 へのマッピング（POST ハンドラ）

`RemoteApiV1Action` の POST `/acquire` は M1D で「enqueue 後つねに 202」になっている。ここに分岐を 1 つ足す:

```text
record = enqueue(...)
if record.state == FAILED && errorCode ∈ { UNKNOWN_RESOURCE, UNKNOWN_LABEL }:
    sendJsonError(rsp, 404, errorCode, message)     // 一律 404
else:
    202（従来どおり lockId + state を返す）           // ACQUIRED / QUEUED / SKIPPED
```

検証は `enqueue` 内（単一ソース・正しくロック）で行い、HTTP ステータスのマップだけハンドラが担う。
（M1C のように境界で別途 `fromName` チェックを書かない＝検証ロジックの二重化を避ける。）

### 3-4. 解決は canonical のまま（不変条件）

ACQUIRED / QUEUED の判定は M1D どおり `toRemoteStructs` → `availableForRemote`
（`getAvailableResources(..., candidateFilter)`）に委譲する。**`claimSelector` / `resolveRemoteAvailable` は復活させない。**
admission を通った要求は「存在＆公開」が保証されるので、busy なら QUEUED、空きありなら ACQUIRED に素直に落ちる。
QUEUED 中に admin が対象を削除/非公開化した場合は、昇格時の candidateFilter が弾き続け最終的に `QUEUE_EXPIRED`
（既存挙動）に縮退する（acquire 時 404 が主経路、これは稀なフォールバック）。

## 4. M-2 解消：exposeLabel（複数ラベル）フィルタへ単純化

### 4-1. ExtensionPoint を撤去し exposeLabel に一本化

- **`RemoteResourceExposurePolicy.java` と `ExposeLabelPolicy.java` を削除**（`ExtensionPoint` SPI を撤去）。
  AND 畳み込み・既定 Extension・「policy 未登録なら全公開」デッドパスがすべて消える。
- 公開判定は **exposeLabel 単一フィルタ**に割り切る。per-client allowlist / 認可 / 公開制限などの拡張は **P1+ 候補**で、
  想定ユーザー（小規模 CI/CD）には現時点で不要。必要になったら**その時に**改めて SPI 化する（YAGNI）。

### 4-2. exposeLabel は「複数ラベル」を許す（OR 公開）

exposeLabel を 1 つに固定すると硬すぎる（要求ラベルとの AND が常に「ちょうどそのラベル」前提になる）。そこで
**exposeLabel を空白区切りの「ラベル集合」**として解釈する（`LockableResource.labels` と同じ流儀＝`split("\\s+")`）。
`getExposeLabel()`（String）は不変のまま、集合化する `getExposeLabels()` を追加する:

- リソース R が公開される条件 = **R のラベル集合 ∩ exposeLabel 集合 ≠ ∅**（どれか 1 つを持てば公開＝**OR**）。
- 空 = 非公開（opt-in、不変）。
- これで 2 つの運用が両方素直に表現できる:
  - **既存ラベル群をそのまま公開:** `exposeLabel = "gpu license"`（gpu か license を持てば公開）。
  - **公開専用マーカーを付与:** `exposeLabel = "remote-ok"`（公開したい R に remote-ok を追記）。
- **後方互換:** 単一値（例 `"remote-ok"`）は 1 要素集合として従来どおり動作。設定 UI は既存の textbox のまま
  （ヘルプ文だけ「空白区切りで複数可」に更新）。exposeLabel はロック時にクライアントへ見える（labels は秘匿対象でない）
  ので、既存ラベルの公開でも新たな情報漏洩は無い。

### 4-3. 「要求ラベル AND exposeLabel(集合)」は local 無改修で吸収（懸念事項の確定）

local lock() のラベル一致は**単一ラベル**。remote の「要求ラベル X AND（exposeLabel のいずれか）」を成立させるが、
**local の一致ロジックに「複数ラベル AND/OR」を埋め込まない**。2 段に分離する:

```text
① ラベル一致  = 従来の単一ラベル一致（getResourcesWithLabel("X")、無改修）
② 可視性フィルタ = remote 層が組む generic Predicate を一段かます（個数選択の前）
     candidates.removeIf(r -> !visible.test(r))
   visible = r -> !Collections.disjoint(r.getLabelsAsList(), exposeLabels)   // exposeLabels 空 → r -> false
```

- ①の判定ロジックは**無改修**（単一ラベル一致のまま。「2 ラベル AND」改造は入れない）。
- canonical（`getAvailableResources` / `getFreeResourcesWithLabel`）は **generic な `Predicate<LockableResource>` 引数を
  1 つ持つだけ**で、exposeLabel の概念を知らない。local 呼び出しは `r -> true`（全通過）を渡すので**挙動は完全不変**
  （local 無改修の証拠＝375 緑がそのまま通る）。
- exposeLabel（集合・OR）の知識は **100% remote 層**（`availableForRemote` の predicate 構築）に閉じ、local の意味論に混入しない。
- フィルタは**個数選択の前**に効くので `amount<=0`（"可視マッチ全部"）が正しく成立。後段フィルタ案（個数意味論が壊れる）／
  remote 再実装案（M1D で消した `claimSelector` の復活＝ドリフト再来）はいずれも不可。**generic シームが唯一の現実解**。

> **確定（2026-06-13, ユーザー協議）:** 公開フィルタは exposeLabel 集合（OR）の単一概念。canonical には generic Predicate
> シームのみ（local 無改修・挙動不変）。exposeLabel の AND/OR ロジックは remote 層に閉じる。**この分離は再議論しない。**

## 5. 軽微（L-3 / L-4 / L-5）

- **L-3（env var 生成の 1 本化）:** `RemoteQueueEntry.onAcquired` がインラインで `name→properties` マップを作って
  `buildLockEnvVars` を直接呼ぶのをやめ、即時取得経路と同じ `LockableResourcesManager.remoteLockEnvVars(variable, resources)`
  に統一する。同一アダプタの重複を解消。
- **L-4（不正 resourceSelectStrategy）:** POST 境界で未知の strategy 文字列を **400 `INVALID_SELECT_STRATEGY`** として
  弾く（他の 400 検証と同列、local の「不正値は拒否」と整合）。`parseSelectStrategy` の寛容フォールバックは安全網として残す。
- **L-5（テスト）:** §6 のテスト方針に反映（未存在名→404 かつ**リソースが増えない**、未公開→404、exposeLabel フィルタ直接、
  selectStrategy 透過、QUEUED→昇格経路でのプロパティ env var）。

## 6. 真の非等価＋意図的非等価（再議論防止）

純ブリッジでも残る**真の非等価**（M1B §1 / M1D §7、設計上維持）:

- 時間遅延（往復レイテンシ）/ ネットワーク障害時の fail-close / 再起動 transient。

M1E で新たに**意図的に持ち込む非等価**（local と異なるが、設計判断として確定。**今後「local 等価に戻す」議論をしない**）:

- **未存在/未公開リソース → 即時 404**（local は QUEUED で待つ）。理由: ①remote 固有の admission 概念で local 基準が
  無意味、②small-scale 環境では QUEUED 占有・ephemeral 量産（H-1）のコストだけが乗る、③API として 404 が自然・存在秘匿。
  → この決定は M1D の「未知→QUEUED」を**意図的に置き換える**もので、`LRR_REVIEW_P1_M1D.md` の H-1 対応方針 (a) に
  ユーザー確定（2026-06-13）。

「公開済みだが busy → QUEUED」は**透過等価のまま**（remote lock の本質、維持）。

## 7. 撤去 / 変更 / 残すコード

| 区分 | 対象 |
|---|---|
| **撤去** | `RemoteResourceExposurePolicy.java` / `ExposeLabelPolicy.java`（SPI）/ `addRemoteStruct` の `createResource` 呼び出し |
| **追加** | `getExposeLabels()`（`exposeLabel` String を `split("\\s+")` で集合化）。`getExposeLabel()` は不変・後方互換 |
| **復活（exposeLabel 集合ベース）** | `validateRemoteSelectors` / `validateSelector` / `hasExposedCandidate`（admission のみ。解決の再実装ではない） |
| **変更** | `availableForRemote` が `RemoteResourceExposurePolicy.visibilityFor` の代わりに exposeLabel 集合の OR predicate を直接構築 / POST が FAILED+`UNKNOWN_*` を 404 にマップ / POST が不正 strategy を 400 / `RemoteQueueEntry.onAcquired` → `remoteLockEnvVars` / config UI のヘルプ文（複数可）と `config.properties` タイトル |
| **残す（M1D の成果）** | canonical 委譲（`toRemoteStructs` / `availableForRemote` / `getAvailableResources(..., Predicate)` シーム）/ 共有 `buildLockEnvVars` / トランスポート・耐障害性・STALE・QUEUE_EXPIRED・Force Release |

## 8. スコープ整理

### 含む（M1E）

| 項目 | 内容 |
|---|---|
| H-1 解消 | `createResource` 撤去 ＋ exposeLabel 集合ベース admission（未存在/未公開 → 一律 404）。ephemeral 量産を遮断 |
| M-2 解消 | `ExtensionPoint` SPI 撤去、exposeLabel フィルタへ単純化（`Predicate` シームは保持） |
| exposeLabel 複数対応 | `exposeLabel` を空白区切りのラベル集合として解釈（OR 公開）。後方互換・UI ほぼ不変 |
| L-3/L-4/L-5 | env var 1 本化／不正 strategy 400／テスト拡充 |

### 含まない（M1E スコープ外）

| 項目 | 備考 |
|---|---|
| per-client allowlist / 認可 / 公開制限 | P1+ 候補。必要時に改めて SPI 化（YAGNI） |
| M-1 onResume displayTarget 劣化 | 表示のみ・後送り（M1B 以来） |
| 真の非等価（時間遅延 / fail-close / 再起動 transient） | 設計上維持 |

## 更新履歴

- 2026-06-13: 初版作成。M1D レビュー H-1（ephemeral 量産）・M-2（ExtensionPoint 過剰）の解消方針を定義。
  未知/未公開は一律 404（ユーザー確定）、公開フィルタは exposeLabel に単純化。canonical 委譲は保持し、
  M1C の再実装は復活させない。「未知→404」を意図的非等価として明文化（再議論防止）。
- 2026-06-13: ユーザー懸念（exposeLabel 単一だと local の単一ラベル一致に AND 判定が混入しないか）を反映。
  §4 を全面改訂: exposeLabel を**複数ラベル（空白区切り・OR 公開）**対応に。「要求ラベル AND exposeLabel(集合)」は
  generic Predicate シームで吸収し **local の判定ロジックは無改修・挙動不変**（§4-3）であることを明記（再議論防止）。
