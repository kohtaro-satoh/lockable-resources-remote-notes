# Remote LR レビュー — mPokornyETM 氏 追加 PR ブランチ `feature/1025-remote-lr-followup-ux`

> **位置づけ:** PR [#1055](https://github.com/jenkinsci/lockable-resources-plugin/pull/1055) のレビュー中、
> メンテナ Martin Pokorny 氏（`mPokornyETM`）が予告どおり「this branch ベースの UX/docs 改善」を
> `jenkinsci` 側のブランチとして push してきた（当方 PR への追加提案）。
> 本書はその**内容の詳細解析と、当方の従来 head `e83534b` との実挙動差分の検証記録**である。
> **レビュー日:** 2026-07-25 〜 2026-07-26
> **対象:** `jenkinsci/lockable-resources-plugin` ブランチ `feature/1025-remote-lr-followup-ux`（HEAD `8fd2193`）
>   = [kohtaro-satoh/lockable-resources-plugin#1](https://github.com/kohtaro-satoh/lockable-resources-plugin/pull/1)
> **比較基準:** `e83534bff02bf096097e01e8c04795e13dd70bfe`（当方の最後のコミット。
>   現 PR #1055 head は氏が push した `3a555fe`＝[§2.2](#22-pr-の関係とcrlf-がすでに-pr-1055-に入っている件)）
> **検証方法:** (a) 全差分の静的精読、(b) `run-mvn-verify.sh`（CI ゲート同等）、(c) `run-e2e.sh --clean-start` 全 21 件、
>   (d) `run-load.sh --preset stress`、(e) `dev/jenkins-env` 4 コンテナ実機での before/after 実測、
>   (f) 氏の新規テストを `e83534b` の worktree に移植して**旧コードで落ちるか**の確認。

---

## 目次

1. [総評](#1-総評)
2. [ブランチ構成とコミット](#2-ブランチ構成とコミット)
3. [変更の全体像](#3-変更の全体像)
4. [解析① 実バグ修正 — HTTP ステータスの取りこぼし](#4-解析-実バグ修正--http-ステータスの取りこぼし)
5. [解析② UI — Held By 列と Queue タブ](#5-解析-ui--held-by-列と-queue-タブ)
6. [解析③ 設定 UI — credentials セレクタと help リンク](#6-解析-設定-ui--credentials-セレクタと-help-リンク)
7. [解析④ 環境変数 `X_SERVER_ID` / `X_LOCK_ID`](#7-解析-環境変数-x_server_id--x_lock_id)
8. [解析⑤ JCasC `@Symbol` と `flushPendingSave` 防御](#8-解析-jcasc-symbol-と-flushpendingsave-防御)
9. [解析⑥ 追加ドキュメント 2 本](#9-解析-追加ドキュメント-2-本)
10. [解析⑦ 追加テスト](#10-解析-追加テスト)
11. [実機検証ログ（before / after）](#11-実機検証ログbefore--after)
12. [指摘事項](#12-指摘事項)
13. [取り込み方針と現況](#13-取り込み方針と現況)
14. [付録: 再現コマンド](#14-付録-再現コマンド)

---

## 1. 総評

**内容は総じて質が高く、取り込むべき。** とくに `RemoteApiClient` の変更は「体裁の改善」ではなく**当方が作り込んでいた
実バグの修正**であり、これ単体でも取り込む価値がある。UI 2 点（Held By 列 / Queue タブ）は Phase 1 で意図的に
後回しにしていた「remote ロックがダッシュボードから見えない」問題を的確に埋めている。

**動作面の回帰はゼロ**。氏のブランチ `8fd2193` に対して当方の検証一式を通した結果:

| 検証 | 結果 |
|---|---|
| `run-mvn-verify.sh`（CI ゲート同等） | テスト **394/0/1skip**、spotbugs/checkstyle/pmd **ok**、**spotless のみ FAIL** |
| `run-e2e.sh --clean-start` | **21/21 PASS・fail 0** |
| `run-load.sh --preset stress`（200 並列 × 2 本） | **mutual-exclusion overlap 0 / HUNG 0**、失敗は全件クリーンな `LOCK_WAIT_TIMEOUT` |

一方で、**そのままではマージできない**。ブランチのベースに含まれる氏の `22c7b2b "spotles"` が
`LockableResource.java` を丸ごと CRLF に変換しており、`spotless:check` だけが BUILD FAILURE になる
（＝ ci.jenkins.io の `buildPlugin` が落ちる）。実質 13 行の変更が 1739 行の差分に膨れているのも同じ原因。
**しかもこの CRLF は氏が push した merge `3a555fe` 経由ですでに PR #1055 に入っており、
#1055 の CI は現時点で赤**（[§2.2](#22-pr-の関係とcrlf-がすでに-pr-1055-に入っている件)）。
行末を LF に戻すだけで解消する軽微な問題だが、**master 着地前に必ず潰す必要がある**。

| 判定 | 件数 | 内訳 |
|---|---|---|
| ✅ 実バグ修正（要取り込み） | 1 | HTTP ステータス取りこぼし（`RemoteApiClient.send`） |
| ✅ 機能追加・改善（取り込み推奨） | 6 | Held By 列 / Queue タブ / credentials セレクタ / 環境変数 2 種 / 診断ログ / JCasC `@Symbol` |
| ✅ ドキュメント（取り込み推奨） | 2 | `remote-api-curl.md` / `remote-lock-pipeline-pattern.md` |
| ✅ テスト（取り込み推奨） | 4 群 | CasC 3 件 / EnvVars 3 件 / LockStepRemote 1 件 / RemoteApiClient 1 件 |
| ⛔ ブロッカー | 1 | CRLF 混入 → `spotless:check` 失敗 |
| ⚠️ 要相談・要修正 | 7 | help URL 表記の二分 / Queue 行の Change Position ボタン ほか（[§12](#12-指摘事項) #2-#8） |
| ℹ️ 情報・将来課題 | 4 | credentials ドメイン整合 / テストのリフレクション依存 ほか（[§12](#12-指摘事項) #9-#12） |

---

## 2. ブランチ構成とコミット

```
*   8fd2193 Merge branch 'feature/1025-remote-lr-p1-m1' into feature/1025-remote-lr-followup-ux
|\                                                                  ← 氏の PR #1 head
| *   3a555fe Merge branch 'feature/1025-remote-lr-p1-m1' of kohtaro-satoh/...
| |\                                                                ← ★現 PR #1055 head（氏が push）
| | * e83534b Fix remote config help links returning 404 (Not Found)   ← 旧 PR #1055 head
* | c8162cf other findings
* | bd48b1e more things
* | 77d36a8 more docs
* | 64b0e14 docs: add Remote Lock REST API curl examples
* | 9ffade8 Remote LR UX follow-up: credentials selector, better diagnostics, heldBy column
|/
* 22c7b2b spotles                                                      ← ★CRLF 混入元
* 7fd218b Report a remote acquire timeout as LOCK_WAIT_TIMEOUT ...      ← 当方 M1I
```

| commit | 日時 | 主題 | 変更 |
|---|---|---|---|
| `22c7b2b` | 07-16 | `spotles` | `LockableResource.java` を CRLF 化のみ（`-w` 差分は**空**、863+/863-） |
| `9ffade8` | 07-19 | UX follow-up | credentials セレクタ / 診断強化 / heldBy 列（9 ファイル） |
| `64b0e14` | 07-19 | docs | `remote-api-curl.md` 新規（+248） |
| `77d36a8` | 07-21 | more docs | curl doc に priority/inversePrecedence 節を追記（+47/-1） |
| `bd48b1e` | 07-22 | more things | Queue タブ remote 表示 / 環境変数 / pipeline パターン doc（8 ファイル、+388/-13） |
| `c8162cf` | 07-22 | other findings | JCasC `@Symbol`＋テスト / `flushPendingSave` 防御（5 ファイル、+78/-13） |

> コミットメッセージが `more things` / `other findings` と粗い。**本家へ出す前に squash か
> メッセージ整形を依頼したほうがよい**（[§13](#13-取り込み方針と現況)）。

### 2.1 CRLF は誰が入れたか — 履歴で確定

「元は CRLF で、当方 PR が LF に変えてしまったのを氏が戻したのではないか」という疑いを潰すため、
`LockableResource.java` の行末を全リビジョンで数えた。**答えは No。当方は一度も行末を変えていない。**

| リビジョン | CR 数 | 内容 |
|---|---|---|
| `origin/master` (`4dbbfc1`) | **0** | 上流 master |
| master 履歴で当該ファイルを触った全 40 コミット | **すべて 0** | 上流では一貫して LF |
| `73a2d3b` | **0** | 当方 PR 初手（Remote Lockable Resources phase 1） |
| `a267ad5` / `3fdef28` / `6ea49f6` / `7fd218b` | **0** | 当方の以降の全コミット |
| `e83534b` | **0** | 当方の最後のコミット（旧 PR #1055 head） |
| **`22c7b2b`（Martin, 2026-07-16「spotles」）** | **863** | ★ここで初出 |
| **`3a555fe`** | **863** | ★氏が当方ブランチへ push した merge = **現 PR #1055 head** |
| `8fd2193` | 876 | 氏の PR #1 head |

さらに **上流 master の全ファイルを走査**したところ、CRLF を含むのは
`src/test/resources/plugins/jobConfigHistory.hpi`（バイナリの .hpi）のみ。**このリポジトリのテキストは
全ファイル LF が確立した規約**であり、CRLF 化は復元ではなく規約違反の持ち込みである。

**加えて、`22c7b2b` の親 `7fd218b` で `mvn spotless:check` は BUILD SUCCESS**（実測）。
つまり氏が整形しようとした時点で整形違反は 1 件も無かった。

**`22c7b2b` の実質変更はゼロ**であることをバイト単位で確認した。変更ファイルは
`LockableResource.java` 1 本のみで、そこから CR を除去すると `7fd218b` の版と完全一致する:

```
before (7fd218b)       : 29620 bytes  sha256=8af6723cb487cae6…
after  (22c7b2b, LF化) : 29620 bytes  sha256=8af6723cb487cae6…  → 完全一致
```

`git diff -w`（全空白無視）だけでなく行末正規化後のバイト比較でも同一なので、コード・インデント・
行末空白・import 順・末尾改行のいずれも変わっていない。**LF に戻せば内容は完全に元通りになる**
（氏に伝える際の安心材料）。

> **推定される機構（断定はできない）**: Windows 環境で `mvn spotless:apply` を実行した際の既知の踏み方。
> spotless の `lineEndings` 既定は `GIT_ATTRIBUTES` で、リポジトリに `.gitattributes` が無いと
> git の `core.autocrlf` / `core.eol` に委譲される。Windows で `core.autocrlf=false`（または未設定）だと
> spotless が作業ツリーへ CRLF を書き戻し、git もそのままコミットしてしまう。
> `.gitattributes` に `*.java text eol=lf` を置けば環境に依らず再発しない（[§12-1](#12-指摘事項)）。

### 2.2 PR の関係と、CRLF がすでに PR #1055 に入っている件

氏の変更は **[kohtaro-satoh/lockable-resources-plugin#1](https://github.com/kohtaro-satoh/lockable-resources-plugin/pull/1)**
「Enhance Remote LR UX with credentials selector and diagnostics」として当方フォークに提出された。

| 項目 | 値 |
|---|---|
| base | `feature/1025-remote-lr-p1-m1`（= PR #1055 の head ブランチ） |
| head | `feature/1025-remote-lr-followup-ux`（`8fd2193`） |
| mergeable | `MERGEABLE` / `CLEAN` |
| PR #1 のコミット | `9ffade8` `64b0e14` `77d36a8` `bd48b1e` `c8162cf` `8fd2193` の 6 本 |

**重要: `22c7b2b` は PR #1 の差分に含まれていない。** 氏が 2026-07-22 に merge `3a555fe`
（= `22c7b2b` + `e83534b`）を**当方ブランチへ直接 push した**ため、CRLF はすでに base 側に入っている
（maintainer edit 権限。同権限での force-push リベースは 2026-07-16 にも実施済み）。

その結果:

- **PR #1055 の head は `e83534b` ではなく `3a555fe`** で、**CRLF はすでに PR #1055 に入っている**
- **PR #1055 の CI は現在赤**（ci.jenkins.io PR-1055 #10、`linux-25 / Build` が exit 1。
  `3a555fe` に対する `mvn spotless:check` の BUILD FAILURE をローカルで再現確認済み）
- PR #1 の Files changed で `LockableResource.java` が `13+ 0-` としか出ないのはこのため
  （base・head とも CRLF なので差分に現れない）

**取り込み順序に制約がある**（実マージで検証済み）:

| 順序 | 結果 |
|---|---|
| 先に当方が LF 修正 → 氏の PR #1 をマージ | ❌ `LockableResource.java` が **CONFLICT**（行末変更で全 876 行が「変更行」になるため） |
| 氏の PR #1 をマージ → その後 LF 修正 | ✅ 衝突なし。LF 化後 `spotless:check` **BUILD SUCCESS**、`git diff -w 8fd2193` は空 |
| 氏が followup-ux 側で先に LF 修正 → マージ | ✅ 衝突なし（当方ブランチ側が不変のため） |

→ **当方が先に直すのは不可**。「PR #1 マージ後」または「氏が自分のブランチで先に」のいずれか。
氏が「レビューしてくれたら一緒にマージして go live しよう」と述べているため、
**氏に `feature/1025-remote-lr-p1-m1` 側での LF 復元を依頼**する方針とした（2026-07-26 approve 済み）。

---

## 3. 変更の全体像

`git diff --stat -w e83534b..8fd2193`（空白差分を除外）＝ **20 ファイル / +907・-26**。

| 領域 | ファイル | 増減（`-w`） |
|---|---|---|
| **バグ修正** | `remote/RemoteApiClient.java` | +40 / -5 |
| **診断ログ** | `remote/RemoteLockSession.java` | +20 / -2 |
| **UI（資源表）** | `LockableResource.java` / `tableResources/table.jelly` / `table.properties` | +13 / +20 / +1 |
| **UI（キュー）** | `actions/LockableResourcesRootAction.java` / `webapp/js/lockable-resources.js` | +100 / -12、+4 |
| **設定 UI** | `RemoteConnection.java` / `RemoteConnection/config.jelly` / `help-credentialsId.html` | +27、±4、+5 / -1 |
| **環境変数** | `LockStepExecution.java` | +26 / -1 |
| **JCasC / 堅牢化** | `LockableResourcesManager.java` | +17 / -1（うち queue getter +11） |
| **ドキュメント** | `src/doc/examples/{readme,remote-api-curl,remote-lock-pipeline-pattern}.md` | +425 |
| **テスト** | 4 テストファイル＋CasC yml | +205 |

`git diff --stat`（空白込み）では `LockableResource.java` が 1739 行になるが、**実体は 13 行の追加のみ**。
残り 1726 行は `22c7b2b` の CRLF 化に由来する。

---

## 4. 解析① 実バグ修正 — HTTP ステータスの取りこぼし

### 4.1 何が壊れていたか

`RemoteApiException extends IOException`。ところが `e83534b` の `RemoteApiClient.send()` は
**HTTP 4xx/5xx 用に投げた `RemoteApiException` を、同じ `try` の `catch (IOException)` が拾って再ラップ**していた。

```java
// e83534b（当方）— RemoteApiClient.java:242-265
try {
    HttpResponse<String> response = httpClient.send(request, ...);
    if (status >= 400) {
        throw new RemoteApiException(msg, status, serverId, remoteCode);  // ← try の内側で throw
    }
    return response;
} catch (InterruptedException ex) { ... }
catch (IOException ex) {                       // ← RemoteApiException IS-A IOException
    LOGGER.log(WARNING, "Remote API communication failure (fail-closed): ...");
    throw new RemoteApiException("Remote API communication failure: " + method + " " + path, ex, serverId);
    //                                                    ↑ この 3 引数コンストラクタは httpStatus = -1, remoteCode = null
}
```

結果、**リモートが返した 400/403/404/410 が、すべて `httpStatus=-1` / `remoteCode=null` の
「communication failure」に化けていた**。

### 4.2 実測による確定

氏の新規テスト `testHttp404PreservesRemoteDetailsWithoutCommunicationFailureWrap` を
`e83534b` の worktree に移植して実行：

```
[ERROR] RemoteApiClientTest.testHttp404PreservesRemoteDetailsWithoutCommunicationFailureWrap:156
        expected: <404> but was: <-1>
[ERROR] Tests run: 6, Failures: 1, Errors: 0, Skipped: 0
```

**旧コードで確実に落ちる = 実バグ修正であることが確定。**

### 4.3 影響範囲 — M1I の「安全網」が死んでいた

`RemoteLockSession.pollOnce()` は `getHttpStatus()` で 404/410 を判定して分岐する：

```java
// RemoteLockSession.java:253
int httpStatus = ((RemoteApiException) ex).getHttpStatus();
if (httpStatus == 404 || httpStatus == 410) {
    // (a) body 未開始 → LOCK_WAIT_TIMEOUT に正規化（M1I の安全網）
    // (b) body 開始済 → 「サーバ再起動でリース消失」として即失敗
}
```

`httpStatus` が常に `-1` だったため、**この分岐は一度も成立していなかった**。実際には
`consecutivePollFailures` を数える「一過性ネットワーク障害」の側に落ち、しきい値
`MAX_CONSECUTIVE_POLL_FAILURES` に達するまでリトライしてから失敗していた。

> **M1I が E2E で PASS していた理由**（重要）: M1I の本命修正はサーバ側の
> `terminalAt` 起点 TTL（terminal record を保持し、クライアントの poll に
> `state=FAILED, errorCode=LOCK_WAIT_TIMEOUT` を返す）である。S18 が緑だったのはそちらの効果で、
> クライアント側 404 正規化は `LRR_RESULT_P1_M1I.md` にも「安全網」と書いたとおりの二次防御だった。
> つまり **M1I の結論自体は正しかったが、二重化したはずの防御が片肺だった**。氏の修正で両肺になる。

### 4.4 修正内容

```java
    return response;
+} catch (RemoteApiException ex) {
+    throw ex;                       // ← 自前の例外は素通し
 } catch (InterruptedException ex) { ...
```
加えてメッセージを大幅に情報化（`serverId` / `errorCode` / リモートの `message` / 404 時のヒント）し、
`extractRemoteMessage()`（`abbreviateForLog` でクランプ済み）を新設。

### 4.5 実機 before / after

**before（`e83534b`、E2E レポート `20260719092233-e2e-test/remote-unknown-rejected/console.txt`）**
```
Trying to acquire remote lock on [Resource: s17-unknown-1784421183] (serverId=b)
org.jenkins...RemoteApiException: Remote API request failed: POST /acquire/ returned HTTP 404
Caused: org.jenkins...RemoteApiException: Remote API communication failure: POST /acquire/
```
→ 外側（＝プログラムが見る例外）は「communication failure」。404 は stack trace の cause にしか残らない。

**after（`8fd2193` を 4 コンテナへデプロイして実行）**
```
Trying to acquire remote lock on [Resource: definitely-not-there] (serverId=b, serverUrl=http://jenkins-b:8080/jenkins)
Remote lock request failed (serverId=b, serverUrl=http://jenkins-b:8080/jenkins):
  Remote API request failed: POST /acquire/ returned HTTP 404
  (serverId=b, errorCode=UNKNOWN_RESOURCE, message=No lockable resource matches the request).
  Verify the remote base URL/context path and that the target resource or label exists and is exposed by exposeLabel.
```

**E2E 互換性**: `scenarios/fail-closed.sh` の判定正規表現は
`auth-error` = `HTTP 401|HTTP 403|returned HTTP 401|returned HTTP 403|Sign in to access`、
`remote-down` = `Remote API communication failure|Connection refused|...`。
新メッセージは前者に `returned HTTP 403` で合致し、後者は真の I/O 障害で従来どおり
"communication failure" になるため、**既存 E2E アサーションは無改修で通る見込み**。

---

## 5. 解析② UI — Held By 列と Queue タブ

### 5.1 資源表 Held By 列（`9ffade8`）

`e83534b` の `table.jelly` は Held By 列で `reservedBy` → `locked` → `queued` の順に判定する。
remote ロック中の資源は `remoteLockedBy != null` かつ `locked == true` だが `build == null` なので、
`${resource.build.url}` が空に評価され **`<a href="/jenkins/"></a>`（空文字の壊れたリンク）**が出ていた。

実測（before, `e83534b`）:
```html
<td class="jenkins-!-warning-color"><strong>LOCKED</strong> by Remote: doc-verify-label</td>
<td><a href="/jenkins/" class="jenkins-table__link"></a></td>   ← Held By が空＋壊れリンク
```

氏は `remoteLockedBy != null` の分岐を `locked` の**前**に挿入し、`LockableResource#getRemoteLockRecord()`
（新設、`RemoteLockManager.get().find(...)` を引く）経由で clientId と要求内容を表示。

実測（after, `8fd2193`）:
```html
<td class="jenkins-!-warning-color"><strong>LOCKED</strong> by Remote: martin-demo-holder</td>
<td><span class="jenkins-table__cell__text"><strong>martin-demo-holder</strong>
    <br><span class="jenkins-!-color-secondary">s01-a-resource-1784417904</span></span></td>
```

レコードが取れない場合は `resource.heldBy.remoteUnknown = (remote, details unavailable)` にフォールバック。
`access-modifier-checker` は通過済み（`@Restricted(NoExternalUse)` な `RemoteLockRecord` を
同一プラグイン内から参照しているだけなので問題なし）。

### 5.2 Queue タブへの remote 待機表示（`bd48b1e`）

`e83534b` では remote の待機（`RemoteQueueEntry`）が**ダッシュボードのキューに一切出ない**。
氏は以下を追加：

- `LockableResourcesManager#getCurrentRemoteQueueEntries()`（`syncResources` 下でスナップショット、read-only）
- `Queue#add(RemoteQueueEntry)` と `QueueStruct(RemoteQueueEntry)` コンストラクタ
- `QueueStruct` に `remote` / `requestedBy` / `requestedByUrl` / `remoteReason` / `remoteRequest` フィールド
- `buildRemoteRequestText()`（`resource=` / `label=` + `quantity=` / `extra=N` を組み立て）
- `getQueuePage` JSON に `type: "remote"` を追加、JS `renderRow()` に `Remote API` 行を追加
- `requestedBy` の取得を `item.getBuild().getFullDisplayName()` 直参照から `item.getRequestedBy()` に集約
  （local/remote 両対応。ローカル側の値は従来と同一）

実測（before / after、同一の QUEUED remote 待機を作った状態で `POST /lockable-resources/getQueuePage`）:

| | before (`e83534b`) | after (`8fd2193`) |
|---|---|---|
| `total` | `0` | `1` |
| items | `[]` | `type: "remote"`, `id: <lockId>`, `priority: 7`, `requestedBy: "martin-demo-waiter"`, `request: "resource=s01-a-resource-1784417904"`, `reason: "doc verification wait"` |

clientId 未指定時は `"Remote API"` にフォールバックする実装。

---

## 6. 解析③ 設定 UI — credentials セレクタと help リンク

### 6.1 credentials をテキストボックスからドロップダウンへ（`9ffade8`）

`RemoteConnection/config.jelly` の `credentialsId` を `<f:textbox/>` → `<f:select/>` に変更し、
`DescriptorImpl#doFillCredentialsIdItems(credentialsId, url)` を追加。

- `@POST` ＋ `Jenkins.ADMINISTER` チェック。権限なしなら `includeCurrentValue` のみ返す（情報漏洩なし）
- `StandardUsernamePasswordCredentials` で絞り込み。これは実際に認証ヘッダを組む
  `RemoteCredentials.basicAuthHeader()` が探す型と**一致**しており整合が取れている
- `URIRequirementBuilder.fromUri(Util.fixEmptyAndTrim(url))` でドメイン要件を組む。
  `fromUri(null)` は credentials-plugin 側で null 安全（`withUri` が null を無視）

実機で fill エンドポイントを直接叩いて確認（`8fd2193`）:
```
POST /jenkins/descriptorByName/....RemoteConnection/fillCredentialsIdItems  → HTTP 200
{"_class":"...StandardListBoxModel","values":[{"name":"- none -","value":""},
 {"name":"admin/****** (E2E generated ...)","value":"s01-a-for-b"}, ... {"value":"load-d-token"}]}
GET（crumb なし）→ HTTP 404（@POST が正しく効いている）
```
グローバル設定ページのレンダリングも確認：
`<select fillUrl=".../fillCredentialsIdItems" fillDependsOn="credentialsId url" name="_.credentialsId">`。

**help テキストの改善**も的確で、氏が実際に踏んだ罠が書かれている：
> Using username + account password may fail with HTTP 403 due to CSRF/crumb handling on the remote server.

これは**実機で再現を確認した**（[§11.1](#111-認証-api-token-vs-パスワード)）。当方の help はここに触れていなかった。

### 6.2 help リンク `/descriptor/` → `/descriptorByName/`

`RemoteConnection/config.jelly` の 3 箇所を `/descriptor/...` から `/descriptorByName/...` に変更。

**これは 404 修正ではない。** Jenkins core `jenkins.model.Jenkins` において
`getDescriptorByName(String)` は `getDescriptor(String)` の **alias**（core ソースのコメントに明記）であり、
両者は同一ルート。実機でも当方 `e83534b` ビルドに対して両形式 6 URL すべて **HTTP 200** を確認した。

さらに Jenkins core `Descriptor#getHelpFile(Klass, String)` が自動生成する URL は
`"/descriptor/" + getId() + "/help"` 側である。したがって **当方 `e83534b` の書き方のほうが core の
既定に沿っている**。氏の変更自体は無害だが、

- 同一プラグイン内の `LockableResourcesManager/config.jelly` は `/descriptor/` のまま 5 箇所残っており、
  **プラグイン内で表記が二分した**

という副作用がある。どちらかに寄せるべき（[§12-2](#12-指摘事項)）。

---

## 7. 解析④ 環境変数 `X_SERVER_ID` / `X_LOCK_ID`

`LockStepExecution#withRemoteMetadata()` を新設し、**remote ロックのボディに限り**
`variable` 名 `X` に対して `X_SERVER_ID` と `X_LOCK_ID` を追加注入する（`bd48b1e`）。

```groovy
lock(label: 'plc', quantity: 2, serverId: 'remote-server-1', variable: 'PLC') {
  echo "${env.PLC}"            // plc-a,plc-b     （従来どおり）
  echo "${env.PLC0_ip}"        // 10.0.0.11       （従来どおり）
  echo "${env.PLC_SERVER_ID}"  // remote-server-1 （新規）
  echo "${env.PLC_LOCK_ID}"    // lock-1          （新規）
}
```

**評価:**
- ローカル `lock()` には一切追加されない（`remoteSession == null` で早期 return）ため、
  M1A 以来の「透過的等価性」を壊さない。設計として妥当。
- 既存の env 命名（`X`, `X0`, `X0_<prop>`）と衝突しない。`X_SERVER_ID` はインデックス無しなので
  プロパティ由来の `X0_ip` 形式とは名前空間が交わらない。
- ただし呼び出しが `if (lockEnvVars != null && !lockEnvVars.isEmpty())` の内側にあるため、
  **リモートが `lockEnvVars` を空で返した場合は `X_SERVER_ID`/`X_LOCK_ID` も注入されない**。
  `variable` 指定時にサーバが空を返す経路は現状ないが、契約としては弱い（[§12-6](#12-指摘事項)）。
- `@edu.umd.cs.findbugs.annotations.CheckForNull` を import せず FQCN でインラインに書いている。
  同ファイルは既に同パッケージの `NonNull` を import 済みなので、スタイル上は import に寄せたい。

---

## 8. 解析⑤ JCasC `@Symbol` と `flushPendingSave` 防御

### 8.1 `@Symbol("lockableResourcesManager")`（`c8162cf`）

`LockableResourcesManager` に `@Symbol` を付与。**JCasC のキー名を明示的に固定する**変更。

**検証:** 氏の新規 CasC テスト 3 件を `@Symbol` のない `e83534b` worktree に移植して実行したところ
**7/7 PASS**。つまり `@Symbol` が無くても JCasC は `lockableResourcesManager` として解決されていた
（`GlobalConfiguration` の既定はクラス名の decapitalize であり、たまたま同一）。

→ **バグ修正ではなく、将来のクラス名変更で JCasC キーが暗黙に壊れることを防ぐ堅牢化**。
JCasC schema/export 上も明示されるので、取り込んでよい。

### 8.2 `flushPendingSave()` の null 許容（`c8162cf`）

```java
-LockableResourcesManager lrm = LockableResourcesManager.get();
+LockableResourcesManager lrm = GlobalConfiguration.all().get(LockableResourcesManager.class);
+if (lrm == null) { return; }
```

`LockableResourcesManager.get()` は解決できないと `IllegalStateException` を投げる。`@Terminator` は
Jenkins シャットダウン時（ExtensionList が既に壊れかけている可能性がある局面）に走るため、
そこで例外を出さないようにした防御的変更。今回の `mvn verify` / CasC テストのログには
`LockableResourcesManager is not registered` は出ておらず、**実害の再現は取れていない**（純粋な予防）。

> 微差だが、`get()` にあった `Jenkins.get().getDescriptorByType(...)` フォールバックが無くなる。
> `GlobalConfiguration.all()` から引けないが descriptor は生きている、という状況では
> **保留中の save が flush されず静かにスキップされる**。実運用で起きる経路は考えにくいが仕様の縮小ではある。

---

## 9. 解析⑥ 追加ドキュメント 2 本

### 9.1 `src/doc/examples/remote-api-curl.md`（293 行）

Pipeline を使わない外部スクリプト向けの curl レシピ集。acquire → poll → heartbeat → release の
完全なシェルスクリプト、label/skipIfLocked/timeout/priority の例、API リファレンス表。

**実機で全項目を突き合わせ検証した（`8fd2193` デプロイ後の jenkins-a）。結果は下表。**

| doc の記述 | 実測 | 判定 |
|---|---|---|
| `POST /acquire/` → 202 `{lockId, state}` | 202 `{"lockId":"...","state":"ACQUIRED"}` | ✅ |
| `GET /acquire/{lockId}/` → 200 + `lockEnvVars` | 200、`variable` 指定時に `RES`/`RES0`/... を返す | ✅ |
| `POST /lease/{id}/heartbeat` → 204 / 410 Gone | 204、release 後は 410 `LOCK_NOT_FOUND` | ✅ |
| `POST /lease/{id}/release` → 204、冪等 | 204、2 回目も 204 | ✅ |
| 400 `MISSING_TARGET` | 400 `{"errorCode":"MISSING_TARGET",...}` | ✅ |
| 404 `UNKNOWN_RESOURCE` / `UNKNOWN_LABEL` | 両方とも 404 で errorCode 一致 | ✅ |
| `quantity: 0`（または省略）＝全件 | label 全 44 件を確保、`RES0`〜`RES43` | ✅ |
| `skipIfLocked: true` → `SKIPPED` | 202 `{"state":"SKIPPED"}` | ✅ |
| timeout 超過は `FAILED` + `LOCK_WAIT_TIMEOUT` | コード確認一致（`RemoteQueueEntry#onTimeout`） | ✅ |
| `inversePrecedence` は受理するがキュー順序に未適用 | `RemoteLockRequest` に保持のみ。順序は `priority` だけ | ✅ |
| API token 必須（パスワードは CSRF で 403） | パスワード＝403 "No valid crumb"、token＝202 | ✅ |
| 状態表に `EXPIRED`（"Allocation timeout elapsed"） | **サーバは `EXPIRED` を返さない**（`RemoteLockState` は QUEUED/ACQUIRED/SKIPPED/FAILED/STALE）。allocation timeout は `FAILED` + `LOCK_WAIT_TIMEOUT` | ❌ 要修正 |
| 状態表に `STALE` が無い | `GET` は `STALE` を返しうる（heartbeat 途絶時） | ❌ 要追記 |
| 「`heartbeatIntervalSeconds` ごとに heartbeat を送ること」 | サーバは受理するが**値を無視**し、固定 `STALE_THRESHOLD_MS = max(既定10s×6, 60s) = 60s` を使う | ⚠️ 要注記 |
| lockId の例 `lr-abc123` | 実際は UUID（`70ee8eee-353f-...`） | ⚠️ 体裁 |

> `EXPIRED`/`CANCELLED`/`UNKNOWN` は**クライアント側の** `RemoteAcquireState` enum には存在するが、
> サーバの `GET /acquire/{lockId}` が返すのは `RemoteLockRecord#getState()`（＝`RemoteLockState`）である。
> doc の状態表はこの 2 つを混同している。

### 9.2 `src/doc/examples/remote-lock-pipeline-pattern.md`（130 行）

「ローカル gate ＋ remote lock の二重ロック」パターン。取得は local → remote、解放は逆順、
gate 名を `serverId::resource` で名前空間化する、という運用指針。末尾の
"Single source of truth"（ローカル gate 順は公平性のためだけで、実際の資源割当は必ずリモートが決める）は
label + quantity 利用時の誤解を的確に潰しており、**設計意図の説明として質が高い**。

`readme.md` の索引にも 2 本とも追加済み。

---

## 10. 解析⑦ 追加テスト

| テスト | 件数 | 内容 | `e83534b` での結果 |
|---|---|---|---|
| `RemoteApiClientTest#testHttp404Preserves...` | 1 | 404 で `httpStatus`/`remoteCode`/message/ヒントが保持されること | **FAIL**（`expected: <404> but was: <-1>`）＝回帰ガードとして有効 |
| `ConfigurationAsCodeTest`（remote 3 件） | 3 | JCasC で server 側／client 側／resources を設定できること | PASS（`@Symbol` 不要） |
| `LockStepExecutionEnvVarsTest` | 3 | `buildLockEnvVars` のインデックス／プロパティ、`withRemoteMetadata` | 新規メソッド前提のため対象外 |
| `LockStepRemoteTest#lockWithLabelPropagates...` | 1 | label+quantity で複数資源のプロパティ env と remote メタデータ env | 新規機能 |

新規 CasC フィクスチャ `configuration-as-code-remote.yml` は server 側（`remoteApiEnabled`, `exposeLabel`）と
client 側（`clientId`, `forcedServerId`, `remotes[]`）を両方カバーしており、**当方が用意していなかった
JCasC の契約テスト**を埋めてくれている。

`LockStepExecutionEnvVarsTest` は `withRemoteMetadata`（private）と `RemoteLockSession.serverId`（private）に
リフレクションで触っている。実装リファクタで壊れやすいので、可能ならメソッドを package-private に
引き上げてリフレクションを外したい（軽微）。

---

## 11. 実機検証ログ（before / after）

環境: `dev/jenkins-env`（jenkins-a/b/c/d、8081-8084）。既存 E2E 由来の資源・remote 設定をそのまま利用。

> **環境の罠（再確認）**: `start.sh` は `/usr/share/jenkins/ref/plugins/` にしか hpi を置かないため、
> 既に `jhX/plugins/lockable-resources.hpi` がある状態では**新しいビルドが反映されない**。
> 今回も一度これを踏んだ。`--clean` を使わず設定を残したまま入れ替えるには、
> `docker compose stop` → 各 `jhX/plugins/` の `lockable-resources.hpi` 差し替え＋展開ディレクトリ削除 →
> `docker compose start` が必要。

### 11.1 認証: API token vs パスワード

```
# パスワード（admin:admin）
POST /lockable-resources/remote/v1/acquire/  → HTTP 403
  <title>Error 403 No valid crumb was included in the request</title>

# API token（admin:110a009e...）
POST /lockable-resources/remote/v1/acquire/  → HTTP 202  {"lockId":"...","state":"ACQUIRED"}
```
→ 氏の help / doc の指摘どおり。**当方 doc・help の穴を突いた良い指摘**。

### 11.2 help URL 両形式（`e83534b` ビルドに対して）

```
200  /descriptor/org.jenkins.plugins.lockableresources.RemoteConnection/help/{serverId,url,credentialsId}
200  /descriptorByName/org.jenkins.plugins.lockableresources.RemoteConnection/help/{serverId,url,credentialsId}
```
→ 6/6 とも 200。`/descriptorByName/` への変更は 404 修正ではない。

### 11.3 Held By 列 / Queue タブ

[§5](#5-解析-ui--held-by-列と-queue-タブ) に掲載（before は空リンク・キュー 0 件、after は clientId 表示・キュー 1 件）。

### 11.4 CI ゲート（`mvn clean verify` @ `8fd2193`）

```
[INFO] Tests run: 394, Failures: 0, Errors: 0, Skipped: 1
[INFO] --- spotbugs:4.9.8.3:check (spotbugs) @ lockable-resources ---        ← PASS
[INFO] --- access-modifier-checker:1.35:enforce (default-enforce) ---        ← PASS
[INFO] --- spotless:3.5.1:check (default) @ lockable-resources ---
[ERROR] The following files had format violations:
[ERROR]     src/main/java/org/jenkins/plugins/lockableresources/LockableResource.java
[ERROR]         @@ -1,876 +1,876 @@
[ERROR]         -/*\r\n
[ERROR]         - * The MIT License\r\n
[ERROR]     ... (1704 more lines that didn't fit)
[ERROR] Run 'mvn spotless:apply' to fix these violations.
[INFO] BUILD FAILURE
[INFO] Total time:  19:52 min
```

**まとめ**: テスト **394 件・0 失敗・0 エラー・1 skip**（新規テスト 8 件を含む）、spotbugs（effort=Max, threshold=Low）と
access-modifier-checker は通過。**落ちるのは spotless:check の 1 点のみで、原因は CRLF**。
`e83534b` 時点の 386 件（`LRR_RESULT_P1_M1I.md`）から 8 件増えて全緑という内訳になる。

正本レポート: **`dev/reports/20260726084233-mvn-verify.md`**（`run-mvn-verify.sh` で生成、18:37）。

```
| spotless:check                            | FAIL |
| spotbugs:check (effort=Max, threshold=Low)| ok   |
| checkstyle:check                          | ok   |
| pmd:check                                 | ok   |
| tests | Tests run: 394, Failures: 0, Errors: 0, Skipped: 1 |
```

> 本サイクルで `run-mvn-verify.sh` に **`PLUGIN_DIR` 対応**を追加した（`start.sh` / `run-e2e.sh` と同じ流儀）。
> 従来はターゲットが `../../lockable-resources-plugin` にハードコードされており、氏のクローンを検証できず、
> 何も知らずに実行すると**当方リポジトリの `e83534b` を検証して SUCCESS になり誤誘導される**状態だった。
> 併せて、`--skip-tests` 未指定でも警告行に "(tests skipped)" と出る表示バグ
> （`${SKIP_TESTS:+…}` は `false` という文字列でも真になる）を修正。
>
> ```bash
> PLUGIN_DIR=../../jenkinsci/lockable-resources-plugin ./run-mvn-verify.sh
> ```

### 11.5 E2E 回帰（`run-e2e.sh --clean-start` @ `8fd2193`）

```
PLUGIN_DIR=../../../jenkinsci/lockable-resources-plugin ./run-e2e.sh --clean-start
Scenario summary: pass=21 fail=0 skip=0
```

**全 21 シナリオ PASS・fail 0**（`dev/reports/20260726094517-e2e-test.md`、09:45–10:00）。
S01–S18（`s-series`／`m1i-series`）と D01–D03（`d-series`）すべて回帰なし。

氏の変更で挙動が変わる可能性のあった箇所も緑を確認:

| シナリオ | 懸念 | 結果 |
|---|---|---|
| `remote-unknown-rejected`（S17） | 404 メッセージが情報化されたため CP02 の判定文字列が外れないか | PASS（`HTTP 404\|UNKNOWN_RESOURCE` の正規表現が新メッセージにも合致） |
| `fail-closed`（S07） | `auth-error` が「communication failure」から「returned HTTP 403」に変わる | PASS（判定正規表現に `returned HTTP 403` を含むため） |
| `remote-acquire-timeout`（S18） | M1I の回帰ガード。404 分岐が生き返った影響 | PASS（サーバ側 `terminalAt` 経路で `LOCK_WAIT_TIMEOUT` が出る点は不変） |
| `heartbeat-resilience`（S11） | heartbeat 例外メッセージの変化 | PASS |

### 11.6 Queue タブ「Change Position」を remote 行で押した場合

remote 待機 1 件のみがキューにある状態（local キューは 0 件）で `changeQueueOrder` を叩いた実測：

```
POST /lockable-resources/changeQueueOrder  id=<lockId>  index=1
→ HTTP 423
   Error 423 The queue position 1 is out of range (1 - 0)!
```

画面には 1 行表示されているのに「範囲は 1〜0」と言われる。ボタンが remote 行にも出る以上、
利用者は必ずこのエラーに遭遇する（[§12-3/4](#12-指摘事項)）。

### 11.7 負荷テスト（`run-load.sh --preset stress` @ `8fd2193`）

G01 grid-storm（4 コントローラが相互に server/client、各 50 ジョブ＝**200 並列**、3 iteration、hold 60s、
remote allocate timeout 3 分）を **2 本**実行した。

| run | plugin | SUCCESS | FAILURE | 失敗の内訳 | overlap 違反 | HUNG / UNKNOWN | queue wait p95 |
|---|---|---|---|---|---|---|---|
| ベースライン `20260719115008` | `e83534b` | 182 | 18 | 全件クリーン `LOCK_WAIT_TIMEOUT` | **0** | **0** | — |
| 1 本目 `20260726100200` | `8fd2193` | 186 | 14 | 全件クリーン `LOCK_WAIT_TIMEOUT` | **0** | **0** | 171.5 s |
| 2 本目 `20260726101522` | `8fd2193` | 181 | 19 | 全件クリーン `LOCK_WAIT_TIMEOUT` | **0** | **0** | 148.9 s |

**回帰なし**。SUCCESS/FAILURE 比の揺れ（186/14 ↔ 181/19 ↔ ベースライン 182/18）は、
p95 待ち時間（149–171 s）が allocate timeout（180 s）の直下にあるためのばらつきで、
**失敗はすべて fail-closed のクリーンな allocate timeout**（ロック不整合ではない）。

**最重要の不変条件は 3 本とも PASS**:

- **mutual-exclusion overlap 違反 0** — 容量を超えて資源が同時保持された瞬間がない
- **HUNG / UNKNOWN 0** — デッドロックや wakeup 喪失がない

成果物は最新の `dev/reports/20260726101522-load-test.md` のみ保持（1 本目は「最新ひとつずつ」ポリシーで削除。
数値は上表に転記済み）。

> **`run-load.sh` の修正**: 1 本目のレポートは `plugin under test` を **`4dbbfc1`（当方 repo の master）**
> と誤記していた。`run-load.sh:326` が `run-mvn-verify.sh` と同じくプラグインリポジトリのパスを
> ハードコードしており、実際にデプロイした jenkinsci クローンではなく既定パスの HEAD を読んでいたため。
> `PLUGIN_DIR` を尊重するよう修正し、2 本目は正しく `8fd2193` と記録されている。

---

## 12. 指摘事項

| # | 重要度 | 指摘 | 対応 |
|---|---|---|---|
| 1 | ⛔ **ブロッカー（進行中）** | `22c7b2b "spotles"` が `LockableResource.java` を CRLF 化。**すでに `3a555fe` 経由で PR #1055 に入っており、#1055 の CI が赤**（[§2.2](#22-pr-の関係とcrlf-がすでに-pr-1055-に入っている件)）。差分も 13 行 → 1739 行に膨張。**当方由来ではない**（上流 master も当方 PR 全コミットも一貫して LF。親 `7fd218b` では `spotless:check` が SUCCESS、実質変更はバイト単位でゼロ）→ [§2.1](#21-crlf-は誰が入れたか--履歴で確定) | **氏に `feature/1025-remote-lr-p1-m1` 側での LF 復元を依頼済み**（2026-07-26、PR #1 approve と併せて）。当方が先に直すと PR #1 のマージが全面衝突するため不可。`spotless:apply` は Windows だと同じ結果になり得るので行末を直接 LF に戻す。再発防止は `.gitattributes` の `*.java text eol=lf`（#1055 着地後に別 PR が穏当） |
| 2 | ⚠️ 中 | help URL の表記がプラグイン内で二分（`RemoteConnection` = `/descriptorByName/` 3 箇所、`LockableResourcesManager` = `/descriptor/` 5 箇所）。core の既定生成は `/descriptor/` 側 | どちらかに統一。core 準拠なら `/descriptor/` に戻す |
| 3 | ⚠️ 中 | Queue タブに remote 行が出るようになったが、**「Change Position」ボタンも remote 行に描画される**（JS は `hasQueuePermission` のみで判定し `type` を見ない）。`changeQueueOrder` は `queuedContexts`（local のみ）しか扱わないため**押すと必ずエラー**になる。**実測: `HTTP 423 The queue position 1 is out of range (1 - 0)!`** | remote 行ではボタンを出さない（JS で `item.type === "remote"` を除外）か、`changeQueueOrder` を remote 対応させる |
| 4 | ⚠️ 中 | 同ボタンの位置指定は `newPosition < queuedContexts.size()` で検証される一方、画面の行数は local + remote の合計。**local 行に対しても「範囲外」誤判定が起きうる**（上の実測はまさにこの経路。表示は 1 行だが local キューは 0 件） | 上記 #3 と併せて設計要検討 |
| 5 | ⚠️ 低 | 表示順が「local 全件 → remote 全件」の単純連結で、実際の昇格順（`proceedNextContext` は両者を priority 比較し、同値なら local 優先）を反映しない。index 列が誤解を招く | マージ後に priority 降順でソートしてから index を振る |
| 6 | ⚠️ 低 | Queue のフリーテキスト `filter` は remote 行に対し `lockId` しか当たらない（`resourcesMatch()`/`labelsMatch()` が false、`getBuild()` が null のため）。`request` 列フィルタは動作する | `filter` 分岐に `item.getRemoteRequest()` / `getRequestedBy()` を追加 |
| 7 | ⚠️ 低 | `withRemoteMetadata` が `lockEnvVars` 非空の場合のみ呼ばれる。空応答時に `X_SERVER_ID`/`X_LOCK_ID` が落ちる | 条件の外に出すか、doc に前提を明記 |
| 8 | ⚠️ 低 | doc `remote-api-curl.md` の状態表に **`EXPIRED` が誤記載**、**`STALE` が欠落**。`heartbeatIntervalSeconds` はサーバが無視して固定 60s 閾値を使う点も未記載 | doc 修正（[§9.1](#91-srcdocexamplesremote-api-curlmd293-行) の表を根拠に） |
| 9 | ℹ️ 情報 | credentials セレクタは URI ドメイン要件で絞り込む一方、`RemoteCredentials.basicAuthHeader()` のフォールバックは `Domain.global()` しか走査しない。非 global ドメインの資格情報は**選べるが（Run コンテキスト外では）解決できない**可能性 | 実運用で踏む確率は低い。将来の整理項目 |
| 10 | ℹ️ 情報 | `LockStepExecutionEnvVarsTest` が private メソッド／フィールドにリフレクション依存 | 可視性を package-private に上げてリフレクション除去 |
| 11 | ℹ️ 情報 | コミットメッセージ `more things` / `other findings` / `spotles` が非記述的 | 本家取り込み前に squash / 整形 |
| 12 | ℹ️ 情報 | 新規メッセージキー `resource.heldBy.remoteUnknown` は `table.properties`（英語）のみ。`table_{cs,de,fr,sk}.properties` は未追加 | Crowdin 同期に委ねてよい（未定義キーは base にフォールバック） |

### 12.1 設計思想（透過等価）との整合性チェック

M1A–M1G で確立した設計原則に照らして、**逸脱の芽**を洗い出した結果。

#### 逸脱している（1 件・要判断）

**`X_SERVER_ID` / `X_LOCK_ID` は M1D §3-2 の明示決定に反する。**

`LRR_DESIGN_P1_M1D.md` §3-2「env var：local と共有関数化」は
「`proceed()` 内のインライン env var 生成を共有関数に抽出し、**local と remote が同じ関数を呼ぶ**」と定めた。
コード側にも `RemoteResolver.remoteLockEnvVars` の javadoc に
"identical to local, including resource-property env vars" と明記されている。

氏の実装は `buildLockEnvVars`（共有関数）自体は**触っていない**。注入地点
（`LockStepExecution.runBody`、remote 経路のみ）で戻り値に 2 キーを足す形なので、
**共有関数の契約は保たれている**。しかし **lock ボディ内で観測される env は local と remote で
もはや同一ではない**。非対称の向きは:

| | local `lock()` | remote `lock(serverId:)` |
|---|---|---|
| `X`, `X0`, `X0_<prop>` | あり | あり（同一） |
| `X_SERVER_ID`, `X_LOCK_ID` | **なし** | あり |

→ remote 向けに書いたパイプラインを local に移すと `X_SERVER_ID` が null になって壊れる。
「同じパイプラインコードが両方で動く」という透過等価の狙いに対する後退。

**ただし擁護できる**: この 2 値は**ネットワークブリッジ由来の情報しか含まない**（どのサーバか・どの lockId か）。
M1F で確定した観点「**ブリッジ由来でない** remote 独自判定を増やさない」の文言には触れていない。
「ブリッジ固有メタデータの露出は透過等価の対象外」と設計書に明文化して受け入れるか、
不要と判断して落とすかの**設計判断が必要**（放置すると M1E-1 のような「意図的残置」の記録漏れになる）。

#### 逸脱していない（安心材料）

| 原則 | 判定 |
|---|---|
| canonical パス（`getAvailableResources` / `proceedNextContext` / `buildLockEnvVars`）を汚さない | ✅ 一切変更なし |
| 公開フィルタは exposeLabel 単一（M1E で ExtensionPoint 撤去） | ✅ 変更なし |
| admission = 未知/未公開は 404（M1E の意図的非等価） | ✅ 変更なし |
| `GET /acquire/{lockId}` は純 read（M1H B2 決定） | ✅ 新設の `getCurrentRemoteQueueEntries` も read-only スナップショット |
| QUEUED 期限は `timeoutForAllocateResource` 一本化（M1H） | ✅ 変更なし |
| Phase 1 スコープ = ロック＋**サーバ ops UI** | ✅ Held By / Queue はいずれもサーバ側 ops UI＝スコープ内 |
| 権限境界 | ✅ `clientId` は既存の `resource.status.remoteLockedBy` で VIEW に露出済み。新規露出なし |

#### 将来のドリフト源（docs、コードではない）

1. **`EXPIRED` の誤記**（[§12-8](#12-指摘事項)）が最も危険。**サーバが返さない状態を契約として文書化**しているため、
   後任が「doc どおりに実装」すると `RemoteLockState` に `EXPIRED` を足す方向へ引っ張られる。
   実体は `FAILED` + `errorCode=LOCK_WAIT_TIMEOUT`（M1I で確定した表現）。
2. **`heartbeatIntervalSeconds`**: doc は「この間隔で送れ」と読めるが、phase 1 は
   「受理するが無視し、サーバ固定 `STALE_THRESHOLD_MS`(=60s) を使う」と `RemoteApiV1Action` に
   コメント付きで明示決定済み。doc が決定と食い違う。
3. **`remote-lock-pipeline-pattern.md` の local gate 推奨トーン**: "Always acquire in this order" と
   命令形で書かれており、**`lock(serverId:)` 単体では不十分**と読める。透過等価の設計思想は
   「単体で十分・安全」であり、gate は任意の運用パターンにすぎない。
   加えて **gate は remote 待機の全期間ロックされ続ける**（当方の既定は
   `timeoutForAllocateResource` 無制限）という副作用が書かれていない。
   `node {}` の内側で使えば executor も同時に占有する。"optional pattern" と明示したい。

### 12.2 本 PR が表面化させた当方側の設計課題（別サイクル送り）

氏の `RemoteApiClient` 修正で `RemoteLockSession.pollOnce()` の 404/410 分岐が**初めて実際に動くようになった**
結果、当方（M1I）のコードに残っていた設計上のねじれが見えた。**氏の PR の問題ではない**ため本 PR では対処せず、
記録のみ行う（2026-07-26 ユーザー確定）。

#### ポーリングのライフサイクル

```java
case ACQUIRED:
    bodyStarted = true;
    cancelPollTask();      // ← 取得と同時にポーリング終了
    startHeartbeat(...);   // ← 以降は heartbeat のみ（失敗は警告ログのみ・ジョブ継続）
    host.runBody(...);
```

`onResume` も `bodyStarted == true` ならポーリングを再開せず、best-effort release して失敗させる。

#### 2 分岐の到達性とラベルのねじれ

| 分岐 | 到達性 | 現在のメッセージ |
|---|---|---|
| `!bodyStarted`（QUEUED 中に record 消失） | **到達可能** | `LOCK_WAIT_TIMEOUT` に正規化 |
| `bodyStarted`（リース消失） | **設計上ほぼ到達不能**（取得と同時に poll 停止。in-flight な 1 反復のみの競合窓） | `server may have restarted` |

さらに M1I のサーバ側修正（`terminalAt` 起点 TTL）により、**正当な allocate timeout は 404 ではなく
`200 + FAILED + errorCode=LOCK_WAIT_TIMEOUT` で返る**。したがって `!bodyStarted` 側に残る主なトリガは
**「QUEUED 中の相手サーバ再起動」**であり、それを `LOCK_WAIT_TIMEOUT` と報告するのは意味的に不正確。

→ **2 つのラベルが実態に対して入れ替わっている**（到達可能な側に timeout ラベル、到達不能な側に restart ラベル）。
修正案は「`!bodyStarted` 側のメッセージを『record が存在しない（サーバ再起動の可能性）』寄りに改め、
真の allocate timeout はサーバ側 FAILED 経路に一本化されている前提を明示する」だが、**別サイクルで検討**する。

#### E2E カバレッジの判断

この経路を踏む E2E シナリオ（「QUEUED 中に相手サーバを再起動」）の追加を検討したが、
**今回は追加しない**（2026-07-26 ユーザー確定）。理由:

- 氏の PR をマージする判断材料としては、既存 21 件の回帰確認（[§11.5](#115-e2e-回帰run-e2esh---clean-start--8fd2193)）で十分。
  UI 変更は表示のみ、env var は氏がユニットテスト済み
- 現在のラベルが上記のとおり要検討であり、**テストで既成事実化したくない**
- ラベルの方針が決まった時点で、シナリオもその仕様に合わせて書くほうが手戻りがない

> なお `bodyStarted` 側の分岐は、たとえ E2E を書いても踏めない（取得後はポーリングが止まっているため、
> 保持中にサーバを落としても heartbeat 経路に落ちる＝既存 S11 の領域）。この点は当初の想定を訂正する。

---

## 13. 取り込み方針と現況

### 13.1 実施済み（2026-07-26）

1. **PR #1 を approve**（[review 4780503811](https://github.com/kohtaro-satoh/lockable-resources-plugin/pull/1#pullrequestreview-4780503811)）。
   検証一式（verify 394/0/1skip・E2E 21/21・load stress）を通した上での承認。
2. **`RemoteApiClient` 修正へのインラインコメント**（[review 4780427470](https://github.com/kohtaro-satoh/lockable-resources-plugin/pull/1#pullrequestreview-4780427470)）。
   `RemoteApiException extends IOException` により自分の `catch (IOException)` に飲まれていた旨と、
   `pollOnce()` の 404/410 分岐が到達可能になったことを確認した旨を記載。
3. **CRLF の LF 復元を氏に依頼**（PR #1 レビュー＋ PR #1055 コメント）。
   **当方が先に直すと PR #1 のマージが全面衝突するため、氏に対応してもらうのが唯一の安全な順序**
   （[§2.2](#22-pr-の関係とcrlf-がすでに-pr-1055-に入っている件)）。

### 13.2 氏のマージ待ち

氏は「レビューしてくれたら一緒にマージして go live しよう」と表明しているため、
**PR #1 マージ → LF 復元 → PR #1055 を master へ** の流れを待つ。

### 13.3 取り込み後に別途対応したい項目

1. **UI 2 点（Held By / Queue）の詰め。** とくに [§12-3](#12-指摘事項)（remote 行の Change Position ボタンが
   必ず 423 になる）は利用者が確実に踏むので、優先度が高い。
2. **doc の状態表修正**（[§12-8](#12-指摘事項)）。`EXPIRED` の誤記・`STALE` の欠落は
   外部スクリプト実装者を確実に迷わせる。
3. **help URL の表記統一**（[§6.2](#62-help-リンク-descriptor--descriptorbyname)）。
   `/descriptor/`（core 準拠）に戻すか `/descriptorByName/` に寄せる（8 箇所）かのどちらか。
4. **`X_SERVER_ID` / `X_LOCK_ID` の位置づけを設計書に明文化**（[§12.1](#121-設計思想透過等価との整合性チェック)）。
   受け入れるなら「ブリッジ固有メタデータは透過等価の対象外」と記録する。
5. **`RemoteLockSession` の 404/410 ラベルのねじれ**（[§12.2](#122-本-pr-が表面化させた当方側の設計課題別サイクル送り)）。
   別サイクルで検討。
6. **`.gitattributes`（`*.java text eol=lf`）の追加。** 環境依存の再発を根本的に止める。
   #1055 のスコープ外なので、**master 着地後に別 PR** が穏当。

---

## 14. 付録: 再現コマンド

```bash
# 実質差分（CRLF を除外）
git -C jenkinsci/lockable-resources-plugin diff --stat -w e83534b..8fd2193

# CRLF 混入元の特定
for r in 7fd218b 22c7b2b e83534b HEAD; do
  echo -n "$r CR="; git show "$r:src/main/java/org/jenkins/plugins/lockableresources/LockableResource.java" | tr -cd '\r' | wc -c
done

# CI ゲート
mvn -B -ntp clean verify
mvn -B -ntp spotless:check

# 「旧コードで落ちるか」の確認（実バグ修正の証明）
git worktree add --detach /tmp/wt-e83534b e83534b
cp .../RemoteApiClientTest.java /tmp/wt-e83534b/src/test/java/.../RemoteApiClientTest.java
cd /tmp/wt-e83534b && mvn -o -Dtest=RemoteApiClientTest -Dspotless.check.skip=true -Dspotbugs.skip=true test

# 実機（jenkins-env）へ新ビルドを反映（設定を残す場合）
cd dev/jenkins-env
PLUGIN_DIR=../../../jenkinsci/lockable-resources-plugin ./start.sh
docker compose stop
for jh in jha jhb jhc jhd; do rm -rf $jh/plugins/lockable-resources; cp docker/lockable-resources.hpi $jh/plugins/; done
docker compose start

# API token の発行（admin:admin ではパスワード認証が CSRF で弾かれるため必須）
CR=$(curl -s -u admin:admin -c cj "$J/crumbIssuer/api/json" \
     | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['crumbRequestField']+': '+d['crumb'])")
curl -s -u admin:admin -b cj -H "$CR" --data-urlencode 'script=
  import jenkins.security.ApiTokenProperty
  def u = jenkins.model.Jenkins.get().getUser("admin")
  println("TOKEN=" + u.getProperty(ApiTokenProperty).tokenStore.generateNewToken("x").plainValue)
  u.save()' "$J/scriptText"

# Queue タブ JSON（POST 必須: PR #1048 以降）
curl -s -u admin:$TOKEN -b cj -H "$CR" -X POST "$J/lockable-resources/getQueuePage?page=1&size=25"
```

---

## 関連ドキュメント

- `LRR_RESULT_P1_M1I.md` — 本件 §4.3 で言及した「安全網」の出自
- `LRR_ISSUE_P1_M1H_queued_expiry_poll_404.md` — 404 誤表面化の原調査
- `LRR_REVIEW_P1_M1H.md` — 前回のメンテナ指摘対応レビュー
- `E2E_TEST_SPECIFICATION.md` — `fail-closed` シナリオの判定条件（§4.5 の互換性判断の根拠）
