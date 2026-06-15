# Remote LR 開発活動 レビュー（Phase 1 / M1F 完了時点）

> **レビュー日:** 2026-06-14
> **対象 plugin 差分:** `feature/1025-remote-lockable-resources-p1-m1e`（`5d956de`）..`feature/1025-remote-lockable-resources-p1-m1f`（HEAD: `6319f12`）
>   の **M1F デルタ**（4 ファイル / +109・-2）。M1F は M1E ベースの整理サイクルのため、レビューも **M1E→M1F の差分**を一次対象とする
>   （`master` 全面差分は `LRR_REVIEW_P1_M1E.md` でカバー済み。M1F はそこに新規コードを足さず、M1E 指摘の選別対応のみ）。
> **対象ドキュメント:** `dev/docs-j/`（LRR_DESIGN_P1_M1F / LRR_IMPLEMENTATION_STEPS_P1_M1F / LRR_RESULT_P1_M1F）、
>   `LRR_REVIEW_P1_M1E.md`（指摘元・M1F 対応バナー）
> **観点:** M1F の中核目標「**M1E 指摘を『lock() 既存ロジックに乗り、ネットワークブリッジ由来以外の remote 独自判定を増やさない』
>   観点で選別**」が忠実に守られているか／実施 3 点（L-b/L-c/L-d）が **HTTP 境界に閉じ・fail-open を増やさず・canonical 委譲と
>   透過等価の意味論に無干渉**か／残置 5 点（M1E-1/M1E-2/M1E-3/L-a/L-e）が再議論防止のため適切に明文化されたか／新規リグレッションの有無。
> **方法:** `6319f12` の差分とコードを静的精読。テスト件数（382）/ E2E（20/20）は記録レポートの実在を確認した
>   （`dev/reports/20260614104134-mvn-test.log` = `Tests run: 382, Failures: 0, Errors: 0, Skipped: 1` / `BUILD SUCCESS`、
>   `dev/reports/20260614105955-e2e-test.md` = pass:20 / fail:0、作業ツリーは `6319f12` でクリーン）。

---

## 目次

