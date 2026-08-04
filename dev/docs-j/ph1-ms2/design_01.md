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
3. [設計 A: サーバ側 API 3 本の追加](#3-設計-a-サーバ側-api-3-本の追加)
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
| **A. サーバ側 API** | `GET /resources` / `GET /lease/{lockId}` / `POST /acquire/{lockId}/cancel` の 3 本。いずれも **issue #1025 の Phase 1 仕様に最初から載っている未実装分**であり、v1 への「追加」ではなく **v1 の完成** |
| **B. クライアント側 LR ページ** | 発信側コントローラで「自分が保持中／待機中の remote ロック」を可視化。PR #1055 が Known limitation として明記した最大の UX ギャップ |
| **C. delegated mode の表示切替** | `forcedServerId` 設定時に LR ページがリモートの公開資源を表示し、delegated バッジを出す |
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
| `POST /acquire/{lockId}/cancel` | **未** | [§3.3](#33-post-acquirelockidcancel) |
| `GET /lease/{lockId}` | **未** | [§3.2](#32-get-leaselockid) |
| `POST /lease/{lockId}/heartbeat` | ✅ | |
| `POST /lease/{lockId}/release` | ✅ | QUEUED に対しては「即 terminal 化して record ごと削除」。[§3.3](#33-post-acquirelockidcancel) で整理 |
| `GET /resources` | **未** | [§3.1](#31-get-resources) |

`RemoteApiV1Action#getDynamic` の分岐は現状 `acquire` / `lease` の 2 つのみ。`resources` の追加が必要。

> **表記について:** 上表は実装の呼称（`lockId`）に合わせている。issue 本文は acquire 側を `requestId`、
> lease 側を `leaseId` と**別 ID として**書いているが、実装は 1 本の `lockId` に統一済み。
> 本 PR で新設する 3 本もこの統一を踏襲する（[§7.5](#75-requestid--leaseid-を-lockid-に一本化した)）。

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

## 3. 設計 A: サーバ側 API 3 本の追加

`RemoteApiV1Action#getDynamic` に `resources` を足し、`AcquireRouter` に `cancel`、
`LeaseRouter` 配下に `doIndex` を足す。**認可・有効化ゲートは既存 3 本と完全に同型**にする
（`Jenkins.get().checkPermission(REMOTE)` → `isRemoteApiEnabled()` チェック → 本体）。

### 3.1 `GET /resources`

公開中のリソース一覧を返す。**状態は含めない**（安価・キャッシュ可能に保つ、という仕様上の明示的な決定）。

```jsonc
// GET /lockable-resources/remote/v1/resources  -> 200
{
  "resources": [
    { "name": "plc-01", "labels": ["plc", "remote-enabled"], "description": "PLC 01" },
    { "name": "plc-02", "labels": ["plc", "remote-enabled"], "description": "" }
  ]
}
```

- **公開フィルタは既存の `getExposeLabels()` を再利用**する。新しい remote 独自判定を足さない
  （M1F の観点「ブリッジ由来でない remote 独自判定を増やさない」を維持）
- `remoteApiEnabled=false` のときは既存 3 本と**完全に同型**、すなわち
  **403 `REMOTE_API_DISABLED`** を返す。issue 本文は「API が存在しないかのように応答（＝404）」と
  書いているが、実装は M1 の時点で 403 を選んでいる。**ここで 404 にすると同一 API 内で挙動が割れる**ため、
  実装の 403 に揃え、issue 本文側を直す（[§7.7](#77-remoteapienabledfalse-時の応答が-403-になっている)）
- 状態（locked / reserved / queued）は**返さない**。返すとクライアント側がそれをロック判断に使う誘惑が生まれ、
  「リモートが単一の真実」という設計原則を壊す。仕様の意図どおり除外する
- ページングは持たない（小〜中規模前提。数千件になる想定なら Phase 3）

### 3.2 `GET /lease/{lockId}`

保持中リースの診断用。仕様では **negotiated `heartbeatIntervalSeconds` と算出された
`staleThresholdSeconds` を返す**と定めている。

```jsonc
// GET /lockable-resources/remote/v1/lease/{lockId}  -> 200
{
  "lockId": "…",
  "state": "ACQUIRED",
  "clientId": "jenkins-a",
  "resources": ["plc-01", "plc-02"],
  "acquiredAt": 1784971784834,
  "lastHeartbeatAt": 1784971844834,
  "heartbeatIntervalSeconds": 10,
  "staleThresholdSeconds": 60
}
```

**設計判断:** `heartbeatIntervalSeconds` はクライアントが送ってきた値ではなく、
**実際に効いている値（＝サーバ既定 10s）を返す**。

理由: 現在サーバはクライアントの申告値を無視して固定閾値を使う（[§7.2](#72-heartbeatintervalseconds-を無視している)）。
"negotiated" が意味するのは「実際に合意され効いている値」なので、申告値をそのまま返すと**嘘になる**。
運用者が「どの値が効いているか正確に見える」ことが仕様の目的であり、そちらを優先する。

> クライアントの申告値も見せたい場合は `requestedHeartbeatIntervalSeconds` を別フィールドで併記する。
> ただし現状は無視される値なので、混乱を招くだけなら省いてよい（[§10](#10-未決事項実装前に決める) Q3）。

`state` が `ACQUIRED` / `STALE` 以外（QUEUED など）の場合は **404** を返す
（「lease」はリソースを保持している状態を指すため）。

### 3.3 `POST /acquire/{lockId}/cancel`

QUEUED（未取得）の要求を取り消す。

**現状 `release` との重複を整理する必要がある。** 現在の `RemoteLockManager#release()` は
QUEUED レコードに対しても動き、`markFailed("RELEASED")` してから `records.remove()` する。
つまり **record ごと消えるので、直後の `GET /acquire/{lockId}` は 404 になる**。

| | 現状 `release`（QUEUED に対して） | 新設 `cancel` |
|---|---|---|
| 状態遷移 | `FAILED("RELEASED")` → **即 record 削除** | **`CANCELLED`** に遷移し、terminal TTL（120s）だけ**保持** |
| 直後の `GET /acquire/{lockId}` | **404 LOCK_NOT_FOUND** | **200 `state=CANCELLED`** |
| 想定利用者 | パイプライン client（内部） | 外部スクリプト client（curl 等） |

**設計判断:** `cancel` は `release` のエイリアスにせず、**`CANCELLED` へ遷移させて保持する**独立の遷移とする。

理由:
1. 仕様の client loop が `CANCELLED -> stop` を明示している。404 では「サーバ再起動」と区別できず、
   [§6-1](#6-m1-やり残しの取り込み) の 404 ラベル問題と同じ穴を新たに作ることになる
2. `RemoteAcquireState` にはすでに `CANCELLED` があり、`RemoteLockSession.pollOnce()` も
   `case CANCELLED` を実装済み（「remote 側/管理者によるキャンセルへの互換」としてコメント済み）。
   **クライアント側は変更なしで受け取れる**
3. terminal TTL は M1I で `terminalAt` 起点に修正済みなので、120s の観測窓が正しく効く

これに伴い `RemoteLockState` に **`CANCELLED` を追加**する（現在は QUEUED/ACQUIRED/SKIPPED/FAILED/STALE）。

- ACQUIRED 済みに対する `cancel` は **409 Conflict**（`ALREADY_ACQUIRED`）。解放は `release` を使わせる
- 未知 lockId は 404
- 所有者検証は行わない（M1E-3 の既存トラストモデルを踏襲。[§8](#8-含まないもの)）

> **併せて `release` の QUEUED 経路も見直す。** 上表のとおり現状は「即削除 → 404」であり、
> パイプライン client が abort された直後に別経路が poll すると 404 を踏む。
> **`release` の QUEUED 経路も `CANCELLED` 遷移＋TTL 保持に統一**し、`records.remove()` を
> 掃引に一本化する。これは [§6-1](#6-m1-やり残しの取り込み) と同じ「404 を出さない」方向の整理。

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
  誤操作でパイプラインと状態がずれるリスクを避ける（[§10](#10-未決事項実装前に決める) Q2）

---

## 5. 設計 C: delegated mode の表示切替（M2 本体）

`forcedServerId` が設定されているとき、LR ページの意味論が変わる。仕様の要求は 3 点。

1. **delegated バッジ**を明示（管理者が解決意味論の変化に驚かないように）
2. **リモートの公開資源を表示**する（`GET /resources` の結果）
3. **ローカル資源定義は「delegated mode では使われない」と示す**（隠すか、その旨を表示）

### 5.1 表示の切り替え

| モード | Resources タブ | Remote locks タブ |
|---|---|---|
| **peer**（`forcedServerId` 未設定） | ローカル資源（従来どおり） | 自分が保持/待機中の remote ロック |
| **delegated**（`forcedServerId` 設定済み） | **`forcedServerId` の公開資源**（`GET /resources`）。ローカル資源は "not used in delegated mode" と注記して折りたたむ | 同上 |

delegated mode ではページ上部に常時バッジを出す:

```
[ Delegated mode ] All lock() calls are routed to serverId = "b" (http://jenkins-b:8080/jenkins)
```

### 5.2 `GET /resources` の短期キャッシュ

毎回のページ表示でリモートを叩かない。**TTL 付きの短期キャッシュ**（既定 60s）を client 側に持つ。

- キャッシュミス時のみ HTTP。取得失敗時は**最後に取れた内容＋「stale（最終取得 N 分前）」表示**にフォールバック
  （fail-closed はロック取得の話であり、**表示は best-effort でよい**）
- リモート設定（`remotes` / `forcedServerId`）変更時はキャッシュを破棄
- 取得はページ表示のリクエストスレッドではなく**非同期**にし、UI をブロックしない

---

## 6. M1 やり残しの取り込み

`../ph1-ms1/LRR_REVIEW_UPSTREAM_FOLLOWUP_UX.md` §13.3 で「Phase 2 PR に相乗り」と決めたものを含む。

| # | 項目 | 出典 | 対応 |
|---|---|---|---|
| 1 | **`RemoteLockSession` の 404/410 ラベルのねじれ** | REVIEW_UPSTREAM §12.2 | 到達可能な `!bodyStarted` 側を「record が存在しない（サーバ再起動の可能性）」寄りの表現に改める。正当な allocate timeout はサーバ側 FAILED 経路に一本化済みである前提をコメントで明示。[§3.3](#33-post-acquirelockidcancel) の `CANCELLED` 保持と併せて **404 が出る条件そのものを減らす** |
| 2 | **docs `remote-api-curl.md` の状態表** | REVIEW_UPSTREAM §12-8 | `EXPIRED` の誤記を削除（サーバは返さない。`maxWaitSeconds` 導入時の将来枠と明記）、`STALE` を追記、`heartbeatIntervalSeconds` がサーバ側で無視される旨を注記。**`CANCELLED` は本 PR で実在するようになるので正式記載** |
| 3 | **Queue タブの Change Position ボタン** | REVIEW_UPSTREAM §12-3/4 | remote 行ではボタンを描画しない（JS で `item.type === "remote"` を除外）。位置検証の範囲もローカルキュー件数基準であることを明示 |
| 4 | **`X_SERVER_ID` / `X_LOCK_ID` の位置づけ** | REVIEW_UPSTREAM §12.1 | 「ブリッジ固有メタデータは透過等価の対象外」と設計書（本書 [§7.3](#73-x_server_id--x_lock_id-の非対称)）に明文化して**維持**する |
| 5 | **Queue の index 順序** | REVIEW_UPSTREAM §12-5 | local/remote をマージ後に priority 降順でソートしてから index を振る。実際の昇格順（`proceedNextContext`）と一致させる |
| 6 | **Queue のフリーテキスト filter** | REVIEW_UPSTREAM §12-6 | `filter` 分岐に `getRemoteRequest()` / `getRequestedBy()` を追加し、remote 行にも効くようにする |
| 7 | **`withRemoteMetadata` が空 `lockEnvVars` で落ちる** | REVIEW_UPSTREAM §12-7 | 条件の外に出し、`variable` 指定があれば常に注入されるようにする |
| 8 | **`inversePrecedence` が remote キュー順序に未適用** | 氏の `remote-api-curl.md` | **適用しない**方針を維持し、doc の記述（既に正確）をそのままとする。適用するとローカルキューと remote キューで順序規則が二重化するため（[§10](#10-未決事項実装前に決める) Q4） |
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
ただし [§3.2](#32-get-leaselockid) の `GET /lease` は**実際に効いている値**を返すことで、
「無視されている」ことが運用者から見えるようにする。

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

## 8. 含まないもの

M1 の設計判断を引き継いで**意図的に残置**するもの。再議論しない。

| 項目 | 出典 | 理由 |
|---|---|---|
| **M1E-1** 昇格経路の `fromNames(create=true)` による ephemeral 再生成 | DESIGN_P1_M1F §4 | canonical の name 解決そのもの。remote だけ `create=false` にするのは remote 独自判定の追加 |
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

---

## 9. テスト方針

サイクル完了条件は従来どおり（`run-mvn-verify.sh` ＋ `run-e2e.sh` 全件）。

### 9.1 ユニット

| 対象 | 内容 |
|---|---|
| `GET /resources` | exposeLabel フィルタが効く / 未公開資源が出ない / `remoteApiEnabled=false` で **403 `REMOTE_API_DISABLED`**（既存 3 本と同型）/ 状態フィールドを含まない |
| `GET /lease/{lockId}` | ACQUIRED で 200＋`staleThresholdSeconds` / QUEUED で 404 / 未知 lockId で 404 |
| `POST /acquire/{id}/cancel` | QUEUED → `CANCELLED` 遷移 / **直後の GET が 200 `CANCELLED`（404 ではない）** / ACQUIRED に対しては 409 / 未知は 404 |
| `release` の QUEUED 経路 | `CANCELLED` 遷移＋TTL 保持に変わったこと（回帰） |
| `RemoteClientRegistry` | acquire/release での登録・解除 / `onResume` 後の再構築 / ビルド削除時に落ちない |
| Queue マージ順序 | local+remote を priority 降順で並べ、index が昇格順と一致する |

### 9.2 E2E（新規シナリオ）

| ID | 名前 | 検証 |
|---|---|---|
| S19 | `remote-resources-endpoint` | A が B の `GET /resources` を取得し、**exposeLabel 付きのみ**が返る。未公開資源が漏れない |
| S20 | `client-side-remote-view` | A が B の資源を保持中、**A の LR ページに保持中 remote ロックが出る**。解放後に消える |
| S21 | `delegated-mode-page` | A に `forcedServerId=b` を設定 → A の LR ページに **delegated バッジ**と **B の公開資源**が出る。解除で元に戻る |
| S22 | `remote-acquire-cancel` | 待機中の acquire を `cancel` → **`GET` が `CANCELLED` を返す（404 でない）**、資源は解放済み |

> S22 は [§6-1](#6-m1-やり残しの取り込み)（404 ラベル問題）の回帰ガードも兼ねる。
> M1 で見送った「QUEUED 中のサーバ再起動」シナリオは、ラベル方針が本書で確定するため
> **ここで書けるようになる**（[§10](#10-未決事項実装前に決める) Q1 の決定後）。

### 9.3 負荷

`GET /resources` は**キャッシュ有無で挙動が変わる**ため、既存 `grid-storm` に
「全コントローラが 60s ごとに相互の `/resources` を引く」負荷を追加するか検討する
（[§10](#10-未決事項実装前に決める) Q5）。

---

## 10. 未決事項（実装前に決める）

| # | 論点 | 選択肢 | 暫定案 |
|---|---|---|---|
| Q1 | 404/410 ラベルの新しい文言 | (a) 「record が存在しない（サーバ再起動の可能性）」に一本化 / (b) `bodyStarted` で従来どおり出し分け | **(a)**。`bodyStarted` 側はそもそも到達不能で、出し分けが実態に合っていない |
| Q2 | クライアント LR ページからの操作 | (a) 可視化のみ / (b) cancel ボタンを出す | **(a)**。パイプラインが待機中に UI から cancel すると step 側の状態と乖離する |
| Q3 | `GET /lease` に申告値も併記するか | (a) 実効値のみ / (b) `requestedHeartbeatIntervalSeconds` も返す | **(a)**。無視される値を見せると混乱を招く |
| Q4 | `inversePrecedence` を remote キューに適用するか | (a) 適用しない（doc 明記のまま） / (b) 適用する | **(a)**。local と remote で順序規則が二重化する |
| Q5 | `/resources` を負荷テストに含めるか | (a) 含めない / (b) grid-storm に相乗り | 実装後に判断 |
| Q6 | Remote locks を新規タブにするか既存タブ内セクションにするか | (a) 新規タブ / (b) Overview 内セクション | **(a)**。#1035 のタブ構成に素直に乗る |
| Q7 | README 追記（[§6.2](#62-readme-未記載追加分)）を本 PR に含めるか | (a) 本 PR に相乗り / (b) docs 単独 PR | **(a)**。ただし Permissions 表の欠落だけは分量が小さく独立性も高いので、先行して小さい PR にする手もある |
| Q8 | issue 本文の更新をいつ出すか | (a) 本 PR 提出時に一括更新 / (b) 先に本文だけ直してから実装 | **(b)**。[§7](#7-仕様と実装の乖離をどう扱うか) は「実装が正・本文が古い」パターンばかりで、レビュアが本文を正本として読むと齟齬が起きる。**#1055 マージ直後の今が更新の好機** |

---

## 11. 更新履歴

| 日付 | 内容 |
|---|---|
| 2026-07-26 | 初版。issue #1025 の Phase 1 M2/M3 を統合し、M1 やり残し 9 件の取り込み先として定義 |
| 2026-08-05 | #1055 マージ（`018e913`, 2026-08-04）を受けてマージ後 `master` と突き合わせ。§1.3「Phase 1 チェックボックスの可否」＋呼称の整理を追加。§3.1 の `remoteApiEnabled=false` 時の応答を **403 に訂正**（実装と食い違っていた。§9.1 の該当テスト行も同時修正）。§6 に **11: README 未記載**（§6.2）を追加。§7 に **7.5 lockId 一本化 / 7.6 acquire ボディ構造 / 7.7 403 / 7.8 `clientId` 設定 / 7.9 `RemoteUse` 権限の先行実装 / 7.10 Open questions の確定**を追加。§10 に Q7・Q8 を追加 |
