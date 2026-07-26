# Remote LR 開発活動 レビュー（Phase 1 / M1D 完了時点）

> **レビュー日:** 2026-06-13
> **対象 plugin ブランチ:** `feature/1025-remote-lockable-resources-p1-m1d`（HEAD: `819daa0`、単一コミット。mvn 375 件成功・E2E 19/19）
> **対象ドキュメント:** `dev/docs-j/`（LRR_DESIGN_P1_M1D / LRR_IMPLEMENTATION_STEPS_P1_M1D / LRR_RESULT_P1_M1D / E2E_TEST_SPECIFICATION）、`LRR_REVIEW_P1_M1B.md`
> **観点:** 元構想（[#1025](https://github.com/jenkinsci/lockable-resources-plugin/issues/1025)）・M1D の中核目標「真のブリッジ化（lock() 正準パスへの委譲＝透過等価）」の達成度・委譲リファクタの正当性・新規リグレッションの有無
> **前提:** M1B/M1A レビューと同じ方法論。フルビルド（~17 分）は再実行せず、`819daa0` の差分とコードを静的に精読。テスト件数（375）/ E2E（19/19）は記録レポートを信頼するが、その実在を確認した（`dev/reports/20260613125351-mvn-test.log` = `Tests run: 375, Failures: 0, Skipped: 1` / `BUILD SUCCESS`、`dev/reports/20260613132702-e2e-test.md` = `pass: 19 / fail: 0`、作業ツリーは `819daa0` でクリーン）。ただし後述のとおり、その検証層は M1D で**新たに開いた一経路**を突いていない。

---

## M1E での対応（2026-06-14 更新・**解消済み**）

本レビューの指摘を受けて M1E サイクルを実施・完了（plugin ブランチ `feature/1025-remote-lockable-resources-p1-m1e`
HEAD `5d956de`、m1d ベース）。方針・解消状況（`LRR_DESIGN_P1_M1E.md` / `LRR_IMPLEMENTATION_STEPS_P1_M1E.md` /
`LRR_RESULT_P1_M1E.md`）:

| 指摘 | M1E での方針（確定） |
|---|---|
| H-1 ephemeral 量産 | **(a)＋API 流拒否**: 解決経路の `createResource` を撤去。未存在/未公開は **一律 404**（`UNKNOWN_RESOURCE`/`UNKNOWN_LABEL`）。busy（公開済み）は従来どおり 202 QUEUED 維持。「未知→404」は M1D の「未知→QUEUED」を**意図的に置き換える**（small-scale 前提・存在秘匿・ephemeral 汚染回避） |
| M-2 ExtensionPoint 過剰 | **単純化**: `RemoteResourceExposurePolicy`/`ExposeLabelPolicy` を削除し **exposeLabel フィルタ**へ割り切り。あわせて exposeLabel を**複数ラベル（空白区切り・OR 公開）**対応に。「要求ラベル AND exposeLabel」は generic Predicate で吸収し local 無改修（設計 §4-3）。allowlist/認可は P1+（YAGNI） |
| L-3 env var 重複 | `onAcquired` を `remoteLockEnvVars` に統一 |
| L-4 不正 strategy | POST 境界で **400** `INVALID_SELECT_STRATEGY` |
| L-5 テスト穴 | unknown→404・**リソース非作成**の回帰、未公開→404、selectStrategy、昇格経路 env var、S17 追加 |

**解消確認（2026-06-14）:** 上記すべて実装・検証済み。**mvn test 378 / 0 失敗**（`dev/reports/20260614002216-mvn-test.log`）、
**E2E 20/20 PASS**（`dev/reports/20260614004015-e2e-test.md`）。S17 で「未知 acquire → 404 即時失敗＋サーバーに
ephemeral 非作成（`NOT_CREATED=true`）」を実環境実証。詳細は `LRR_RESULT_P1_M1E.md`。M1D レビュー指摘は全クローズ。

---

## 目次

1. [総評](#1-総評)
2. [M1D で良くなった点（アーキテクチャの成功）](#2-m1d-で良くなった点アーキテクチャの成功)
3. [指摘事項（H-1 / M-2）](#3-指摘事項)
4. [軽微（L-3/L-4/L-5）](#4-軽微lll)
5. [透過等価の確認（疑義の解消）](#5-透過等価の確認疑義の解消)
6. [テスト/検証層の評価](#6-テスト検証層の評価)
7. [推奨アクション（優先順）](#7-推奨アクション優先順)

---

## 1. 総評

**M1D の中核設計判断は正しく、実装も高品質である。** 「server が lock() の意味論を再実装している」ことが
M1A→M1B→M1C で `extra`/`label`/`quantity` の機能別残件を生み続けた根本原因だ、という診断は的確であり、
それを **canonical `getAvailableResources` への委譲**で構造的に断ったのは本プロジェクト最大のアーキテクチャ前進である。
`resolveRemoteAvailable` / `claimSelector` / `validateRemoteSelectors` / `generateLockEnvVars` という
**再実装の塊を丸ごと撤去**し、後方互換オーバーロード（`Predicate<LockableResource>` 版、既存呼び出しは `r -> true`）で
local を一切いじらずに済ませた設計は、低リスクかつ効果が大きい。env var 生成の共有化
（`LockStepExecution.buildLockEnvVars`）でプロパティ env var が透過したこと、公開判定をブリッジの外側の
`RemoteResourceExposurePolicy`（`ExtensionPoint`）へ追い出したことも、いずれも「関心の分離」として正しい層化だ。

並行性も M1C の到達点を後退させていない。即時取得（`RemoteLockManager.enqueue`）も
キュー昇格（`getNextRemoteEntry`→`proceedRemoteEntry`）も**解決と確定ロックを単一の `syncResources` 保持区間内**で
行うため、resolve→lock の TOCTOU は無い（昇格経路は `proceedNextContext()` のループ全体が
`synchronized (syncResources)` 下。`getNextRemoteEntry` が `setResolved` した直後に同一ロック内で
`proceedRemoteEntry` が `lockForRemote` する）。M1B C-2（client release と昇格の競合）の修正も維持されている。

**ただし「透過等価」を額面どおり名乗るには、M1D が新たに開いた一経路に未解決の問題がある（H-1）。**
M1D は「未知/未公開リソースは terminal をやめ QUEUED（local 等価）」とするために、POST 境界の存在/公開チェックを撤去した。
この撤去自体は設計として妥当だが、その結果、**任意の RemoteUse クライアントが存在しないリソース名を投げるだけで、
公開もされず・ロックもされない ephemeral リソースをサーバー上に作成し、ディスクに永続化させられる**ようになった。
これは M1A/M1B のような排他保証の侵害（fail-open）ではなく、認証済みクライアントによる**リソース汚染／DoS**だが、
**M1D 自身が新規に作り込んだリグレッション**であり、しかも M1D のテスト群（ユニット・E2E とも）は
リソースを必ず事前作成してから要求するため、この「オンデマンド作成経路」を一度も突いていない。
M1A→M1C を貫く構造的弱点「『作ったものが宣言どおりか』の検証層に穴がある」が、形を変えてまた再現している。

結論として、**M1D は設計・実装の本筋では成功**だが、H-1 を塞ぐまでは「透過等価を達成し PR 可能」とは言い切れない。

---

## 2. M1D で良くなった点（アーキテクチャの成功）

- **canonical 委譲が「機能別残件」を構造的に消した。** `toRemoteStructs` が `RemoteLockRequest` を
  `List<LockableResourcesStruct>`（`LockStep.getResources()` の鏡写し）に変換し、local と同じ
  `getAvailableResources(structs, …, candidateFilter)` を呼ぶ。extra / label / quantity(0=all) /
  resourceSelectStrategy / 重複排除（`isPreReserved`）/ ephemeral が**すべて canonical 由来**になり、
  個別実装が無くなった＝個別ドリフトの余地が消えた。C-1/F-1 級の再発防止として理想的。
- **後方互換オーバーロードで local 無改修。** `getAvailableResources(...)` /
  `getFreeResourcesWithLabel(...)` に `Predicate<LockableResource> candidateFilter` 版を足し、
  既存版は `r -> true` で委譲（`LockableResourcesManager.java:1612`）。フィルタは個数選択の**前**に
  候補プールへ適用（`getFreeResourcesWithLabel` の `candidates.removeIf(...)`、`:1728`）するため、
  `amount<=0`（"all"）が「**可視**マッチ全部」と正しく解釈される。
- **env var の共有化。** `proceed()` のインライン生成を `LockStepExecution.buildLockEnvVars`
  （`LockStepExecution.java:649` 付近）に抽出し、local と remote が同じ関数を呼ぶ。`VAR0_<PROP>`
  まで含めて生成ロジックが一本化され、リソースプロパティ env var が透過した。
- **公開判定の層化。** `RemoteResourceExposurePolicy`（`ExtensionPoint`、SPI）＋既定 `@Extension ExposeLabelPolicy`。
  ブリッジが policy を `Predicate` に畳んで canonical へ渡す。exposeLabel は local lock() に無い remote 固有概念なので、
  解決コードから追い出してフィルタ層に置いたのは正しい設計判断（M1C までは解決コードに直書きされていた）。
- **並行性の非後退。** resolve→lock を単一 `syncResources` 区間で実施（TOCTOU 無し）。M1C の release 直列化も維持。
- **検証証跡の実在を確認。** mvn 375/0 失敗、E2E 19/19（S01–S16 + D01–D03）。S16 `remote-resource-properties` は
  プロパティ env var の実環境伝搬を実証している。レポートファイルは現存し、ツリーは `819daa0` でクリーン。

---

## 3. 指摘事項

### H-1【Medium／セキュリティ・堅牢性 — 新規リグレッション】未公開・未存在リソース名で ephemeral リソースが量産・永続化される

**症状:** `remoteApiEnabled=true` のサーバーに対し、RemoteUse 権限を持つクライアントが
存在しないリソース名（例: `resource: "scratch-" + ランダム`）で acquire を投げると、毎回サーバー上に
**新しい ephemeral `LockableResource` が作成され、`config` としてディスクに保存される**。その後そのリソースは
公開もロックもされず QUEUED のまま放置され、**解放経路を一度も通らないため決して回収されない**。
要求名を変えながらループすれば、サーバーのリソース一覧と設定 XML が**上限なく肥大**し、再起動後も残る。

**経路:**

1. M1D は POST 境界の存在/公開チェックを撤去した（`RemoteApiV1Action.java:108-116` および `:145` のコメント
   「Exposure is decided by RemoteResourceExposurePolicy at resolution time, not here」）。
   現在 acquire の入口に残るゲートは `remoteApiEnabled` / `RemoteUse` 権限 / `MISSING_TARGET`（空要求）のみで、
   **リソースの存在チェックは無い**。任意名がそのまま解決層へ届く。
2. 解決層の入口 `toRemoteStructs` → `addRemoteStruct` が、**公開フィルタを適用する前に**
   `createResource(resource)` を呼ぶ（`LockableResourcesManager.java:1223`）。これは
   `LockableResourcesStruct(resources,label,quantity)` コンストラクタが `fromName`（作成なし）で名前解決し、
   未存在名を黙って落とすため、「canonical 解決に見せるには先に実体を作る必要がある」ことに由来する必須の呼び出しである。
3. `createResource` は `allowEphemeralResources`（**既定 `true`**、`:86`）が真なら ephemeral を作り、
   `addResource(resource, /*doSave*/ true)` で **`this.save()` してディスクへ永続化**する（`:1295-1304`、addResource の `save()`）。
4. 続く `availableForRemote` → `getAvailableResources` の name 分岐で公開フィルタ
   （既定 `ExposeLabelPolicy`）が**当該リソースを不可視と判定**し（新規 ephemeral は exposeLabel を持たない）、
   `available = null` → **QUEUED**（`:1654-1659`）。
5. QUEUED はタイムアウトで `QUEUE_EXPIRED` になり record は FAILED/unqueue されるが、
   **作成済み ephemeral リソースは削除されない**。ephemeral 回収は `freeResources` の
   「ロック→解放」経路だけ（`:919-928`）で、一度もロックされていないこのリソースはそこを通らない。

**なぜ重大か:**

- **M1D 自身が作り込んだ新規リグレッション。** M1C では未公開/未存在は POST 境界で 404 `UNKNOWN_RESOURCE` に倒れ、
  `createResource` には到達しなかった。M1D が「未知→QUEUED」へ転換するため境界チェックを外した副作用として、
  作成オンデマンド経路が初めて外部から到達可能になった。
- **認証済みとはいえトラストバウンダリが違う。** local lock() も未存在名で ephemeral を作るが、それは**同一プロセス内の
  信頼された pipeline** が呼ぶうえ、local には公開フィルタが無いので**作った直後に必ずロックされ、解放時に回収される**。
  remote は**ネットワーク越しの半信頼ピア**が呼び、**作った直後にフィルタで隠されてロックされない**＝回収されない。
  「透過等価」が local の挙動をコピーしたつもりが、フィルタ層の存在によって**作成と回収のライフサイクルだけ非対称**になっている。
- **永続・無制限・再起動耐性。** `doSave=true` で config XML に書かれるため、メモリだけでなくディスクが伸び、
  ループ要求は反復 `save()`（I/O）も誘発する。
- **既定構成で到達可能。** 前提は「remote 機能を有効化（`remoteApiEnabled=true`、管理者オプトイン）」＋
  `allowEphemeralResources=true`（既定）＋呼び出し側 RemoteUse のみ。exposeLabel の値は無関係（`createResource` は
  exposeLabel を参照しない）。つまり**remote 機能を一度 ON にすれば既定で踏める**。

**補足（設計的にも作成は無意味）:** 既定 `ExposeLabelPolicy` の下では、新規 ephemeral はラベルを持たないため
**原理的に公開され得ず、ロックされ得ない**。したがって remote 解決経路での ephemeral 作成は
（label ではなく name を公開する独自 policy を入れた特殊例を除き）**そもそも有益な場面が無い**。
「local が作るから remote も作る」という透過は、ここでは利得ゼロ・コストありで成り立っていない。

**修正方針（いずれか。要決定）:**

- **(a) remote 解決経路では ephemeral を作らない（推奨）。** `addRemoteStruct` の `createResource` 呼び出しを外し、
  未存在名は素直に「現時点で不可視＝QUEUED」とする（local の「資源は後から増え得る」と同じ含意で、後から
  *管理者が* 実体を作れば昇格する）。既定 policy 下では何も失わない。
- **(b) 公開され得ない作成済み ephemeral を回収する。** resolve 後に「作成したが可視候補にならなかった」
  ephemeral を sweep する、もしくは QUEUE_EXPIRED 時に未ロックの ephemeral を回収する。
- **(c) 境界で軽い存在チェックを復活させる。** ただし enumeration オラクルの再導入＋label ベース公開との
  鶏卵問題があるため非推奨。

**併せて H-1 のリグレッションテストを追加すること**（下記 L-5）。

### M-2【Low–Medium／設計・文書整合】公開 ExtensionPoint は AND 固定＋既定常駐のため「差し替え」できない

`RemoteResourceExposurePolicy.visibilityFor` は登録された全 policy を **AND（最も制限的なものが勝つ）** で畳む。
一方、既定 `ExposeLabelPolicy` は常に `@Extension` で登録され、**exposeLabel が空（既定）なら全リソースに対して
`isExposed=false`** を返す（`ExposeLabelPolicy.java`）。この 2 つが組み合わさると:

- 第三者が「per-client allowlist で *許可* する」独自 policy を `@Extension` で足しても、**exposeLabel が空のままだと
  ExposeLabelPolicy が全件を拒否し、AND によって何も公開されない**。独自 policy は事実上死ぬ。
- 独自 policy を活かすには管理者が exposeLabel を「全候補が持つラベル」に設定する必要があり、
  実質「exposeLabel **かつ** 独自制限」しか表現できない。**exposeLabel を別ロジックで *置き換える* ことはできない。**

設計書 §4 は第三者が公開判定を「**差し替え・拡張**できる」と書いているが、現状の実装で可能なのは
「**さらに制限する（拡張）**」だけで「**置き換える**」は不可。インターフェースの Javadoc 側
（"restrict exposure further" / "most-restrictive wins"）の方が正確。また Javadoc の
「No policies registered ⇒ accept all (transparent)」分岐は、既定 policy が常駐するため**実質デッドパス**。

M1D のスコープ（seam を用意するのみ、既定＝exposeLabel）としては許容範囲だが、**PR で seam を売りにする以上、
文書と実装の整合を取るべき**:

- 設計書/Javadoc を「独自 policy は exposeLabel の**上に**重ねて *さらに* 制限する。AND（最も制限的が勝つ）」と明記。
- exposeLabel そのものを置換したい場合の手順（既定 `ExposeLabelPolicy` を無効化/上書きする、もしくは
  exposeLabel を許容的に設定する）を書く。
- 「policy 未登録なら全公開」は既定常駐下では起きない旨を注記（誤解防止）。

---

## 4. 軽微（L-3/L-4/L-5）

| # | 内容 | 重さ | 場所 |
|---|---|---|---|
| L-3 | env var マップ生成の重複。即時取得は `LockableResourcesManager.remoteLockEnvVars(variable, List<LockableResource>)` を使うが、キュー昇格の `RemoteQueueEntry.onAcquired` は同じ `name→properties` マップ構築を**インラインで再実装**して `buildLockEnvVars` を直接呼ぶ。同一アダプタが 2 箇所に。`onAcquired` を `remoteLockEnvVars` 経由に統一すれば 1 本化できる | 低（保守性） | `RemoteQueueEntry.java`（onAcquired）/ `LockableResourcesManager.java`（remoteLockEnvVars） |
| L-4 | `parseSelectStrategy` は不正な `resourceSelectStrategy` 文字列を**黙って SEQUENTIAL にフォールバック**する。local は `LockStep` の setter で設定時に検証し不正値を弾く（`LockStep.java:112-124`）ため、ここだけ挙動が緩い。透過等価の観点では「不正値→既定」を local と揃える（または warn ログ）と良い。`java.util.Locale.ENGLISH` がインライン完全修飾（import 整理の余地） | 低（等価性・スタイル） | `LockableResourcesManager.java`（parseSelectStrategy） |
| L-5 | テスト未カバー経路（下記 §6 参照）。特に **H-1 の作成オンデマンド経路**、`resourceSelectStrategy` の remote 反映、プロパティ env var の **QUEUED→昇格（`onAcquired`）経路** | 低→中（検証層） | `RemoteLockManagerTest` 他 |

---

## 5. 透過等価の確認（疑義の解消）

レビュー中に「local と乖離しないか」を検討し、**意図どおり等価**と確認できた点を、後続サイクルでの再議論防止のため記録する:

- **空集合 → QUEUED は local 一致。** `availableForRemote` の `available.isEmpty() ? null` は、`getAvailableResources`
  自身の「`available.isEmpty()` なら `return null`」（`:1664-1667`）と同じ。`lock(label:'存在しないラベル')` は
  local も QUEUED で待つため、remote の QUEUED も等価（`availableForRemote` の `isEmpty` ガードは防御的な二重化で無害）。
- **同一 label の main+extra（`lock(label:'X', extra:[[label:'X']])`）の QUEUED も local quirk の正しい継承。**
  canonical の `isPreReserved` 分岐（`:1669-1679`、`available.removeAll(candidates)`）で extra 側が空になり
  `return null`→QUEUED。これは local の既知挙動そのもので、M1C の「別個 2 個確保」を捨てて local に合わせたのは
  M1D の趣旨どおり。専用 dedup テスト 2 件の削除は妥当。
- **selectStrategy の既定一致。** remote 既定（null）→ SEQUENTIAL は local 既定（`ResourceSelectStrategy.SEQUENTIAL`）と一致。

これらは「真の非等価」（時間遅延／fail-close／再起動 transient）ではなく、**設計どおりの透過等価**である。

---

## 6. テスト/検証層の評価

- **件数・回帰は十分（375 ユニット + 19 E2E）だが、M1D で開いた経路にネガティブ/作成系の穴がある。**
  これは M1A §6#5・M1B C-1 と同じ構造的弱点（[[rlr-equivalence-test-defaults]] の教訓）の再現。
- **不足しているテスト（次サイクルで追加すべき）:**
  - **H-1 直撃:** 「**未存在**リソース名で acquire → QUEUED」かつ「その名前の ephemeral が**作成され残存していない**こと」を
    アサートする。現状の `enqueueQueuesWhenResourceDoesNotExist` は QUEUED は見るが**作成有無を検証していない**。
    `unexposedNamedResourceStaysQueued` も `internal-1` を**事前作成**しており、オンデマンド作成経路を突いていない。
  - **selectStrategy:** `resourceSelectStrategy: "RANDOM"` の remote 反映（実装ステップ計画にあったが差分にユニットが無い）。
  - **プロパティ env var の昇格経路:** `resourcePropertyEnvVarsArePropagated` は即時取得のみ。
    一度 QUEUED にしてから昇格させ、`onAcquired` 経由でも `VAR0_<PROP>` が入ることを確認する。
  - **policy の差し替え（M-2）:** `@TestExtension` で「AND により独自 policy + 既定が最も制限的に効く」ことと、
    「exposeLabel 空時に独自 allow policy が効かない」ことをピン留めし、文書の主張と一致させる。
- E2E 仕様（`E2E_TEST_SPECIFICATION.md`）にも H-1 回帰（未存在名でリソースが増えない）を P1M1E（or 次タグ）として追記推奨。

---

## 7. 推奨アクション（優先順）

1. **H-1 を塞ぐ**（推奨は方針 (a)：remote 解決経路で `createResource` を呼ばない）。
   既定 `ExposeLabelPolicy` 下では失うものが無く、リソース汚染/DoS とディスク肥大を断てる。
   **これが片付くまで「透過等価を達成・PR 可能」とは名乗らない。**
2. **H-1 のリグレッションテストを追加**（未存在名 acquire 後にリソース数が増えていないこと）。
   併せて selectStrategy / 昇格経路 env var / policy 差し替えのユニットを補完（§6）。
3. **M-2: ExtensionPoint の文書整合**（「AND で *さらに* 制限／置換は不可、その手順」）。設計書 §4 と Javadoc を一致させる。
4. 軽微 L-3（env var 1 本化）/ L-4（selectStrategy 不正値の扱い）は任意。次サイクルに同梱するか後送りかを判断。
5. メモリ／notes の M1D 記述に「H-1 を次サイクル課題として登録」を追記（[[remote-lock-project-state]]）。

> **総括:** M1D の「真のブリッジ化」は本プロジェクトのアーキテクチャを正しい方向へ大きく前進させた。
> 委譲・層化・並行性は高品質で、透過等価の本筋は達成している。残るは H-1 一点 ——
> 「未知→QUEUED」転換の副作用で開いた **ephemeral 作成オンデマンド経路** ——
> を塞ぎ、その回帰テストを足すこと。これで M1D は PR 品質に到達する。

---

## 更新履歴

- 2026-06-13: 初版作成。M1D 完了時点（plugin `819daa0`）の全体レビュー。canonical 委譲による「真のブリッジ化」を
  アーキテクチャの成功と評価。新規リグレッション H-1（未公開/未存在名での ephemeral 量産・永続化）を Medium、
  公開 ExtensionPoint の AND 固定/差し替え不可（M-2）を設計・文書整合の指摘として検出。透過等価の本筋
  （空集合・同一 label・selectStrategy 既定）は意図どおりと確認。