1. [総評](#1-総評)
2. [観点遵守の確認 — 選別は正しく守られたか](#2-観点遵守の確認--選別は正しく守られたか)
3. [実施 3 点の妥当性](#3-実施-3-点の妥当性)
   - [L-b（url スキーム検証）](#l-b)
   - [L-c（POST ボディ上限）](#l-c)
   - [L-d（FAILED→4xx 写像）](#l-d)
4. [指摘事項（すべて Low / nit）](#4-指摘事項すべて-low--nit)
5. [残置懸念の扱いの評価](#5-残置懸念の扱いの評価)
6. [テスト / 検証層の評価](#6-テスト--検証層の評価)
7. [推奨アクション（優先順）](#7-推奨アクション優先順)

---

## 1. 総評

**M1F は「設計で宣言した観点をコードが裏切っていない」ことが確認できる、模範的な整理サイクルである。** 機能追加ではなく
M1E レビュー指摘の選別対応に徹し、実施したのは HTTP トランスポート/境界層の堅牢化 3 点（L-b/L-c/L-d）のみ。いずれも
**lock() の意味論・canonical 委譲・透過等価・公開（exposeLabel）ポリシーに一切触れていない**。残置と決めた 5 点は設計 §4 に
「再議論防止」として明文化され、M1E レビュー本体にも対応バナーが追記されている。

- 差分は **+109・-2 / 4 ファイル**（うち 2 がテスト）と最小。新規 public API・新規状態・新規 remote 判定の追加はゼロ。
- **fail-open を一切増やしていない。** 3 点はいずれも「より厳しく弾く（reject を増やす）」方向の変更で、誤ったロック付与に
  つながる経路を生まない。L-d はむしろ未来の FAILED が 202 成功へ漏れる穴を**塞ぐ**防御。
- ビルド 382/0/1skip・E2E 20/20 を実在レポートで確認。**新規 E2E を足さず既存 20/20 の回帰維持**という方針は、変更が
  HTTP 境界に閉じユニットで直接カバーできる本件では妥当。

**結論: 本スコープにおいて PR 品質に到達している。ブロッカーなし。** 以下の指摘はいずれも Low / nit で、マージ判断を妨げない。

---

## 2. 観点遵守の確認 — 選別は正しく守られたか

設計 §1 の観点「lock() 既存ロジックに乗り、ネットワークブリッジ由来以外の remote 独自判定を増やさない」に対し、
**コード上で観点違反（＝ブリッジ由来でない remote 独自判定の混入）が無いこと**を確認した。

| 実施項目 | 触れた層 | lock()/canonical/公開意味論への干渉 | 判定 |
|---|---|---|---|
| L-b | `RemoteConnection.validate()` ＝ 設定永続前の入口（トランスポート設定値） | なし（URL は HTTP transport 専用。lock 判定に不参加） | 観点準拠 |
| L-c | `parseJsonBody`（HTTP リクエストボディ読み取り） | なし（パース前の I/O 境界） | 観点準拠 |
| L-d | POST ハンドラの HTTP ステータス写像（`enqueue` の戻りは変えない） | なし（`enqueue` の判定結果をそのまま 4xx に写すだけ） | 観点準拠 |

3 点とも「`enqueue`/`lock()` が出した結論を変えず、その手前（設定入口）か後ろ（HTTP 応答写像）でのみ作用」しており、
remote 独自の許否判定を新設していない。**選別はコードレベルで守られている。**

---

## 3. 実施 3 点の妥当性

<a id="l-b"></a>
### L-b — remote base URL のスキーム検証（`RemoteConnection`）

- `validate()` に `isHttpUrl` 検査を追加。非 http(s)（`file:` / `ftp:` / スキーム無し）を `IllegalArgumentException` で拒否。
  **`validate()` は `LockableResourcesManager.setRemotes()` から呼ばれる永続前の唯一のゲート**であることを確認
  （[LockableResourcesManager.java:332](../../lockable-resources-plugin/src/main/java/org/jenkins/plugins/lockableresources/LockableResourcesManager.java#L332)。
  フォーム `configure` 経由・CasC 経由の両方がここを通る）。設計 §3-1 の「実質強制点」という記述は正確。
- `DescriptorImpl` を `@Extension` 化し `doCheckUrl`（`FormValidation`）を追加。
  **検証メモ:** 親フォームは `<f:repeatable field="remotes">` 内で `<st:include class="…RemoteConnection" page="config.jelly"/>`
  により jelly を直接 include しているため（`LockableResourcesManager/config.jelly:51-53`）、`@Extension` 未登録だった M1E 以前でも
  **フォーム描画自体は壊れていなかった**。一方、`url` フィールドの `doCheckUrl` 自動配線、および config.jelly が参照する
  `/descriptor/…RemoteConnection/help-*` ヘルプリンクの解決には descriptor 登録が前提。よって `@Extension` 追加は
  **doCheckUrl を機能させ、併せてヘルプリンクの 404 を解消する net-positive** な変更（既存挙動を退行させない）。
- ヘルパ `isHttpUrl` は trim ＋ `Locale.ENGLISH` 小文字化で prefix 判定。ロケール指定があり turkish-i 問題を回避していて良い。

**妥当。** fail-open を増やさず、ローカル設定の誤りを lock() 実行時の不透明な失敗ではなく設定時点で弾く。設計 §3-1 の
「到達性・FQDN・ポートは検証しない」という非該当境界も明示されており、過剰検証に踏み込んでいない。

<a id="l-c"></a>
### L-c — POST ボディサイズ上限（`RemoteApiV1Action`）

- `MAX_BODY_CHARS = 1 MiB` を導入し、`parseJsonBody` の読み取りループで累積文字数が上限超過した時点で
  `PayloadTooLargeException`（private、`IOException` サブクラス）を投げる。`sb.append` の**前**に判定するため、
  バッファが上限を超えて伸びることはない。POST ハンドラは `PayloadTooLargeException` を **`Exception` より先に catch**して
  413 `PAYLOAD_TOO_LARGE` にマップ（既存の不正 JSON 経路 400 `INVALID_JSON` は維持）。catch 順序も正しい。
- **検証メモ:** `parseJsonBody` の呼び出しは `RemoteApiV1Action` 内で **1 箇所（POST `/acquire`、line 84）のみ**。
  release/heartbeat はボディを読まず lockId を URL パスで運ぶ（`RemoteApiClient` の `URLEncoder.encode(lockId, …)` 経路）ため、
  **ボディを読む唯一の終端を上限が覆っている**。穴は無い。
- `total` は `int` だが 1 MiB+1 で即 throw するため int オーバーフロー（~2 GiB）には到達しない。安全。

**妥当。** 認証済みクライアントでも巨大ボディで OOM を誘発し得る点を、パース前の I/O 境界で閉じている。観点（トランスポート堅牢化）に合致。

<a id="l-d"></a>
### L-d — POST の FAILED → 4xx 写像一般化（`RemoteApiV1Action`）

- 変更前は `UNKNOWN_RESOURCE`/`UNKNOWN_LABEL` のみ 404 で `return` し、**それ以外の `FAILED` は下の 202 成功応答へフォールスルー**していた。
  変更後は `else` で 400（`errorCode` 優先、無ければ `ACQUIRE_FAILED`）を返し、`return;` を if/else の外に出して**全 FAILED が必ず終端**する。
  ロジックは正しく、202 漏れ経路を確実に塞ぐ。
- 設計 §3-3 の「現状 `enqueue` の非 `UNKNOWN_*` な FAILED は `MISSING_TARGET` のみで、境界の MISSING_TARGET チェックで到達不能」
  という防御的位置づけは、コード上も整合（既存 404 テストが緑のまま＝現行観測挙動を変えない）。

**妥当。** 「現状到達不能だが将来コードに堅い」防御変更として価値があり、リスクはゼロ（到達不能経路の写像を厳しくするだけ）。

---

## 4. 指摘事項（すべて Low / nit）

> いずれもマージを妨げない。記録目的。今サイクルで対処してもよいし、後送りでも実害は無い。

- **F-1（nit / Low）`isHttpUrl` と `resolve()` の whitespace 正規化が非対称。**
  `isHttpUrl` は `value.trim()` してから prefix 判定するため `"  http://x  "` は `validate()` を**通過**するが、
  保存される `url` はトリムされない生値（`@DataBoundConstructor` がそのまま格納）。送信時の
  `RemoteApiClient.resolve()`（[RemoteApiClient.java:286-304](../../lockable-resources-plugin/src/main/java/org/jenkins/plugins/lockableresources/remote/RemoteApiClient.java#L286-L304)）は
  空判定にだけ `trim()` を使い、`URI.create` には生値を渡すため、前後空白付き URL は `URI.create` で
  `IllegalArgumentException`→`INVALID_CONFIGURATION` になり得る。**fail-open ではない**（lock 時に弾かれるだけ）が、
  「設定時に OK と言ったのに実行時に設定エラー」という不一致が残る。対処するなら `validate()` 通過時に
  トリム済み値を正規化保存するか、`resolve()` 側で `trim()` を効かせると一貫する。低優先。
- **F-2（nit / Low）L-d の空文字 errorCode。**
  `ec != null ? ec : "ACQUIRE_FAILED"` は `ec` が空文字 `""` の場合に**空の errorCode をそのまま応答に載せる**。
  現状 `FAILED` レコードは常に非空コードを設定するため実害は無いが、防御変更の趣旨に合わせるなら
  `Util.fixEmpty(ec)` 相当で空も `ACQUIRE_FAILED` に倒すとより堅い。低優先。
- **F-3（観察 / 軽微）L-c は文字数上限でありバイト上限ではない。**
  OOM 防止（ヒープ占有の上限）目的としては文字数で正しく、意図的。ただしマルチバイトボディの実バイト数は 1 MiB を
  多少超え得る点は仕様として認識しておけば十分（攻撃面の問題ではない）。記録のみ、対処不要。

---

## 5. 残置懸念の扱いの評価

設計 §4 の「意図的に残置する懸念」5 点（M1E-1 / M1E-2 / M1E-3 / L-a / L-e）について、**残置という判断自体が観点と整合し、
かつ再議論防止の明文化が十分**であることを確認した。

- **M1E-1（昇格経路の `fromNames(create=true)` ephemeral 再生成）** の残置は、観点（remote だけ `create=false` にする＝
  ブリッジ由来でない独自判定の追加）に照らして一貫。発火条件が狭い（exposed・busy・QUEUED 中の admin 削除）・**非 fail-open**
  （誤ロックは付与されない）・孤児は名前あたり 1 個に収束、という受容根拠も妥当。将来観点を変える場合の具体策（canonical シームに
  `create` フラグを一段通す）まで設計 §4 に書かれており、再着手の足場も残っている。**「直さない」とユーザー確定済みである点が
  メモリ [[remote-lock-project-state]] とも一致。**
- M1E-2 / M1E-3 / L-a / L-e も区分（local 由来・設計上・無害・性能のみ）と残置理由が明記され、観点と矛盾しない。

> 注意点（次サイクルへの申し送り）: M1E-1 は **意図的残置であって「解決済み」ではない**。多テナント化や昇格経路の admission 再検証が
> P1+ で俎上に載る際は、設計 §4 の `create` フラグ案を起点に再開すること。本レビューはこれを**未解決の既知課題として再確認**する。

---

## 6. テスト / 検証層の評価

- **L-b: 3 件追加で十分。** `testValidateAcceptsHttpsUrl`（受理）、`testValidateRejectsNonHttpUrl`（`file:`/`ftp:`/スキーム無しを拒否）、
  `testDoCheckUrl`（http/https=OK、file/空/null=ERROR）。受理側・拒否側・UI 側を網羅。[[rlr-equivalence-test-defaults]] の
  「空/null を突く」教訓にも沿う（`doCheckUrl(null)`/`("")` を明示的にカバー）。
- **L-c: 1 件（`acquireWithOversizedBodyReturns413`）。** 1 MiB 超ボディ → 413 を直接検証。境界ちょうど（=MAX_BODY_CHARS）での
  挙動テストは無いが、`> MAX_BODY_CHARS` の境界条件はコード上明快で、過剰テストは不要と判断。許容。
- **L-d: 直接の positive テストは無いが、これは正当。** 一般化した `else`（非 `UNKNOWN_*` の 400）分岐は設計どおり
  **現状 `enqueue` から到達不能**なため、テストで踏ませる seam が無い。既存の `UNKNOWN_RESOURCE`/`UNKNOWN_LABEL` 404 テストが
  if 側を回帰カバーし、`return` 位置の変更が 404 経路を壊していないことを保証している。防御変更としては妥当なカバレッジ。
- E2E は方針どおり新規追加なし・既存 20/20 回帰維持。HTTP 境界の変更はユニットで直接カバー済みのため整合。

---

## 7. 推奨アクション（優先順）

1. **（任意・今サイクルでも可）F-1 の whitespace 非対称を解消。** `validate()` 通過時にトリム正規化して保存するか、
   `resolve()` で `trim()` を効かせる。1 行で「設定 OK＝実行 OK」の一貫性が取れる。低コスト・低リスク。
2. **（任意）F-2 の空文字 errorCode を `ACQUIRE_FAILED` に倒す**（防御変更の趣旨を最後まで通すなら）。
3. **次サイクルへの申し送り（必須・記録のみ）:** M1E-1 は**意図的残置の既知課題**として継続管理。P1+ で昇格経路 admission 再検証や
   多テナント化に着手する際は設計 §4 の `create` フラグ案から再開する（[[remote-lock-project-state]] に登録済み）。
4. それ以外（M1E-2 / M1E-3 / L-a / L-e）は設計 §4 の判断どおり後送りで問題なし。

> **総括:** M1F は「レビュー指摘を闇雲に潰さず、ユーザー確定の一本の観点で選別し、実施分は HTTP 境界に閉じ、残置分は
> 再議論防止まで明文化する」という、**整理サイクルとして理想的な進め方**を実行できている。実施 3 点はいずれも fail-open を
> 増やさず canonical を汚さず、テストとビルド/E2E の裏付けもある。指摘は Low / nit のみで、**本スコープでは PR 品質。**
> 唯一の留意は M1E-1 が「解決」ではなく「意図的残置の既知課題」である点で、これは設計とメモリに正しく記録されている。

---

## 更新履歴

- 2026-06-14: 初版作成。M1E(`5d956de`)..M1F(`6319f12`) デルタ（4 ファイル / +109・-2）を静的精読。
  実施 3 点（L-b url スキーム検証 / L-c ボディ上限 413 / L-d FAILED→4xx）が観点「ブリッジ堅牢化のみ・remote 独自判定を増やさない」を
  コードレベルで遵守し、fail-open を増やさず canonical 委譲・透過等価に無干渉であることを確認。`@Extension` 追加は doCheckUrl 配線と
  descriptor ヘルプリンク解決の net-positive（既存描画は `st:include` のため退行なし）と評価。L-c の上限は唯一のボディ読み取り終端
  （POST /acquire）を覆うことを確認。指摘は F-1（isHttpUrl と resolve の whitespace 非対称・Low）/ F-2（L-d 空文字 errorCode・nit）/
  F-3（文字数 vs バイト上限・観察）の Low/nit のみ。残置 5 点は設計 §4 の明文化が十分と評価し、M1E-1 を「意図的残置の既知課題」として再確認。
  ビルド 382/0/1skip・E2E 20/20 をレポート実在で確認。本スコープで PR 品質と判定。
