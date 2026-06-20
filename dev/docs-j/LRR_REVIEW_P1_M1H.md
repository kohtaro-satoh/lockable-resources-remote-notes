# Remote LR 開発活動 レビュー（Phase 1 / M1H・PR #1055 CI 指摘対応の起点）

> **位置づけ:** 本レビューは **M1G（純リファクタ）完了・PR #1055 提出後**に本家 CI から提起された事象を対象とし、
> 是正作業を **M1H 開発サイクル**として切り出すための起点レビューである（M1G への追記ではない）。
> **レビュー日:** 2026-06-20
> **対象 PR:** [jenkinsci/lockable-resources-plugin #1055](https://github.com/jenkinsci/lockable-resources-plugin/pull/1055)
>   `feature/1025-remote-lr-p1-m1`（HEAD: `5136daa`、base `master` = `87c4a7e`）。
> **トリガ:** PR 提出後に発生した 2 事象 — ①「本家 master とのコンフリクト疑い」②`github-advanced-security[bot]` の **security 警告 4 件**。
> **対象ドキュメント:** `dev/docs-j/`（M1G 完了記録 = LRR_DESIGN_P1_M1G / LRR_RESULT_P1_M1G、本サイクル = LRR_DESIGN_P1_M1H /
>   LRR_IMPLEMENTATION_STEPS_P1_M1H / LRR_RESULT_P1_M1H）、GitHub PR の checks / review comments。
> **観点:** (a) コンフリクトは実在するか・解消方針は何か、(b) security 4 件それぞれの妥当性と是正方針、
>   (c) とりわけ `GET /acquire/{lockId}` が状態を変更している設計が正しいか。
> **方法:** `gh` による PR メタデータ／checks／review comments の取得、`upstream/master` の fetch と
>   ローカル 3-way マージ（`merge-tree --write-tree` ＋ 実マージ dry-run）、該当コードの静的精読。

---

## 目次

1. [総評](#1-総評)
2. [コンフリクト診断 — 実在しない（master 同期のみ）](#2-コンフリクト診断--実在しないmaster-同期のみ)
3. [security 警告 4 件の内訳](#3-security-警告-4-件の内訳)
4. [#52 の焦点 — なぜ GET が状態を変更しているのか](#4-52-の焦点--なぜ-get-が状態を変更しているのか)
5. [決定: B2（GET を純 read 化）](#5-決定-b2get-を純-read-化)
6. [是正方針まとめ](#6-是正方針まとめ)
7. [この後の開発サイクルへの引き継ぎ](#7-この後の開発サイクルへの引き継ぎ)

---

## 1. 総評

**PR #1055 のコードは健全で、対応すべきは「外部 CI から提起された 4 件の security 警告」のみ。** ユーザーが懸念した
「master コンフリクト」は **現時点では存在しない**（GitHub も `mergeable: MERGEABLE`、ローカル 3-way マージもクリーン）。
`mergeStateStatus: BLOCKED` の理由は `REVIEW_REQUIRED`（メンテナのレビュー待ち）であり、コンフリクトではない。
PR ブランチが master より 2 コミット遅れているため GitHub UI が一時的に「要更新」を表示していたと推測される。

security 4 件のうち 3 件（#49/#50/#51）は Stapler web メソッドの定型的な CSRF/権限ハードニングで、機械的に是正可能。
残る 1 件（#52）は `GET /acquire/{lockId}` が `touchPoll()` で状態を変更している点の指摘で、**設計判断を要する唯一の項目**。
精読の結果、状態遷移自体は GET に依存しておらず、GET の副作用は「QUEUED の見捨てられたクライアント GC」専用と判明。
これを踏まえ **B2（GET を純 read 化し、QUEUED 期限をサーバ側キューの timeout に一本化）** を採用する。

---

## 2. コンフリクト診断 — 実在しない（master 同期のみ）

| 項目 | 値 |
|---|---|
| `mergeable` | `MERGEABLE` |
| `mergeStateStatus` | `BLOCKED`（= `reviewDecision: REVIEW_REQUIRED` が理由。コンフリクトではない） |
| merge-base | `87c4a7e`（PR の base） |
| upstream/master tip | `8f03dbf`（#1056 crowdin bump, #1057 BOM bump） |
| `merge-tree --write-tree` | exit 0・コンフリクトマーカーなし |
| 実マージ dry-run | `Auto-merging pom.xml` → クリーン成功 |

master が触ったファイルは `pom.xml`（#1057 が BOM を `6549...`→`6585...` に bump）と `.github/workflows/crowdin.yml`。
本 PR も `pom.xml` を触る（`credentials` 依存追加・別ハンク）が、両者は別領域のため自動マージ可能。

**結論:** コンフリクトは無し。`upstream/master` への rebase（または merge）で 2 コミット遅れを解消すれば足りる。
security 修正コミットを積む際に同時に取り込む。

---

## 3. security 警告 4 件の内訳

`github-advanced-security[bot]` が PR にインラインレビューコメントとして提起（CI チェック "Jenkins Security Scan"
自体はブロックせず pass 表示だが、bot コメントはメンテナの目に付く。**クロスリポ PR のためアラート dismiss は投稿者側で不可** →
コードで是正するのが現実的）。

| alert | 箇所 | ルール | 現状 |
|---|---|---|---|
| [49](https://github.com/jenkinsci/lockable-resources-plugin/security/code-scanning/49) | `RemoteConnection.DescriptorImpl#doCheckUrl` | Stapler: Missing permission check | 権限チェック **無し** |
| [51](https://github.com/jenkinsci/lockable-resources-plugin/security/code-scanning/51) | 同上 | Stapler: Missing POST/RequirePOST（CSRF） | 注釈 **無し** |
| [50](https://github.com/jenkinsci/lockable-resources-plugin/security/code-scanning/50) | `LockableResourcesManager#doCheckForcedServerId` | Stapler: Missing POST/RequirePOST（CSRF） | `Jenkins.ADMINISTER` チェックは既設・注釈のみ欠 |
| [52](https://github.com/jenkinsci/lockable-resources-plugin/security/code-scanning/52) | `RemoteApiV1Action.AcquireStatusResource#doIndex` | Stapler: Missing POST/RequirePOST（CSRF） | `REMOTE` 権限チェック有り・**GET で状態変更**している点が flag |

- **#49/#51（doCheckUrl）**: 大域設定（admin 操作）の descriptor 検証。`@POST` ＋ `Jenkins.get().checkPermission(Jenkins.ADMINISTER)`
  を付与し、`RemoteConnection/config.jelly` の `url` フィールドに `checkMethod="post"` を足す（@POST 化すると検証リクエストが
  POST になるため、jelly 側の指定が無いと GET 検証が 405 になる）。
- **#50（doCheckForcedServerId）**: 既に ADMINISTER チェック有り。`@POST` 付与のみ＋ `LRM/config.jelly` の
  `forcedServerId` に `checkMethod="post"`。
- **#52（doIndex）**: 次章で詳述。

---

## 4. #52 の焦点 — なぜ GET が状態を変更しているのか

### 4.1 状態遷移は GET ポーリングに依存していない

QUEUED→ACQUIRED の昇格も、タイムアウトでの失敗も、**すべてサーバ側ローカルロジックが所有**する。GET は無関与。

- POST `/acquire` が busy なら統一キューへ登録（`RemoteLockManager.enqueue` → `lrm.queueRemote(entry)`）。
- ローカル `lock()` ステップと肩を並べて優先度ディスパッチ（`LockableResourcesManager.proceedNextContext` →
  `proceedRemoteEntry`）。
- 取得可否は `proceedNextContext()`（キュー昇格）と 1 秒周期 `PeriodicWork`（`RemoteLockManager.doRun`）が決める。
- **タイムアウトもサーバ側完結**: `RemoteQueueEntry` が `timeoutForAllocateResource` から `timeoutDeadlineMillis` を保持し、
  `getNextRemoteEntry()` / scheduled timeout task が期限切れを FAILED にする。

クライアント側 `RemoteLockSession.pollStatus` の `case QUEUED: return;` が示すとおり、GET は
**「ACQUIRED になったら body を起動する」ために状態を読むだけ**で、遷移を駆動していない。＝ short polling。

### 4.2 GET が `touchPoll()` で変更する唯一の理由

QUEUED の「**見捨てられたクライアントの GC**」専用。

- ローカル `lock()` の待ち手は「生きたスレッド／Run」で、ビルド abort 時にキューエントリが消える。
- リモートの待ち手は **レコードだけ**で、紐づく生きたスレッドが無い。「まだ生きていて欲しいか」を知る手段が無い。
- そこで「GET を打ち続けている＝生存」とみなし、ポーリング停止後 `getQueuePollExpiryMs()`（= `STALE_THRESHOLD` =
  `max(heartbeat*6, 60)s`）で QUEUED を `QUEUE_EXPIRED` にする（`maybeScanStale` の QUEUED 分岐）。

**重要:** この keepalive が実効を持つのは `timeoutForAllocateResource == 0`（無限待ち）の場合のみ。有限タイムアウトなら
`RemoteQueueEntry` の deadline が既に面倒を見る。つまり touchPoll は「無限待ちのクライアントが死んだ時に ~60 秒でキュー枠を
回収する保険」にすぎず、QUEUED 中はリソースを掴んでいないため fail-safe（枠のみ保持）。

---

## 5. 決定: B2（GET を純 read 化）

「GET は read-only であるべき」という指摘は正しい。#52 をコードの band-aid（status を POST 化）で潰すのではなく、
**正しい設計の帰結として自然に消す**。検討した 3 案のうち B2 を採用。

| 案 | 内容 | 評価 |
|---|---|---|
| B1 | GET 純 read＋keepalive を POST `/lease` heartbeat に寄せ、QUEUED から heartbeat 開始 | 速い GC を維持・REST も綺麗だが、QUEUED 中に poll+heartbeat の 2 チャネルが走り改修が大きい |
| **B2（採用）** | GET から `touchPoll` 除去＝純 read、QUEUED 期限をサーバ側キュー timeout に一本化 | 最小・設計観（遷移はサーバ側ローカルロジック所有）に最も忠実・#52 が自然消滅 |
| B3 | status GET を POST 化 | 症状治療・read を mutation にする・非 RESTful。**却下** |

**B2 で捨てる挙動（明文化）:** `timeoutForAllocateResource == 0`（無限待ち）かつクライアントが死亡した QUEUED 枠が、
従来 ~60 秒で `QUEUE_EXPIRED` 回収されていたのが、回収されなくなる。ただし:
- QUEUED 中はリソース非保持（枠のみ）。
- 昇格された場合は ACQUIRED の heartbeat-STALE 機構が回収する。
- 「無限待ちを要求した以上、無限に待つ」はローカル `lock()`（timeout 無し）と整合する。

→ 失うのは「無限待ち＋死亡クライアント」という限定コーナーケースの早期回収のみ。許容と判断。

---

## 6. 是正方針まとめ

| # | 是正 | 種別 |
|---|---|---|
| 49/51 | `doCheckUrl` に `@POST` ＋ `checkPermission(ADMINISTER)`、jelly に `checkMethod="post"` | 機械的 |
| 50 | `doCheckForcedServerId` に `@POST`、jelly に `checkMethod="post"` | 機械的 |
| 52 | **B2**: `doIndex` の `touchPoll` 除去（GET 純 read）、poll-keepalive 一式撤去、QUEUED 期限を `RemoteQueueEntry` deadline に一本化 | 設計変更 |
| — | `upstream/master` へ rebase（コンフリクト無し） | 同期 |

撤去対象（B2）: `RemoteApiV1Action.doIndex` の `touchPoll` 呼び出し / `RemoteLockManager` の `touchPoll`・
`getQueuePollExpiryMs`・`DEFAULT_QUEUE_POLL_EXPIRY_MS`・`maybeScanStale` の QUEUED 分岐 / `RemoteLockRecord` の
`lastPolledAt`・`polled()`・`getLastPolledAt()`。テストは `RemoteLockManagerTest` の poll-keepalive 2 本を
「キュー timeout で QUEUED 失効」「GET は QUEUED 寿命に無影響」へ置換。

---

## 7. この後の開発サイクルへの引き継ぎ

本レビューの結論（B2 ＋ #49/#50/#51 機械修正 ＋ master 同期）を **M1H 開発サイクル**として実装する（M1G とは別サイクル）。
設計は `LRR_DESIGN_P1_M1H.md`、手順は `LRR_IMPLEMENTATION_STEPS_P1_M1H.md` を新規作成し、
`run-mvn-verify`（CI 等価ゲート＝全テスト＋静的ゲート）＋ `run-e2e` 全件を通したうえで
`LRR_RESULT_P1_M1H.md` を作成、plugin・notes を commit（push しない）。
