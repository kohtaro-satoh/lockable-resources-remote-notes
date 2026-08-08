# Remote LR 設計（Phase 1 / M2 + M3 統合 ＋ M1 やり残し取り込み）

> **位置づけ:** PR [#1055](https://github.com/jenkinsci/lockable-resources-plugin/pull/1055)（Phase 1 / M1）が
> `master` にマージされた地点を**起点**として作る次 PR の設計。
> issue [#1025](https://github.com/jenkinsci/lockable-resources-plugin/issues/1025) の
> **Phase 1 M2 と M3 を 1 本に統合**し、あわせて **M1 のやり残し**を回収する。
> **作成日:** 2026-07-26 / **最終更新:** 2026-08-05
> **前提コミット:** #1055 は **2026-08-04 に `jenkinsci:master` へマージ済み**（マージコミット `018e913`、
> merged by mPokornyETM）。本書の実装側記述は `upstream/master` = `011c6a3`（`018e913` を含む）で確認済み
> **正本仕様:** issue #1025 本文の "Configuration surface" 〜 "Phase 1 scope"（authoritative）
> **関連:** `../ph1-ms1/LRR_DESIGN_P1_M1.md`（M1 設計。§4 に本書が埋める API が「M3 以降」として予告済み）、
> `../ph1-ms1/LRR_REVIEW_UPSTREAM_FOLLOWUP_UX.md` §13.3（やり残しの一覧と行き先）

---

## 目次

1. [目的とスコープ](#1-目的とスコープ)
2. [現状ギャップ（仕様 vs 実装）](#2-現状ギャップ仕様-vs-実装)
3. [設計 A: サーバ側の追加分](#3-設計-a-サーバ側の追加分)
4. [設計 B: クライアント側 LR ページ](#4-設計-b-クライアント側-lr-ページ)
5. [設計 C: delegated mode の表示切替（M2 本体）](#5-設計-c-delegated-mode-の表示切替m2-本体)
6. [M1 やり残しの取り込み](#6-m1-やり残しの取り込み)
7. [仕様と実装の乖離をどう扱うか](#7-仕様と実装の乖離をどう扱うか)
8. [含まないもの](#8-含まないもの)
9. [テスト方針](#9-テスト方針)
10. [未決事項（実装前に決める）](#10-未決事項実装前に決める)
11. [更新履歴](#11-更新履歴)

---

## 1. 目的とスコープ

### 1.1 なぜ M2 と M3 を 1 本にするか

issue #1025 のマイルストーン定義は次のとおり。

```
Phase 1 — Remote lock via REST + transparent DSL + remote resource list view
  M1: Core REST API + explicit lock(..., serverId: 'X')   ← #1055 で完了
  M2: forcedServerId resolution and the LR page mode-switching behavior
  M3: GET /resources and the client-side LR page integration with the remote view
```

**M2 の DSL 部分（`forcedServerId` による delegated ルーティング）は M1 で先食い実装済み**であり、
E2E `delegated-mode`（S09）で回帰も張ってある。M2 に残っているのは
**「LR ページのモード切替表示」だけ**で、これは `GET /resources`（M3）が無いと実装できない。

→ **M2 の残りと M3 は不可分**。分割すると「動かない中間状態の PR」を 1 本挟むことになるため、統合する。

### 1.2 スコープ

| 区分 | 内容 |
|---|---|
| **A. サーバ側 API** | **`GET /resources` の 1 本のみ**（2026-08-05 に縮小）。初版は `GET /lease/{lockId}` と `POST /acquire/{lockId}/cancel` も対象にしていたが、M1 設計書で前者は「M1 後の拡張候補」、後者は「廃止（release に統合）」と決定済みであり、未実装分ではなかった（[§3.2](#32-get-leaselockid-は追加しない2026-08-05-決定) / [§3.3](#33-release-の-queued-経路と-cancel-の扱い)）。あわせて **Martin 氏要望のメンテナンススイッチを Phase 1 に前倒し**（[§3.4](#34-メンテナンススイッチ-accept-new-acquires-onoff)） |
| **B. クライアント側 LR ページ** | 発信側コントローラで「自分が保持中／待機中の remote ロック」を可視化。PR #1055 が Known limitation として明記した最大の UX ギャップ |
| **C. delegated mode の表示切替** | `forcedServerId` 設定時に LR ページが**ローカル資源と並べて**リモートの公開資源を表示し、delegated バッジを出す（[§5.0](#50-置き換えから並存へ方針変更) で「置き換え」から方針変更） |
| **D. M1 やり残し** | [§6](#6-m1-やり残しの取り込み)。独立 PR を立てず本 PR に相乗り |

これで **Phase 1 は「issue 本文の Phase 1 scope をすべて満たした」と宣言できる状態**になる。

### 1.3 Phase 1 チェックボックスを checked にする条件

issue #1025 本文末尾の Phases 節にある `- [ ] Phase 1` は、**#1055 マージ後もまだ checked にできない**。
2026-08-05 時点の判定は次のとおり。

| 本文の項目 | 判定 | 根拠 |
|---|---|---|
| M1: Core REST API + 明示 `serverId` | ✅ | #1055 |
| M2: `forcedServerId` resolution **and the LR page mode-switching behavior** | ⚠️ 半分 | 解決ロジックのみ。LR ページ側は未実装（本書 [§5](#5-設計-c-delegated-mode-の表示切替m2-本体)） |
| M3: `GET /resources` + client-side LR page integration | ❌ | 未着手（本書 [§3.1](#31-get-resources) / [§4](#4-設計-b-クライアント側-lr-ページ)） |
| Phase 1 scope "LR page integration on **both** sides" | ⚠️ 半分 | サーバ側のみ実装済み |

→ **本書の A〜C を実装した時点で checked にできる**。逆に言えば、Phase 1 完了宣言はこの PR が唯一の残作業。

> **呼称の注意:** 本書の作業を過去メモや PR #1055 のコメントで「Phase 2」と呼んでいた箇所があるが、
> issue 本文の定義では **Phase 1 の M2＋M3**。本文の Phase 2 は運用系
> （maintenance switch / polling 値の設定化 / client allow-list、本書 [§8](#8-含まないもの)）を指す。
> 対外的な記述では「remaining Phase 1 work (M2+M3)」と書く。

---

## 2. 現状ギャップ（仕様 vs 実装）

#1055 マージ後の `master` を起点としたときの差分。**本書の設計対象は「未」の行**。

### 2.1 REST エンドポイント

| 仕様（#1025） | 実装 | 備考 |
|---|---|---|
| `POST /acquire` | ✅ | `heartbeatIntervalSeconds` は受理するが無視（意図的、[§7.2](#72-heartbeatintervalseconds-を無視している)） |
| `GET /acquire/{lockId}` | ✅ | 返す状態は `RemoteLockState`。`CANCELLED` / `EXPIRED` は返らない |
| `POST /acquire/{lockId}/cancel` | — | **追加しない。** M1 で廃止（release に統合）済み [§3.3](#33-release-の-queued-経路と-cancel-の扱い) |
| `GET /lease/{lockId}` | — | **追加しない。** M1 で「M1 後の拡張候補」と決定済み [§3.2](#32-get-leaselockid-は追加しない2026-08-05-決定) |
| `POST /lease/{lockId}/heartbeat` | ✅ | |
| `POST /lease/{lockId}/release` | ⚠️ | QUEUED に対しては「即 terminal 化して record ごと削除」→ 直後の GET が 404。**TTL 保持に修正**（[§3.3](#33-release-の-queued-経路と-cancel-の扱い)） |
| `GET /resources` | **未** | [§3.1](#31-get-resources) |
| *(仕様外)* メンテナンススイッチ | **未** | 氏の要望を Phase 1 に前倒し [§3.4](#34-メンテナンススイッチ-accept-new-acquires-onoff) |

`RemoteApiV1Action#getDynamic` の分岐は現状 `acquire` / `lease` の 2 つのみ。`resources` の追加が必要。

> **表記について:** 上表は実装の呼称（`lockId`）に合わせている。issue 本文は acquire 側を `requestId`、
> lease 側を `leaseId` と**別 ID として**書いているが、実装は 1 本の `lockId` に統一済み
> （[§7.5](#75-requestid--leaseid-を-lockid-に一本化した)）。

### 2.2 設定・UI

| 仕様（#1025） | 実装 | 備考 |
|---|---|---|
| `remoteApiEnabled` / `exposeLabel`（サーバ側） | ✅ | `exposeLabel` は**複数ラベル OR** に拡張済み（M1E、[§7.1](#71-exposelabel-を複数ラベルに拡張した)） |
| `remotes[]` / `forcedServerId`（クライアント側） | ✅ | `forcedServerId` の存在検証も実装済み |
| `forcedServerId` による delegated ルーティング | ✅ | M1 で先食い（E2E S09） |
| **サーバ側** LR ページに remote lease の clientId 表示 | ✅ | M1B Step6＋氏の follow-up で Held By 列も表示 |
| **クライアント側** LR ページの remote ビュー | **未** | [§4](#4-設計-b-クライアント側-lr-ページ) |
| **delegated mode バッジ** | **未** | [§5](#5-設計-c-delegated-mode-の表示切替m2-本体) |

---

## 3. 設計 A: サーバ側の追加分

新設するエンドポイントは **`GET /resources` の 1 本だけ**（`RemoteApiV1Action#getDynamic` に
`resources` 分岐を足す）。**認可・有効化ゲートは既存 4 本と完全に同型**にする
（`Jenkins.get().checkPermission(REMOTE)` → `isRemoteApiEnabled()` チェック → 本体）。
これに加えて `release` の QUEUED 経路の修正（[§3.3](#33-release-の-queued-経路と-cancel-の扱い)）と
メンテナンススイッチ（[§3.4](#34-メンテナンススイッチ-accept-new-acquires-onoff)）がサーバ側の作業になる。

### 3.1 `GET /resources`

公開中のリソース一覧と、**サーバ側の受付状態**を 1 回のスナップショットで返す。

```jsonc
// GET /lockable-resources/remote/v1/resources  -> 200
{
  "acceptNewAcquires": false,          // メンテナンススイッチ（§3.4）の状態
  "resources": [
    { "name": "plc-01", "labels": ["plc", "remote-enabled"], "description": "PLC 01",
      "state": "LOCKED", "heldByKind": "REMOTE_CLIENT", "heldByClientId": "jenkins-c",
      "since": 1785026807000, "queuedCount": 2 },
    { "name": "plc-02", "labels": ["plc", "remote-enabled"], "description": "",
      "state": "FREE" }
  ]
}
```

#### 状態を返す（2026-08-08 に方針変更）

初版および issue 本文は「**状態は含めない**（安価・キャッシュ可能に保つ）」としていたが、**撤回する**。
クライアント側 LR ページで **local と remote のリソースを同程度の情報量で並べたい**（[§5.1](#51-表示の切り替え)）ため、
状態なしでは片方だけ情報が薄い表になってしまう。

`state` はローカルの Resources タブと同じ 4 値: **`FREE` / `LOCKED` / `RESERVED` / `QUEUED`**
（`table.properties` の `resource.status.*` と対応。`QUEUED` = 誰かが待っている）。

**開示レベルは中間案を採る（2026-08-08 決定）。** ローカル表の `Held By` 列の実体は
**そのサーバのビルド名**（`job/foo #12`）であり、`Reason` と `note` は自由記述。これらを返すと
**B のジョブ名が A の LR ページ閲覧者全員に見える**ことになる。B の管理者が opt-in したのは
「リソースの公開」であって「ジョブ名の公開」ではなく、`RemoteUse` 権限は B 全体の READ とも別物。
したがって **識別子は出さず、保持者の「種別」と経過時間だけ**を返す。

| フィールド | 内容 |
|---|---|
| `state` | `FREE` / `LOCKED` / `RESERVED` / `QUEUED` |
| `heldByKind` | `LOCAL_BUILD` / `REMOTE_CLIENT` / `ADMIN`（`RESERVED` 時）。`FREE` では省略 |
| `heldByClientId` | `heldByKind = REMOTE_CLIENT` のときのみ。**remote クライアント名であり B のジョブ名ではない**。A は自分の `clientId` と突き合わせて「これは自分のロック」と判別できる |
| `since` | 取得/予約時刻（epoch ms）。数値なので開示リスクが無く、体感の情報量を大きく上げる |
| `queuedCount` | 待機件数（0 のときは省略可） |

**返さないもの:** ビルド名 / ビルド URL / `reason` / `note`。将来必要になったら、B 側に
「詳細も公開する」オプトインを足す形で別途検討する。

#### `acceptNewAcquires` を同じレスポンスに載せる理由

メンテナンス中は「リソースは見えるが lock はできない」と画面で示したい（[§3.4](#34-メンテナンススイッチ-accept-new-acquires-onoff)）。
別エンドポイントに分けると **2 つのキャッシュが食い違い**、「FREE と表示しているのに実は受付停止中」という
不整合な画面が作れてしまう。1 回のスナップショットで両方返せば、画面は必ず整合した組み合わせを描ける。
エンドポイント名を `resources` のままにするのも、封筒にサーバ側メタデータを載せる一般的な形として問題ない。

> **重要:** メンテ中でも**リソースの状態はそのまま真実を返す**（FREE は FREE）。
> 「FREE だが今は取得できない」は**画面側の表現**で伝える。データを曲げないことで、
> `acceptNewAcquires` を無視するクライアントでも状態表示だけは正しく保たれる。

#### その他

- **公開フィルタは既存の `getExposeLabels()` を再利用**する。新しい remote 独自判定を足さない
  （M1F の観点「ブリッジ由来でない remote 独自判定を増やさない」を維持）
- `remoteApiEnabled=false` のときは既存 4 本と**完全に同型**、すなわち
  **403 `REMOTE_API_DISABLED`** を返す。issue 本文は「API が存在しないかのように応答（＝404）」と
  書いているが、実装は M1 の時点で 403 を選んでいる。**ここで 404 にすると同一 API 内で挙動が割れる**ため、
  実装の 403 に揃え、issue 本文側を直す（[§7.7](#77-remoteapienabledfalse-時の応答が-403-になっている)）
- ページングは持たない（小〜中規模前提。数千件になる想定なら Phase 3）

#### 「単一の真実」原則との整合

状態を返さない元の理由は「クライアントがそれをロック判断に使う誘惑が生まれる」だった。これは
**将来のドリフト防止**の話であり、Phase 1 のクライアントは可用性判断を一切せず POST するだけなので、
判断経路そのものが存在しない。担保は 2 つ: (1) 表示専用である旨をコード側コメントと
「client-side cached view」表示で明示する、(2) **状態を消費する判断コードを作らない**ことを
レビュー観点として残す。

### 3.2 `GET /lease/{lockId}` は追加しない（2026-08-05 決定）

初版では「issue 本文に載っている未実装分」として追加対象にしていたが、**これは誤りだった**。
M1 設計書 `../ph1-ms1/LRR_DESIGN_P1_M1.md` の対象外表に
「`GET /lease/{lockId}`（診断エンドポイント） — **M1 後の拡張候補**」と既に記録されている。

追加しない理由:

1. M1 の時点で「後回し」と判断済み（実装漏れではない）
2. **同じ `lockId` で `GET /acquire/{lockId}` が引ける**ため、保持中の状態確認（`ACQUIRED` / `STALE`）は既に可能。
   返らないのは `clientId` / `acquiredAt` / `lastHeartbeatAt` / heartbeat・stale 値だけで、いずれもサーバ側 LR ページに出ている
3. クライアント側 LR ページは自前レジストリ（[§4.2](#42-データ源をどう持つか)）でデータを持つ設計なので、**この endpoint に依存しない**

**将来の導入時期:** heartbeat / poll / timeout の設定化と同時。値が設定可能になって初めて
「実効値を読み戻す手段」が実質的に必要になる。その時に [§10](#10-未決事項実装前に決める) Q3（申告値を併記するか）も再検討する。

### 3.3 `release` の QUEUED 経路と `cancel` の扱い

**`POST /acquire/{lockId}/cancel` は追加しない（2026-08-05 決定）。**
M1 設計書に「**cancel エンドポイント廃止**、abort・正常完了いずれも `POST /lease/{lockId}/release` に統合。
サーバー側・管理者操作による `CANCELLED` 状態は互換性のため受け取れるが、クライアントからは発行しない」と
明記されており、初版で「未実装」に分類したのは誤りだった。実装上も `RemoteLockManager#release()` は
QUEUED レコードに対して動作するため、**キャンセルは既に release で実現されている**。

**ただし実害が 1 つ残るので、それだけ直す。** 現在の `release()` は QUEUED に対して
`markFailed("RELEASED")` した直後に `records.remove()` するため、**record ごと消えて直後の
`GET /acquire/{lockId}` が 404 になる**。abort 直後に別経路が poll すると、
[§6-1](#6-m1-やり残しの取り込み) と同じ「404 が実態を表さない」問題を踏む。

| | 現状 | 修正後 |
|---|---|---|
| 状態遷移 | `FAILED("RELEASED")` → **即 record 削除** | `FAILED("RELEASED")` のまま **terminal TTL（120s）保持** |
| 直後の `GET /acquire/{lockId}` | **404 LOCK_NOT_FOUND** | **200 `state=FAILED, errorCode=RELEASED`** |

**設計判断:** 新状態 `CANCELLED` は**追加しない**。`RemoteLockState` は現行の
QUEUED/ACQUIRED/SKIPPED/FAILED/STALE のままとし、`records.remove()` を terminal TTL 掃引に一本化するだけにとどめる。
M1 の「クライアントからは `CANCELLED` を発行しない」方針と整合し、変更範囲も最小になる
（`RemoteAcquireState.CANCELLED` と `RemoteLockSession` の `case CANCELLED` は
「サーバ側・管理者操作による将来のキャンセル」への互換として、そのまま残す）。

### 3.4 メンテナンススイッチ "accept new acquires: ON/OFF"

**Phase 2 候補から Phase 1 に前倒し**（2026-08-05）。Martin 氏が
[#1025 のこのコメント](https://github.com/jenkinsci/lockable-resources-plugin/issues/1025#issuecomment-4365352278) §8 で
要望していたもので、実装量が小さいこと・氏の要望であることから同梱する。

**サーバ側:** `acceptNewAcquires`（`boolean`、既定 `true`）を `LockableResourcesManager` に追加。
`remoteApiEnabled` と同じ型で config.jelly ＋ help ＋ Messages ＋ JCasC を用意する。
OFF のとき **`POST /acquire` だけが 503 `ACQUIRES_PAUSED`** を返し、
`GET /acquire/{lockId}` / heartbeat / release は素通し（＝進行中のリースは無傷）。
サーバ側 LR ページに一時停止バナーを出す（管理者が戻し忘れないように）。

**未確定（氏には未質問。作り込んでから PR で提示する。[§9.4](#94-新旧並走の視覚比較pr-スクショ用) 参照）:**

| # | 論点 | こちらの提案 |
|---|---|---|
| a | クライアントが 503 を受けたときの挙動 | **リトライ**。現状は `POST /acquire` 失敗＝fail-closed で即 abort だが、それでは「B のメンテ中に A が困らない」という要望の目的を満たさない。`timeoutForAllocateResource` の範囲内でポーリング間隔で再試行し、INFO を 1 回だけ出す |
| b | OFF 時に既にキューにある要求の扱い | **昇格を続ける**（受理済みの要求は履行し、キューが drain する）。凍結する案は待機中クライアントをタイムアウトまで宙吊りにする |

上記の提案で実装し、PR に「こう作ってみたがどうか」として提示する。相違があればそこで差し替える。

### 3.5 サーバ側の判定順序（Wire → Admission → Canonical）

`POST /acquire` が受け取った要求を、どの層がどの順で裁くか。**remote 固有の判定を最小限の 2 層に閉じ込め、
残りは canonical に丸投げする**のが狙い（2026-08-08 確定）。

| 順 | 段 | 判定内容 | 失敗時 | remote 固有か |
|---|---|---|---|---|
| 0 | 認可 | `checkPermission(REMOTE)` | **403** | —（Jenkins 標準） |
| 1 | 有効化 | `remoteApiEnabled` | **403** `REMOTE_API_DISABLED` | 固有 |
| 2 | 一時停止 | `acceptNewAcquires`（[§3.4](#34-メンテナンススイッチ-accept-new-acquires-onoff)） | **503** `ACQUIRES_PAUSED` | 固有 |
| 3 | **Wire** | JSON 妥当性・フィールド形・`heartbeatIntervalSeconds` | **400**／ボディ超過は **413** | 固有（ワイヤ形式） |
| 4 | **Admission** | 露出フィルタ＋名前の実在 | **404** 一律 | 固有（ブリッジ境界） |
| 5 | **Canonical** | `LockStepResource.validate()` に丸投げ | **400** `INVALID_REQUEST` | **固有判定を持たない** |

0・1 は全エンドポイント共通。2 は `POST /acquire` のみ（heartbeat / release / GET は素通し）。

**Admission の責務（宣言）:**

1. **露出フィルタ** — `exposeLabel` を持つ資源だけが remote から見える
2. **名前の実在** — 存在しない名前は即 404
3. **remote 由来の ephemeral を作らせない** — 1・2 の結果として、canonical の `create=true`（LRM:1586）に
   未知の名前が到達しない。即時取得パスでは admission と解決が**同一 `syncResources` ブロック内**にあるため
   （`RemoteLockManager.enqueue`）、この保証は厳密に成立する。
   **例外はキュー昇格パスのみ**で、これは [§8.1](#81-m1e-1孤児-ephemeral再検討の記録2026-08-08) の既知残置

**Canonical に丸投げする 5 チェック**（`LockStepResource.validate()`）: ターゲット未指定（`allowEmptyOrNullValues` 考慮）/
`priority != 0 && inversePrecedence` / `label` と `resource` の同時指定 / label の実在 / `resourceSelectStrategy` の妥当性。

**remote 側から消えるコード:** 現在の境界にある `MISSING_TARGET` と `INVALID_SELECT_STRATEGY` の自前チェック。
**canonical の部分コピーであり、しかもズレている** —— `MISSING_TARGET` は `allowEmptyOrNullValues` を無視するため、
同設定が true のとき **local は受理する要求を remote は 400 で弾く**（既存の透過等価の破れ）。
丸投げに変えると remote 固有コードは差し引きで**減る**。

**これで変わる挙動（3 件）:**

| ケース | 現状 | 変更後 |
|---|---|---|
| `allowEmptyOrNullValues=true` かつターゲット未指定 | 400 `MISSING_TARGET` | **受理**（local と同じ）＝破れの修正 |
| `priority != 0 && inversePrecedence` | 受理 | **400**（[§10.1](#101-q4-の別解inverseprecedence-の透過等価)） |
| `resource` と `label` の同時指定 | 受理（M1E-2 残置） | **400**（local と同じ） |

**M1E-2 を閉じる判断:** 当時これを残したのは「閉じるには remote 固有の判定を足す必要がある」からだった。
本構成では**逆に remote 固有コードを減らすことで自動的に閉じる**ため、判断を支えていた前提が反転している。

**なぜ Admission を Canonical より前に置くか:** canonical は label の実在も検査するため、先に走らせると
**未知 label が 400・未公開 label が 404** となって存在が漏れる（M1E の「一律 404」が崩れる）。
Admission を先に置けば秘匿性は**無償で維持**され、canonical 丸投げも同時に達成できる。
なお秘匿性には診断性のコスト（404 が曖昧）が残るが、それを解消するなら
**未公開 = 403 `NOT_EXPOSED` / 未知 = 404** と明示的に分ける別論点として扱う。検証順序の副作用として漏らすのは筋が悪い。

**実装メモ:** `RemoteLockManager.enqueue` を admission → canonical の順にし、canonical の `IllegalArgumentException` は
**そのまま伝播**させる。`RemoteApiV1Action` が catch して 400 `INVALID_REQUEST` ＋ `ex.getMessage()`（record は作らない＝
現状の 400 群と同じ門前払い）。admission の 404 経路は record を作る現状のままで、M1F の L-d で入れた
「`UNKNOWN_*` は 404、それ以外の FAILED は 400」配線とも整合する。`extra` も canonical に乗せるなら
`RemoteLockRequest.ExtraResource` から `LockStepResource` を組んで list オーバーロードを呼ぶ
（`RemoteResolver.toRemoteStructs` が `LockStep.getResources()` を写しているのと同じ発想）。

**残る小論点:** errorCode の粒度。canonical に寄せると `INVALID_SELECT_STRATEGY` 等の細分コードが
`INVALID_REQUEST` 一本になる。機械可読な意味は errorCode、詳細は（ローカライズ済みの）message、という切り分けとし、
`remote-api-curl.md` のエラーコード表を更新する。メッセージからコードを逆マップするのは脆いので採らない。

---

## 4. 設計 B: クライアント側 LR ページ

### 4.1 何が無いのか

現在、**発信側コントローラには remote ロックの可視化が一切ない**。ビルドログを追う以外に
「今このコントローラがどのリモート資源を持っているか／待っているか」を知る手段がない。
所有側（サーバ側）のダッシュボードは M1B/M1 follow-up で充実しているのと対照的で、
PR #1055 も Known limitation として明記している。

### 4.2 データ源をどう持つか

remote ロックの client 側状態は `RemoteLockSession`（step ごと）にしか存在しない。
コントローラ横断で集約する仕組みが要る。

| 案 | 内容 | 評価 |
|---|---|---|
| **(a) 明示レジストリ**（推奨） | `RemoteClientRegistry`（`@Extension`, transient）を新設。`RemoteLockSession` が acquire 時に登録、release/失敗時に登録解除 | 待機中（QUEUED）も保持中（ACQUIRED）も表現できる。O(1) 参照。再起動時は `onResume` で再登録 |
| (b) 実行中ビルド走査 | 全 `Run` の `LockedResourcesBuildAction` を走査 | 新規状態を持たない一方、**待機中が取れない**（action は取得後に付く）。走査コストも高い |
| (c) サーバへ問い合わせ | 各 remote の `GET /resources` + lease 一覧 | サーバ側に「client 別 lease 一覧」API が無く、Phase 1 スコープ外 |

→ **(a) を採用**。`RemoteLockManager`（サーバ側）と対になる **client 側の軽量レジストリ**という位置づけ。

```
RemoteClientRegistry (transient, in-memory)
  key   : lockId
  value : serverId / 要求内容(resource|label+quantity) / state(QUEUED|ACQUIRED)
          / 取得済みリソース名 / enqueuedAt / acquiredAt / 発信ビルド(Run への参照)
```

- **永続化しない**。再起動時は `RemoteLockSession.onResume` から再登録する
  （`onResume` は QUEUED / ACQUIRED いずれの状態も持っているので再構築可能）
- ビルドが消えた場合に備え、`Run` は弱参照＋`getFullDisplayName()` のスナップショットを併せ持つ
  （M-1「onResume で displayTarget が劣化する」の解消もここで回収 → [§6-9](#6-m1-やり残しの取り込み)）

### 4.3 表示

LR ページに **「Remote locks」タブ**（または既存タブ内のセクション）を追加する。
PR [#1035](https://github.com/jenkinsci/lockable-resources-plugin/pull/1035) で導入された
タブ構成（Overview / Resources / Labels / Queue）に **1 つ足す**形が既存 UI と整合する。

| 列 | 内容 |
|---|---|
| Server | `serverId`（クライアント側エイリアス） |
| Request | `resource=…` / `label=… quantity=…` |
| State | QUEUED / ACQUIRED |
| Resources | 取得済みリソース名（ACQUIRED のみ） |
| Requested by | 発信ビルド（リンク） |
| Since | 経過時間 |

- **「これはクライアント側のキャッシュビューであり、リモートの権威状態ではない」**旨を
  タブ内に常時表示する（仕様の明示要件）
- 操作（cancel / release）はこの画面からは**出さない**。Phase 1 は可視化までとし、
  誤操作でパイプラインと状態がずれるリスクを避ける（[§10](#10-未決事項実装前に決める) Q2 で確定。
  なお cancel ボタンの発案元は当方のメモのみで、**外部への約束は無い**ことを #1025 / #1055 の全コメント検索で確認済み）

---

## 5. 設計 C: delegated mode の表示切替（M2 本体）

`forcedServerId` が設定されているとき、LR ページの意味論が変わる。仕様の要求は 3 点。

1. **delegated バッジ**を明示（管理者が解決意味論の変化に驚かないように）
2. **リモートの公開資源を表示**する（`GET /resources` の結果）
3. ~~**ローカル資源定義は「delegated mode では使われない」と示す**（隠すか、その旨を表示）~~
   → **方針変更（2026-08-05）: 隠さず並存させる。**下記 [§5.0](#50-置き換えから並存へ方針変更)

### 5.0 「置き換え」から「並存」へ（方針変更）

`4365352278` では delegated mode の LR ページを「リモートの公開資源**のみ**」にすると書いたが、
**表示だけ並存に改める**（解決ルールは変更しない）。理由は 2 つ。

1. **役割はインスタンス単位ではなく関係単位**（本文の "Mutual sharing via multiple independent
   one-way relations" 節）。`forcedServerId` を設定したコントローラでも `remoteApiEnabled` + `exposeLabel`
   があれば**自分の資源は他コントローラから普通にロックされる**。ローカル行を隠すと
   「他所が現に掴んでいる資源」が画面から消える。現行記述は delegated と server を実質排他にしており、
   設計全体の意図と矛盾している
2. **#1035 でページがタブ構成になった**ため、置き換えなくても曖昧さなく両方を出せる

`4365352278` が「置き換え」を選んだ本来の理由（名前衝突の排除、「リモートのつもりでローカルを掴む」事故の防止）は
**解決ルール側で担保され続ける**: delegated では全 `lock()` がリモートに行き、ローカル定義へのフォールバックは無く、
未知名は `UNKNOWN_RESOURCE` で即失敗する。UI では「その名前がどちらに解決されるか」を行単位で示して補う。

### 5.1 表示の切り替え

| モード | Resources タブ（ローカル資源） | Remote タブ |
|---|---|---|
| **peer**（`forcedServerId` 未設定） | 従来どおり | 自分が保持/待機中の remote ロック |
| **delegated**（`forcedServerId` 設定済み） | **従来どおり表示する**。ただし「このコントローラの `lock()` 解決には使われない（他コントローラからのロック対象としては現役）」と明示 | 上記＋ `forcedServerId` の公開資源（`GET /resources`） |

delegated mode ではページ上部に常時バッジを出す:

```
[ Delegated mode ] All lock() calls are routed to serverId = "b" (http://jenkins-b:8080/jenkins)
                   Local resources below are still lockable by other controllers.
```

### 5.2 `GET /resources` の短期キャッシュ

毎回のページ表示でリモートを叩かない。**TTL 付きの短期キャッシュ**（既定 **10s**）を client 側に持つ。

> **TTL 変更（2026-08-08）:** 初版は 60s だったが、[§3.1](#31-get-resources) で
> **状態と `acceptNewAcquires` を返すことにした**ため、60s は誤情報を見せる長さになった
> （1 分前の FREE を表示してしまう）。エンドポイントを「静的カタログ 60s ＋ 状態 5s」の 2 本に割る案は
> 「新設は 1 本だけ」という縮小方針に逆行し、キャッシュ不整合も生むため採らない。
> **1 本のまま TTL を 10s に短縮**する。リモート 1 台あたり 10 秒に 1 回で、ページ表示ごとではない。

- キャッシュミス時のみ HTTP。取得失敗時は**最後に取れた内容＋「stale（最終取得 N 分前）」表示**にフォールバック
  （fail-closed はロック取得の話であり、**表示は best-effort でよい**）
- リモート設定（`remotes` / `forcedServerId`）変更時はキャッシュを破棄
- 取得はページ表示のリクエストスレッドではなく**非同期**にし、UI をブロックしない

---

## 6. M1 やり残しの取り込み

`../ph1-ms1/LRR_REVIEW_UPSTREAM_FOLLOWUP_UX.md` §13.3 で「Phase 2 PR に相乗り」と決めたものを含む。

| # | 項目 | 出典 | 対応 |
|---|---|---|---|
| 1 | **`RemoteLockSession` の 404/410 ラベルのねじれ** | REVIEW_UPSTREAM §12.2 | **(a) 一本化**（[§10](#10-未決事項実装前に決める) Q1 で確定。当該分岐は全行が当方のコードで、他者コードへの手入れにならないことを blame で確認済み）。到達可能な `!bodyStarted` 側を「record が存在しない（サーバ再起動の可能性）」寄りの表現に改め、正当な allocate timeout はサーバ側 FAILED 経路に一本化済みである前提をコメントで明示。あわせて `release` の QUEUED 経路を terminal TTL 保持に直し（[§3.3](#33-release-の-queued-経路と-cancel-の扱い)）、**404 が出る条件そのものを減らす** |
| 2 | **docs `remote-api-curl.md` の状態表** | REVIEW_UPSTREAM §12-8 | `EXPIRED` の誤記を削除（サーバは返さない。`maxWaitSeconds` 導入時の将来枠と明記）、`STALE` を追記、`heartbeatIntervalSeconds` がサーバ側で無視される旨を注記。**`CANCELLED` は本 PR で実在するようになるので正式記載** |
| 3 | **Queue タブの Change Position ボタン** | REVIEW_UPSTREAM §12-3/4 | remote 行ではボタンを描画しない（JS で `item.type === "remote"` を除外）。位置検証の範囲もローカルキュー件数基準であることを明示 |
| 4 | **`X_SERVER_ID` / `X_LOCK_ID` の位置づけ** | REVIEW_UPSTREAM §12.1 | 「ブリッジ固有メタデータは透過等価の対象外」と設計書（本書 [§7.3](#73-x_server_id--x_lock_id-の非対称)）に明文化して**維持**する |
| 5 | **Queue の index 順序** | REVIEW_UPSTREAM §12-5 | local/remote をマージ後に priority 降順でソートしてから index を振る。実際の昇格順（`proceedNextContext`）と一致させる |
| 6 | **Queue のフリーテキスト filter** | REVIEW_UPSTREAM §12-6 | `filter` 分岐に `getRemoteRequest()` / `getRequestedBy()` を追加し、remote 行にも効くようにする |
| 7 | **`withRemoteMetadata` が空 `lockEnvVars` で落ちる** | REVIEW_UPSTREAM §12-7 | 条件の外に出し、`variable` 指定があれば常に注入されるようにする |
| 8 | **`inversePrecedence` が remote キュー順序に未適用** | 氏の `remote-api-curl.md` | **方針転換（2026-08-05）: 適用する。** `queueRemote` に local と同じ挿入規則を反映し、`priority` との同時指定は 400 で弾く。透過等価の観点では現状のほうが規則の二重化であるため（[§10.1](#101-q4-の別解inverseprecedence-の透過等価)）。氏の doc の該当記述も実装変更後に更新する |
| 9 | **M-1: onResume の displayTarget 劣化** | REVIEW_P1_M1B | [§4.2](#42-データ源をどう持つか) のレジストリが要求内容を保持するため、**副産物として解消**する |
| 10 | **`lockCause` がリモート保持を考慮していない** | 本書（2026-07-26 実機確認） | 下記 [§6.1](#61-lockcause-のリモート非対応追加分) |
| 11 | **README が remote 機能に一切触れていない** | 本書（2026-08-05 マージ後確認） | 下記 [§6.2](#62-readme-未記載追加分) |

### 6.1 `lockCause` のリモート非対応（追加分）

実機（jenkins-env、氏のブランチ `8fd2193`）で確認した未修正箇所。氏が直したのは Held By 列と
Queue タブであり、**`lockCause` の文字列生成は手つかず**。

remote 保持中の資源に対して、ビルド名（null）と取得時刻（未設定）をそのまま埋め込んでいる:

```
# REST API（同じ B 上の 2 資源）
demo-plc-board          : locked by null at <unknown>                      ← remote 保持
s02-shared-1785026807   : locked by demo-local-holder-b#1 at Jul 26, 2026, 8:44 AM   ← local 保持

# ローカル待機ジョブのコンソール
The resource [demo-plc-board] is locked by remote lockId e8ec986d-... since <unknown>.
```

- **`locked by null`** — `getBuild()` が null（remote 保持なので Run が無い）
- **`at <unknown>` / `since <unknown>`** — 取得時刻が未設定。`RemoteLockRecord` は `acquiredAt` を
  保持しているので**出せるはずの値**

**対応:** `lockCause` 生成を `remoteLockedBy != null` の場合に分岐させ、clientId と
`RemoteLockRecord#getAcquiredAt()` を使う。Held By 列（氏の実装）と同じ情報源を参照する。

> 露出範囲が広い点に注意。この文字列は **REST API の `lockCause`** と
> **ローカル待機ジョブのコンソール**の両方に出る。とくに後者は「なぜ待たされているか」を
> 調べる利用者が最初に見る場所であり、`by null` は分かりにくい。

### 6.2 README 未記載（追加分）

マージ後の `master` で確認したところ、**プラグイン本体の `README.md` に remote 機能の記述が 1 文字も無い**
（`grep -c -i remote README.md` → **0**）。#1055 で入ったドキュメントは
`src/doc/examples/remote-api-curl.md` と `remote-lock-pipeline-pattern.md` の 2 本と、
`src/doc/examples/readme.md`（索引）への 2 行追加のみ。

利用者が最初に読む README に導線が無いため、**機能が事実上「発見できない」状態**にある。
とくに次の 3 点は既存 README の記述との整合性の問題でもある。

| 箇所 | 現状 | 必要な追記 |
|---|---|---|
| **Permissions 表**（README `### Permissions`） | View / Configure / Unlock / Reserve / Steal / Queue の 6 行のみ | **`RemoteUse`（Implied by: Jenkins.ADMINISTER）の行が欠落**。M1B で追加した権限が表に無く、表自体が不正確になっている |
| **Usage / Acquire lock** | `lock()` のパラメータ説明に `serverId` が無い | peer mode の `lock(..., serverId: 'X')` と delegated mode（`forcedServerId`）の説明 |
| **Configuration as Code** | 例に remote 系キーが無い | `remoteApiEnabled` / `exposeLabel` / `clientId` / `forcedServerId` / `remotes[]`。テストには既に `configuration-as-code-remote.yml` があるので、そこから抜粋できる |

**対応方針:** 本 PR に相乗りさせる。理由は (1) Permissions 表の欠落は既存ドキュメントの不整合であり
早いほうがよい、(2) 本 PR で LR ページに remote 表示が入るため、README の説明対象がここで確定するから。
ただし分量が出るようなら **docs 単独 PR に切り出す**判断もあり（[§10](#10-未決事項実装前に決める) Q7）。

---

## 7. 仕様と実装の乖離をどう扱うか

issue #1025 本文（正本）と実装が意図的にずれている箇所。**本 PR で issue 本文側を更新するか、
実装を寄せるかを決める**必要がある。いずれも M1 で議論済みの決定であり、蒸し返さない。

### 7.1 `exposeLabel` を複数ラベルに拡張した

仕様は "A single label name"。実装は M1E で**空白区切りの複数ラベル OR**（`getExposeLabels()`）。
単一値は後方互換。

→ **実装を維持し、issue 本文を更新する**（機能追加であり後退ではない）。

### 7.2 `heartbeatIntervalSeconds` を無視している

仕様は「省略時はサーバ既定 10s、範囲外なら 400」。実装は**受理・検証はするが値は無視**し、
固定の `STALE_THRESHOLD_MS = max(既定10s × 6, 60s) = 60s` を使う（`RemoteApiV1Action` にコメント済み）。

→ **Phase 1 は現状維持**（ワイヤ形式は既に対応済みなので、設定化は API バージョンを上げずに後から可能）。
当初は [§3.2](#32-get-leaselockid-は追加しない2026-08-05-決定) の `GET /lease` で「実際に効いている値」を
見せる案だったが、その endpoint 自体を Phase 1 から外したため、**Phase 1 では運用者が実効値を API から
読み戻す手段は無い**。help / docs に「Phase 1 では申告値は使われない」と明記して代替する。

> **検証内容の精度に注意。** 実装の 400 `INVALID_HEARTBEAT_INTERVAL` は
> **「整数として読めない」「0 以下」の 2 条件のみ**で、仕様の言う "outside the server's accepted range"
> （上限を含む範囲チェック）は行っていない。値を使っていない以上、上限だけ検証しても意味が無いため
> **これも現状維持**とし、issue 本文の記述を「正の整数であること（値は Phase 1 では未使用）」に改める。

### 7.3 `X_SERVER_ID` / `X_LOCK_ID` の非対称

M1D §3-2 は「env var は local と remote で同一（共有関数）」と定めたが、氏の follow-up で
remote ボディにのみ 2 変数が追加された。共有関数 `buildLockEnvVars` 自体は不変で、
注入地点で足す形。

→ **維持する。** この 2 値は**ネットワークブリッジ由来の情報しか含まない**（どのサーバか・どの lockId か）ため、
M1F の観点「**ブリッジ由来でない** remote 独自判定を増やさない」には抵触しない。
本書に「**ブリッジ固有メタデータは透過等価の対象外**」と明文化し、再議論しない。

### 7.4 `EXPIRED` 状態

仕様の `GET /acquire` は `EXPIRED` を列挙しているが、サーバは返さない。
allocate timeout は `FAILED` + `errorCode=LOCK_WAIT_TIMEOUT`（M1I で確定した表現）。

→ **`EXPIRED` は将来枠**（仕様本文も "future: when maxWaitSeconds is set" と書いている）。
doc から誤記を削除し、issue 本文にも将来枠である旨を補記する。

なお client 側 `RemoteAcquireState` には仕様に無い **`UNKNOWN`** が足してある
（未知文字列を例外にせず吸収するための番兵）。issue 本文の状態一覧に注記する。

### 7.5 `requestId` / `leaseId` を `lockId` に一本化した

仕様は acquire 側を `requestId`、lease 側を `leaseId` と別 ID で書いているが、実装は
**`POST /acquire` が返す `lockId` を lease 操作でもそのまま使う**。実際に 2 つの ID を分ける必要が無く、
分けるとクライアントが対応表を持たされる。

→ **実装を維持し、issue 本文の endpoint 表・client loop・JSON 例を `lockId` に統一する。**
本 PR で新設する 3 本（`GET /lease/{lockId}`・`POST /acquire/{lockId}/cancel`・`GET /resources`）も同じ呼称。

### 7.6 acquire リクエストボディの構造が仕様と別物

仕様の JSON 例はフラットな 3 フィールド（`resource` / `skipIfLocked` / `heartbeatIntervalSeconds`）。
実装は透過等価対応（M1C〜M1G）を経て次の形になっている。

```jsonc
{
  "clientId": "jenkins-a",              // 任意。未指定ならサーバ側で "Remote API" 表示
  "heartbeatIntervalSeconds": 10,       // 任意・現状は無視（§7.2）
  "lockRequest": {                      // ← ラッパが入った
    "resource": "plc-01",
    "label": "plc",
    "quantity": 0,                      // 0/未指定 = label に一致する全件（local lock() と同じ）
    "variable": "RESOURCE",
    "inversePrecedence": false,
    "resourceSelectStrategy": "SEQUENTIAL",
    "skipIfLocked": false,
    "priority": 0,
    "timeoutForAllocateResource": 0,
    "timeoutUnit": "MINUTES",
    "reason": "…",
    "extra": [ { "resource": "…", "label": "…", "quantity": 0 } ]
  }
}
```

→ **実装を維持し、issue 本文の JSON 例を差し替える。** 本文の例のままだと、curl クライアントを
書く人が `lockRequest` ラッパに気付けず `MISSING_LOCK_REQUEST`（400）を踏む。
`src/doc/examples/remote-api-curl.md` は正しい形で書かれているので、本文からそちらへ誘導するのが実務的。

### 7.7 `remoteApiEnabled=false` 時の応答が 403 になっている

仕様は「全エンドポイントが **API が存在しないかのように** 応答する」＝ 404 相当を意図した書き方。
実装は 4 本すべて **403 `REMOTE_API_DISABLED`**（`RemoteApiV1Action` の各メソッド冒頭）。

→ **実装を維持し、issue 本文を「403 `REMOTE_API_DISABLED` を返す」に改める。**
理由: (1) 認可チェック（`checkPermission(REMOTE)`）が先に走るため、権限の無い相手には
どのみち「存在の有無」を明かさない、(2) 権限を持つ運用者にとっては
「無効化されている」と「パスを間違えた」が区別できるほうが診断しやすい、
(3) 本 PR の新設 3 本を仕様どおり 404 にすると**同一 API 内で挙動が割れる**。

### 7.8 クライアント側に `clientId` 設定が増えている

仕様の Client-side settings 表は `remotes[]` と `forcedServerId` の 2 つのみ。実装には
**`clientId`**（サーバ側 LR ページで「どのコントローラが握っているか」を表示するための自己申告名。
未設定時は root URL 相当にフォールバック）が追加されている。JCasC でも設定可能
（`configuration-as-code-remote.yml`）。

→ **実装を維持し、issue 本文の Client-side settings 表に 1 行追加する。**

### 7.9 `RemoteUse` 権限を Phase 1 で先行実装した

仕様の Non-goals は「Phase 1 ではプラグイン固有の allow-list や**専用の remote-API 権限は作らない**。
Jenkins 標準の認証・認可で保護する」と明記。実装は Security Scan 対応（M1H）で
**専用 Permission `RemoteUse`（ADMINISTER が implied）を追加**し、全エンドポイントがこれを要求する。

→ **実装を維持し、issue 本文の Non-goals と Phase 1 scope を修正する。**
これは「クライアント allow-list」（＝どの client を許すかの列挙）とは別物で、
**権限を絞れるようにしただけ**。allow-list 自体は引き続き Phase 2（[§8](#8-含まないもの)）。
Non-goals に残したままだと、レビュアから「仕様に反する実装」に見える。

### 7.10 Open questions のうち確定したもの

issue 本文末尾の Open questions は #1055 でほぼ決着している。**本文を更新して未決事項を減らす**。

| Open question | 確定値 | 根拠 |
|---|---|---|
| Default polling interval | **3s** | `RemoteClientDefaults.DEFAULT_POLL_INTERVAL_SECONDS` |
| Default heartbeat / stale threshold | **10s** / `max(hb × 6, 60) = 60s` | `RemoteClientDefaults` / `RemoteLockManager.STALE_THRESHOLD_MS`（式は仕様どおり） |
| `UNKNOWN_RESOURCE` / `UNKNOWN_LABEL` の HTTP コード | **404 に統一**（本文は "4xx" 止まり） | `RemoteApiV1Action`。存在の有無を明かさないため両者を同一コードに |
| サーバ側の remote owner 表示 | **`clientId`**（未指定時 "Remote API"）を Held By / Queue に表示 | M1B ＋ 氏の follow-up |
| UI 統合の詳細（merged vs separate tab、バッジ） | 本書 [§4.3](#43-表示) / [§5](#5-設計-c-delegated-mode-の表示切替m2-本体) で確定 | 本 PR で実装 |

未決のまま残るのは **クライアント側の request timeout 既定 5s**（`DEFAULT_REQUEST_TIMEOUT_SECONDS`。
本文の Open questions には項目自体が無い）くらい。設定化は Phase 2。

---

### 7.11 乖離の記載先を PR 本文にする（2026-08-08）

本節（§7.1〜§7.10）で洗い出した「実装が正・issue 本文が古い」項目は、**本文を書き換えて解消しない**。
**新 PR の本文に乖離セクションとして書き、PR 提出後に #1025 へ導線コメントを 1 本置く**形に変更した。

**理由:** #1025 の本文は設計が固まるまでの議論を反映して何度も更新されており、いま実装に合わせて直しても
「どこが最新か」の可読性は戻らない。読み手にとっては、**実装と一体で提示される PR 本文のほうが信頼できる**。

**PR 本文に書く内容（§7 から転記する項目）:**

| # | 乖離 | 理由 |
|---|---|---|
| 1 | `requestId` / `leaseId` → `lockId` に一本化 | 2 つに分ける必要が無く、クライアントに対応表を持たせるだけになる（§7.5） |
| 2 | `POST /acquire` のボディが `lockRequest` ラッパ ＋ `clientId` ＋ 全 `lock()` パラメータ | 透過等価（M1C〜M1G）の結果（§7.6） |
| 3 | `remoteApiEnabled=false` が 403 `REMOTE_API_DISABLED` | 認可チェックが先に走るため存在は秘匿済み。運用者には「無効」と「パス誤り」が区別できるほうが有用（§7.7） |
| 4 | クライアント側 `clientId` 設定の追加 | サーバ側 LR ページで保持者を示すため（§7.8） |
| 5 | 専用権限 `RemoteUse` を Phase 1 で実装 | Security Scan 対応（M1H）。allow-list とは別物（§7.9） |
| 6 | `exposeLabel` が複数ラベル OR | M1E の機能拡張。単一値は後方互換（§7.1） |
| 7 | allocate timeout は `FAILED` + `LOCK_WAIT_TIMEOUT`、`EXPIRED` は将来枠 | M1I で確定（§7.4） |
| 8 | `heartbeatIntervalSeconds` は受理するが Phase 1 では未使用 | 設定化は後続。ワイヤ形式は先行して用意済み（§7.2） |
| 9 | `cancel` は `release` に統合、`GET /lease` は後続 | M1 で決定済み（§3.2 / §3.3） |
| 10 | `GET /resources` が状態と `acceptNewAcquires` を返す | 画面で local/remote の情報量を揃えるため（§3.1） |
| 11 | 既定値の確定（poll 3s / heartbeat 10s / stale 60s / `UNKNOWN_*` は 404） | 実装で確定（§7.10） |

**副作用として受容すること:** 本文は古いまま残るため、**新規の読み手は本文を仕様として読む**。
PR 提出後のコメントは時系列で流れるので、時間が経つほど届きにくくなる。
最小の緩和策として「本文冒頭に警告 1 行だけ置く」案はあるが、2026-08-08 時点では**採らない**（ユーザー判断）。

---

## 8. 含まないもの

M1 の設計判断を引き継いで**意図的に残置**するもの。再議論しない。

| 項目 | 出典 | 理由 |
|---|---|---|
| **M1E-1** 昇格経路の `fromNames(create=true)` による ephemeral 再生成 | DESIGN_P1_M1F §4 | **2026-08-08 に再検討し、あらためて残置と確定**。根本は canonical 側にキュー掃除の仕組みが無いことで、ブリッジ層では症状しか消せない。詳細と再開条件は [§8.1](#81-m1e-1孤児-ephemeral再検討の記録2026-08-08) |
| **M1E-2** resource と label 同時指定時の挙動 | 同上 | local `lock()` 由来。非 fail-open |
| **M1E-3** lease 操作の lockId 所有者非検証 | 同上 | トラストバウンダリ＝REMOTE 権限という既存モデルを維持。多テナント化時に Phase 3 |
| **L-e** `getExposeLabels` の毎回 split | 同上 | 性能のみ・無害 |
| `.gitattributes` の追加 | REVIEW_UPSTREAM §13.3 | リポジトリ横断の規約変更。maintainer 判断に委ねる |
| help URL 表記の統一（`/descriptor/` vs `/descriptorByName/`） | 同上 | 同上。動作差なし |
| サーバ側メンテナンススイッチ（accept new acquires ON/OFF） | issue #1025 | **Phase 2** |
| polling / heartbeat / timeout の設定化 | 同上 | **Phase 2** |
| クライアント allow-list | 同上 | **Phase 2**（`RemoteUse` 権限は M1B で先行実装済み） |
| マルチサーバルーティング / failover、`serverId:'any'` | 同上 | **Phase 3** |
| クライアント LR ページからの cancel / release 操作 | 本書 [§4.3](#43-表示) | Phase 1 は可視化まで |

### 8.1 M1E-1（孤児 ephemeral）再検討の記録（2026-08-08）

**何度でも再浮上する論点**なので、そのたびに一から追跡せずに済むよう機構と判断根拠を残す。

**機構（時間差。Admission は時点検査であってエントリの生存期間を守らない）:**

```
t0  remote から lock(resource:'plc-01') → Admission 通過（実在かつ exposed）
    → 他が保持中のため QUEUED（エントリは canonical structs = 名前 "plc-01" を保持）
t1  管理者が plc-01 を削除（removeResources は syncResources を取るので
    スキャンとは競合しないが、スキャンとスキャンの「間」には普通に起きる）
t2  昇格スキャン → Admission を再実行しない
    → canonical の名前ブランチが fromNames("plc-01", create=true)（LRM:1586）
    → plc-01 が ephemeral として復活（ラベル無し・doSave=true で永続）
```

**local でも同じコードパスで再現する**（`proceedLocalEntry` の `fromNames(candidates, true)`、LRM:1027）。
違うのは**結末**であり、そこが remote 固有の被害を生む:

| | local | remote |
|---|---|---|
| t2 で復活した資源 | 露出フィルタが無いので**そのままロックされる** | ラベル無しのため **exposeLabel フィルタが弾き、永久にロックされない** |
| 解放時 | `freeResources` が `isEphemeral()` を見て `removeResources` で削除 | ロックされないので解放も起きず、**回収経路に入らない** |
| 最終状態 | **元通り**（ライフサイクル完結・自己修復） | **孤児が永続**（再起動しても残る） |

→ canonical の `create=true` は **local にとっては正常動作**（名前を要求されたら在るものとして扱う ephemeral の設計意図）。
壊れているのは「可視性フィルタを挟んだせいで回収ループが閉じない」という remote 側の組み合わせのほう。

**検討した閉じ方と、いま採らない理由:**

| 案 | 内容 | 判断 |
|---|---|---|
| (a) canonical に `create=false` を通す | 解決シームに remote 用フラグ | **不可**。M1F の観点（ブリッジ由来でない remote 独自判定を canonical に足さない）に反する |
| (b) 昇格スキャンで Admission を再実行 | ブリッジ層のみで完結。canonical 不変 | **技術的には可能**（数行）。ただし remote の症状を消すだけで根本ではない |
| (c) 資源削除時にキューを掃除 | 削除された資源を参照する QUEUED エントリ（local/remote 双方）を除外する仕組みを LR 本体に入れる | **根本解。ただし upstream 横断の設計変更**であり、drive-by contributor が持ち込む範囲を超える |

**残置の理由（2026-08-08、ユーザー判断）:** 発火には「削除したリソースを、その直後に lock しに来るジョブが待機している」
という状態が要る。**リソースを削除する時点でもう誰も要求しないことが確定しているはず**で、そうでないなら運用側のバグ。
実運用で踏むルートではないため、(b) のコストと引き換えるほどの価値が無い。

**再開を検討すべき条件（次に浮上したときの判断材料）:**

- 実運用または負荷試験で**実際に孤児が観測された**とき（＝発火頻度の前提が崩れる）
- (c) が upstream 側で実装されたとき（そのとき remote 側の (b) は不要になる）
- 多テナント化など、**リソース削除が日常操作になる**運用形態を扱うとき（M1E-3 の再開条件と同時期になるはず）
- 孤児が「非ロックで無害」でなくなる変更が入ったとき（例: 露出判定の緩和、ephemeral の自動公開）

---

## 9. テスト方針

サイクル完了条件は従来どおり（`run-mvn-verify.sh` ＋ `run-e2e.sh` 全件）。

### 9.1 ユニット

| 対象 | 内容 |
|---|---|
| `GET /resources` | exposeLabel フィルタが効く / 未公開資源が出ない / `remoteApiEnabled=false` で **403 `REMOTE_API_DISABLED`**（既存 3 本と同型）/ 状態フィールドを含まない |
| `release` の QUEUED 経路 | terminal TTL 保持に変わり、**直後の `GET /acquire/{lockId}` が 200 `FAILED`/`RELEASED` を返す**（404 ではない）。TTL 経過後は 404 に戻る |
| メンテナンススイッチ | OFF で `POST /acquire` が 503 `ACQUIRES_PAUSED` / **同じ状態で heartbeat・release・`GET /acquire` は成功する** / ON に戻すと再び受理 / 既存キューの昇格が止まらない |
| `inversePrecedence`（透過等価） | remote 要求が `inversePrecedence=true` でキュー先頭に入る（local と同じ挿入位置）/ `priority != 0` との同時指定は 400 |
| `RemoteClientRegistry` | acquire/release での登録・解除 / `onResume` 後の再構築 / ビルド削除時に落ちない |
| Queue マージ順序 | local+remote を priority 降順で並べ、index が昇格順と一致する |

### 9.2 E2E（新規シナリオ）

| ID | 名前 | 検証 |
|---|---|---|
| S19 | `remote-resources-endpoint` | A が B の `GET /resources` を取得し、**exposeLabel 付きのみ**が返る。未公開資源が漏れない |
| S20 | `client-side-remote-view` | A が B の資源を保持中、**A の LR ページに保持中 remote ロックが出る**。解放後に消える |
| S21 | `delegated-mode-page` | A に `forcedServerId=b` を設定 → A の LR ページに **delegated バッジ**と **B の公開資源**が出る。解除で元に戻る |
| S22 | `remote-maintenance-switch` | B を OFF にすると A の新規 `lock()` が待たされる（ジョブは落ちない）／**保持中のリースは heartbeat・release とも無事**／ON に戻すと待っていた `lock()` が取得に進む |

> S22 は [§6-1](#6-m1-やり残しの取り込み)（404 ラベル問題）の回帰ガードも兼ねる。
> M1 で見送った「QUEUED 中のサーバ再起動」シナリオは、ラベル方針が本書で確定するため
> **ここで書けるようになる**（[§10](#10-未決事項実装前に決める) Q1 の決定後）。

### 9.3 負荷

`run-load.sh`（G01 grid-storm）で計測する。`GET /resources` は**キャッシュ有無で挙動が変わる**ため、
「全コントローラが **10s ごと**に相互の `/resources` を引く」負荷を**加えて計測する**
（[§10](#10-未決事項実装前に決める) Q5 で確定。状態を返すことにした結果、頻度が 6 倍になったため）。

> **確定した条件（2026-08-05）:** 負荷試験は **LR ページが正式な挙動で更新されている状態のまま**回せること。
> 計測のためにクライアント側リモートビューを無効化したり、キャッシュを迂回したりしない。
> 実運用と同じく 60s TTL のキャッシュが効いた状態の数字を取る。

### 9.4 新旧並走の視覚比較（PR スクショ用）

**進め方の方針（2026-08-05 確定）:** UI の論点は Martin 氏に**事前質問しない**。作り込んで
デザインを固め、**PR に修正前後のスクリーンショットを貼って「こう作ってみたがどうか」**として提示する。
#1035 で体裁が大きく変わった直後であり、文章より現物のほうが議論しやすいため。

**手順:** `jenkins-env` の 4 コントローラのうち **a に新版（PR 提出版）、b に旧版（現 master）** を載せ、
同じ資源構成・同じロック状況で両方の LR ページを開いて見比べる。

- `start.sh` は全コントローラに同じ hpi を配るので、**b だけ旧版に差し替える手作業が要る**:
  `docker compose stop` → `jhb/plugins/` の hpi を master ビルドに置換＋展開ディレクトリ削除 → `docker compose start`
  （[[rlr-build-environment]] のデプロイの罠と同じ手順）
- **c / d は新版のまま**にしておくと、a↔c/d で新版同士の相互ロックも同時に確認できる
- a（新版クライアント）→ b（旧版サーバ）のロックが通ることは、**ワイヤ互換性の確認**にもなる
  （追加したのは `GET /resources` と 503 だけで、既存 4 本の契約は不変）
- この状態では E2E / load は回さない（両スイートは全台同一ビルド前提）。**視覚比較専用の一時構成**

**この比較で最終決定する項目:** [§10](#10-未決事項実装前に決める) Q6（Remote ビューを新規タブにするか
Resources の列にするか）。暫定 (a) 新規タブで作るが、並べて見て違和感があれば作り直す。

---

## 10. 未決事項（実装前に決める）

**2026-08-05 にユーザー判断で全件確定**（Q5 のみ実装後に再判断）。以下は決定事項であり、再議論しない。

| # | 論点 | 決定 |
|---|---|---|
| Q1 | 404/410 ラベルの文言 | **(a) 一本化。** 事実確認の結果、当該分岐（`RemoteLockSession` の 404/410 処理、現 249-290 行）は `73a2d3b`（初版）＋`7fd218b`（M1I）で**全行が当方のコード**。氏が同ファイルに入れた `9ffade8` は acquire 時ログの `serverUrl` 追記とビルドログへのエラー出力のみで poll 分岐に未関与。**他者コードへの手入れにならない**ため一本化を採用 |
| Q2 | クライアント LR ページからの操作 | **(a) 可視化のみ。** #1025 / #1055 の全コメントを検索した結果、cancel ボタンの発案元は**当方のメモのみ**（Martin 氏は一度も言及なし）。外部への約束が無いため、Phase 1 では出さない |
| Q3 | ~~`GET /lease` に申告値も併記するか~~ | **論点消滅。** `GET /lease/{lockId}` 自体を Phase 1 スコープから外したため（[§3.2](#32-get-leaselockid-は追加しない2026-08-05-決定)）。将来 heartbeat 値の設定化と同時に導入する際に再検討する |
| Q4 | `inversePrecedence` を remote キューに適用するか | **(c) 別解＝透過等価として local の規則を remote 経路に反映する。** 下記 [§10.1](#101-q4-の別解inverseprecedence-の透過等価) |
| Q5 | `/resources` を負荷テストに含めるか | **含める（2026-08-08 に確定）。** §3.1 で状態を返すことにし TTL が 60s → 10s になったため、呼び出し頻度が 6 倍になった。grid-storm に「全コントローラが 10s ごとに相互の `/resources` を引く」負荷を加えて実測する。条件は従来どおり **LR ページが正式な挙動で更新されている状態のまま**回すこと |
| Q6 | Remote locks を新規タブにするか既存タブ内セクションにするか | **暫定 (a) 新規タブ**（#1035 のタブ構成に乗る）で作り、**実装後に新旧並走で見比べて最終決定**する（[§9.4](#94-新旧並走の視覚比較pr-スクショ用)）。#1035 で体裁が大きく変わったため、机上では判断しきれないというのが理由。Martin 氏には事前に質問せず、固めたものを PR で提示する |
| Q7 | README 追記（[§6.2](#62-readme-未記載追加分)）を本 PR に含めるか | **(a) 本 PR に相乗り。Permissions 表の欠落も分離せず同梱**する |
| Q8 | issue 本文の更新をいつ出すか | **方針変更（2026-08-08）: 本文は更新しない。** #1025 は約 1 年の議論が堆積して「どこが最新か」が読み取りにくい状態にあり、本文だけ直しても可読性は戻らない。代わりに **新 PR の本文に「#1025 仕様との乖離と、そうした理由」を明記**し、PR 提出後に #1025 へ「最新仕様は PR #X にある」と短く追記する。→ [§7.11](#711-乖離の記載先を-pr-本文にする2026-08-08) |

### 10.1 Q4 の別解（`inversePrecedence` の透過等価）

論点は「remote 独自の順序ルールを足すか」ではなかった。**local の挿入規則が remote 経路に反映されていない**のが実態で、
反映すれば規則はむしろ一本化される。

| 経路 | 現状 |
|---|---|
| local `queueContext` | `inversePrecedence && priority == 0` のとき **index 0 に挿入**（＝キュー先頭に割り込む）。それ以外は `compare` で整列挿入 |
| remote `queueRemote` | **priority だけで挿入位置を決める。`inversePrecedence` を一切参照しない**（ワイヤで運ばれ `RemoteLockRequest` に保持されてはいる） |

**対応 1:** `queueRemote` に local と同じ条件分岐を入れる。値は `entry.getLockRequest().isInversePrecedence()` で取得できる。

**対応 2（関連する穴）:** local は `priority != 0 && inversePrecedence` の同時指定を
`LockStepResource.validate()` で `IllegalArgumentException` にするが、**remote の POST は両方を黙って受理する**。
これは単独の穴ではなく「canonical 検証に丸投げする」という構成全体の一部として解決する。
判定順序・HTTP コード・実装位置は [§3.5](#35-サーバ側の判定順序wire--admission--canonical) に集約した。

これに伴い [§6](#6-m1-やり残しの取り込み) の項目 8（「適用しない」方針）は**逆転**する。氏の `remote-api-curl.md` の
記述（現状の挙動を正確に書いている）は、実装変更後に更新が必要になる。

---

## 11. 更新履歴

| 日付 | 内容 |
|---|---|
| 2026-07-26 | 初版。issue #1025 の Phase 1 M2/M3 を統合し、M1 やり残し 9 件の取り込み先として定義 |
| 2026-08-08 (3) | **issue #1025 本文の更新を取りやめ**（Q8 の方針変更）。乖離は**新 PR 本文に「乖離と理由」として記載**し、PR 提出後に #1025 へ導線コメントを置く形に変更。§7.11 を新設し、PR 本文へ転記する 11 項目を一覧化。本文が古いまま残る副作用と、採らなかった緩和策（本文冒頭の警告 1 行）も記録 |
| 2026-08-08 (2) | `GET /resources` の仕様を確定（§3.1 全面書き換え）。**「状態を返さない」決定を撤回**し、local/remote の情報量を揃えるため `state`（FREE/LOCKED/RESERVED/QUEUED）＋ `heldByKind` ＋ `heldByClientId` ＋ `since` ＋ `queuedCount` を返す。**開示レベルは中間案**（ビルド名・reason・note は返さない = B のジョブ名を A の閲覧者に出さない）。**`acceptNewAcquires` を同じレスポンスに載せる**（別エンドポイントだとキャッシュ不整合で「FREE と表示しつつ受付停止中」の画面が作れてしまうため）。メンテ中も資源状態は真実を返し、表現は画面側で行う。§5.2 のキャッシュ TTL を 60s → **10s**、§10 Q5 は「**含める**」に確定 |
| 2026-08-08 | 検証ロジックの再設計。**§3.5「サーバ側の判定順序（Wire → Admission → Canonical）」を新設**し、remote 固有判定を Wire と Admission の 2 層に閉じ込め、残りは `LockStepResource.validate()` に丸投げする構成に確定（境界の `MISSING_TARGET` / `INVALID_SELECT_STRATEGY` は削除。前者は `allowEmptyOrNullValues` を無視する既存の透過等価の破れでもあった）。**M1E-2（resource+label 同時指定）は「remote 固有コードを減らすことで自動的に閉じる」ため残置を解除**。秘匿性（一律 404）は Admission を先に置くことで無償維持。**M1E-1（孤児 ephemeral）は再検討のうえ残置を維持**し、機構・local との差・閉じ方 3 案・再開条件を §8.1 に記録 |
| 2026-08-05 (3) | 進め方を変更: **UI 論点は氏に事前質問せず、作り込んで PR にスクショで提示**する方針を §3.4 / §10 Q6 に反映し、**§9.4「新旧並走の視覚比較」を新設**（a=新版・b=旧版、E2E/load は回さない一時構成、ワイヤ互換性確認も兼ねる）。Q6 は「暫定 (a) 新規タブ、実機比較で最終決定」に変更。**§5.0 を新設して delegated 表示を「置き換え」→「並存」に方針変更**（役割は関係単位／#1035 のタブ構成で両立可能。解決ルールは不変）。§10.1 対応 2 の実装位置を決定（remote 層の API 境界で 400。canonical 検証を丸ごと呼ばない理由を明記） |
| 2026-08-05 (2) | §10 の未決 8 件をユーザー判断で確定（Q5 のみ実装後に再判断）。**サーバ側 API を 3 本 → `GET /resources` 1 本に縮小**（`GET /lease` と `cancel` は M1 で決定済みだったものを初版が「未実装」と誤分類。§3.2 / §3.3 を差し替え）。**メンテナンススイッチを Phase 1 に前倒し**（§3.4 新設、氏への質問 2 件は回答待ち）。Q4 は **(c) 別解**＝`inversePrecedence` の透過等価として §10.1 を新設し §6-8 の方針を逆転。§9 のテスト計画（ユニット 3 行・S22）を差し替え、§9.3 に「LR ページを正式挙動のまま計測する」条件を追記 |
| 2026-08-05 | #1055 マージ（`018e913`, 2026-08-04）を受けてマージ後 `master` と突き合わせ。§1.3「Phase 1 チェックボックスの可否」＋呼称の整理を追加。§3.1 の `remoteApiEnabled=false` 時の応答を **403 に訂正**（実装と食い違っていた。§9.1 の該当テスト行も同時修正）。§6 に **11: README 未記載**（§6.2）を追加。§7 に **7.5 lockId 一本化 / 7.6 acquire ボディ構造 / 7.7 403 / 7.8 `clientId` 設定 / 7.9 `RemoteUse` 権限の先行実装 / 7.10 Open questions の確定**を追加。§10 に Q7・Q8 を追加 |
