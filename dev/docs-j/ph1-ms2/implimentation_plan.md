# 実装計画（Phase 1 / M2 + M3）

> **設計書:** [`design_01.md`](./design_01.md)（本計画の各項目は設計書の節を参照する）
> **作業ブランチ:** `feature/issues-1025-remote-lr`
> **基点:** `upstream/master` = `origin/master` = **`27422e3`**（2026-08-08 時点）
> **作成日:** 2026-08-08

---

## 方針

- **1 機能 1 コミット。** 混ぜない。レビュアが 1 コミット単位で意味を追えることを優先する
- **実装順: バグ fix 系 → 機能追加系 → ドキュメントメンテ。** 機能追加のうち **LR 画面系は最後**に回す
- **ユニットテストは該当コミットに同梱**する（Jenkins プラグインの慣例。テストだけ後追いにしない）
- **help / Messages / JCasC も該当機能のコミットに同梱**する（設定を足したコミットが help なしで着地しない）
- **E2E シナリオは notes リポジトリ側の作業**なので plugin のコミットには含めない（[§並行作業](#並行作業notes-リポジトリ側)）
- コミットメッセージは英語・命令形・prefix なし。**`Co-Authored-By` は付けない**

---

## Phase A: バグ fix（5 コミット）

先に入れる。以降の機能追加が同じファイルに触るため、バグ fix が後ろに回ると差分が混ざる。

### A1. `lockCause` がリモート保持を考慮していない

- [ ] `Report the remote holder in the lock cause`
- **対象:** `LockableResource#getLockCause()` / `#getLockCauseDetail()`（`LockableResource.java:652`〜）
- **内容:** remote 保持中の資源が `locked by null at <unknown>` と表示される。`remoteLockedBy != null` で分岐させ、
  `clientId` と `RemoteLockRecord#getAcquiredAt()` を使う。Held By 列（氏の実装）と同じ情報源を参照する
- **露出範囲:** REST API の `lockCause` と、**ローカル待機ジョブのコンソール**の両方。後者は「なぜ待たされているか」を
  調べる利用者が最初に見る場所
- **テスト:** remote 保持中の資源の `lockCause` に clientId と取得時刻が入ること／local 保持時は従来どおり
- **設計書:** §6.1

### A2. QUEUED の release 直後に `GET /acquire/{lockId}` が 404 になる

- [ ] `Keep a released queued request until its terminal TTL`
- **対象:** `RemoteLockManager#release()`
- **内容:** QUEUED に対する release が `markFailed("RELEASED")` の直後に `records.remove()` するため、
  直後の GET が 404 を返す。**terminal TTL（120s）保持に変更**し、`records.remove()` は掃引に一本化する。
  **新状態 `CANCELLED` は追加しない**（M1 の「クライアントからは CANCELLED を発行しない」方針を維持）
- **テスト:** release 直後の GET が **200 `FAILED` / `RELEASED`**／TTL 経過後は 404 に戻る／
  ACQUIRED の release は従来どおり（回帰）
- **設計書:** §3.3

### A3. 404/410 のラベルが実態とねじれている

- [ ] `Report a vanished remote record as a missing record, not a timeout`
- **対象:** `RemoteLockSession#pollOnce()` の 404/410 分岐（現 249-290 行）
- **内容:** 到達可能な `!bodyStarted` 側を「record が存在しない（サーバ再起動の可能性）」寄りの表現に**一本化**する。
  正当な allocate timeout はサーバ側 FAILED 経路に一本化済みである前提をコメントで明示。A2 と併せて
  **404 が出る条件そのものが減る**
- **前提確認済み:** 当該分岐は `73a2d3b`＋`7fd218b` で全行が当方のコード（氏の `9ffade8` は acquire 時ログのみ）
- **テスト:** 既存の 404/410 テストの文言更新（回帰）
- **設計書:** §6-1 / §10 Q1

### A4. `variable` 指定が空 `lockEnvVars` で注入されない

- [ ] `Inject the remote lock variable even when no env vars are returned`
- **対象:** `LockStepExecution#withRemoteMetadata()`（`LockStepExecution.java:340`、呼び出しは `:168`）
- **内容:** 空 `lockEnvVars` の条件の内側に入っているため注入が落ちる。条件の外に出し、
  **`variable` 指定があれば常に注入**されるようにする
- **テスト:** `lockEnvVars` が空でも `X_SERVER_ID` / `X_LOCK_ID` と variable が入ること
- **設計書:** §6-7

### A5. Queue タブが remote 行を正しく扱っていない（3 件まとめて 1 コミット）

- [ ] `Fix the queue tab handling of remote entries`
- **対象:** `LockableResourcesRootAction`（`QueueStruct` / `getQueuePage` / `doChangeQueueOrder`）、
  `tableQueue/table.jelly`、`tableQueue/queue-too-long.js`
- **内容:**
  1. **Change Position ボタン** — remote 行では描画しない（`doChangeQueueOrder` は local キューのみ扱うため、
     押すと必ず `423`。実測済み）
  2. **表示順** — local 全件 → remote 全件の単純連結をやめ、**priority 降順でマージしてから index を振る**
     （実際の昇格順＝`proceedNextContext` と一致させる）
  3. **フリーテキスト filter** — `getRemoteRequest()` / `getRequestedBy()` を filter 分岐に追加し、remote 行にも効かせる
- **1 コミットにする理由:** 3 件とも「Queue タブが remote 行を local 行と同じには扱えていない」という同一機能面の欠陥で、
  同じファイル群に触る。分割するとレビュー時に 3 つの差分を行き来することになる
- **テスト:** マージ順序のユニット（local+remote を priority 降順に並べ index が昇格順と一致）
- **設計書:** §6-3 / §6-5 / §6-6

---

## Phase B: 機能追加（LR 画面以外、4 コミット）

### B1. `inversePrecedence` の透過等価

- [ ] `Apply inversePrecedence to remotely queued requests`
- **対象:** `LockableResourcesManager#queueRemote()`
- **内容:** local の `queueContext` は `inversePrecedence && priority == 0` のとき **index 0 に挿入**するが、
  `queueRemote` は priority しか見ておらず `inversePrecedence` を参照しない（ワイヤでは運ばれて
  `RemoteLockRequest` に保持されている）。**local と同じ挿入規則を反映**する。
  値は `entry.getLockRequest().isInversePrecedence()` で取得できる
- **注意:** これは「remote 独自ルールの追加」ではなく、**local 規則の未反映を直す**もの
- **テスト:** remote 要求が `inversePrecedence=true` でキュー先頭に入る（local と同じ挿入位置）
- **設計書:** §10.1 対応 1 / §6-8

### B2. 検証層の再設計（Wire → Admission → Canonical）

- [ ] `Delegate remote request validation to the canonical validator`
- **対象:** `RemoteApiV1Action`（境界）、`RemoteLockManager#enqueue()`、必要なら `RemoteResolver`
- **内容:**
  - 境界の自前チェック **`MISSING_TARGET` と `INVALID_SELECT_STRATEGY` を削除**（canonical の部分コピーであり、
    前者は `allowEmptyOrNullValues` を無視するため **local が受理する要求を remote が 400 で弾く**破れになっている）
  - `enqueue` を **admission → canonical** の順にし、`LockStepResource.validate(...)` を呼ぶ。
    `IllegalArgumentException` は**そのまま伝播**させ、`RemoteApiV1Action` が catch して
    **400 `INVALID_REQUEST` ＋ `ex.getMessage()`**（record は作らない＝現状の 400 群と同じ門前払い）
  - `extra` も canonical に乗せる（`ExtraResource` → `LockStepResource` を組んで list オーバーロード）
- **これで変わる挙動 3 件:** `allowEmptyOrNullValues=true` の無指定が**受理**される／
  `priority != 0 && inversePrecedence` が **400**（§10.1 対応 2）／`resource` と `label` の同時指定が **400**（M1E-2 を閉じる）
- **順序が重要:** admission を先に置くことで **未知/未公開とも一律 404** が維持される（canonical を先に走らせると
  未知 label が 400・未公開が 404 となり存在が漏れる）
- **テスト:** 上記 3 挙動＋未知/未公開が 404 のまま（回帰）＋ `INVALID_REQUEST` のメッセージ
- **設計書:** §3.5 / §10.1

### B3. メンテナンススイッチ "accept new acquires: ON/OFF"

- [ ] `Add a maintenance switch for the remote acquire endpoint`
- **対象:** `LockableResourcesManager`（`acceptNewAcquires`、既定 `true`）、`RemoteApiV1Action`、
  `LockableResourcesManager/config.jelly` ＋ `help-acceptNewAcquires.html` ＋ `Messages.properties` ＋ JCasC、
  クライアント側は `RemoteLockSession`
- **内容:**
  - OFF のとき **`POST /acquire` だけが 503 `ACQUIRES_PAUSED`**。`GET /acquire/{lockId}` / heartbeat / release は素通し
  - **クライアントは 503 でリトライ**する（`timeoutForAllocateResource` の範囲内、ポーリング間隔。INFO は 1 回だけ）。
    現状の「acquire 失敗＝即 abort」のままでは要望の目的（B のメンテ中に A が困らない）を満たさない
  - **既にキューにある要求は昇格を続ける**（受理済みは履行し、キューが drain する）
- **未確定（氏に未質問。PR で提示して合意を取る）:** 上記リトライと drain の 2 点。相違があれば PR で差し替える
- **テスト:** OFF で 503／同じ状態で heartbeat・release・GET が成功／ON 復帰で再び受理／既存キューの昇格が止まらない／
  クライアントが 503 でリトライし timeout まで粘る
- **設計書:** §3.4

### B4. `GET /resources`

- [ ] `Add the remote resources discovery endpoint`
- **対象:** `RemoteApiV1Action#getDynamic`（`resources` 分岐を追加）
- **内容:** 公開中の資源一覧と、**サーバ側の受付状態**を 1 回のスナップショットで返す
  - 資源ごと: `name` / `labels` / `description` / **`state`（`FREE` / `LOCKED` / `RESERVED` / `QUEUED`）** /
    `heldByKind`（`LOCAL_BUILD` / `REMOTE_CLIENT` / `ADMIN`）/ `heldByClientId`（REMOTE_CLIENT 時のみ）/
    `since` / `queuedCount`
  - 封筒: **`acceptNewAcquires`**（B3 のスイッチ状態。別エンドポイントに割るとキャッシュ不整合で
    「FREE と表示しつつ受付停止中」の画面が作れてしまうため、同一スナップショットで返す）
  - **ビルド名 / ビルド URL / `reason` / `note` は返さない。** B のジョブ名を A の LR ページ閲覧者に
    出さないため（`RemoteUse` 権限は B 全体の READ とは別物）
  - **メンテ中でも資源状態は真実を返す**（FREE は FREE）。「取得できない」は画面側の表現で伝える
  - 公開フィルタは既存の `getExposeLabels()` を再利用。`remoteApiEnabled=false` では既存 4 本と同型で
    **403 `REMOTE_API_DISABLED`**。ページングは持たない
- **テスト:** exposeLabel フィルタが効く／未公開資源が漏れない／**4 状態が正しく出る**／
  **ビルド名・reason・note が漏れない**／`acceptNewAcquires` が反映される／無効時 403
- **設計書:** §3.1

---

## Phase C: 機能追加（LR 画面系、4 コミット）

**最後に回す。** #1035 で体裁が変わった直後であり、[§9.4](./design_01.md) の新旧並走比較で見た目を確認しながら詰める。

### C1. クライアント側レジストリ（表示のデータ源）

- [ ] `Track the remote locks this controller holds or waits for`
- **対象:** 新規 `RemoteClientRegistry`（`@Extension`、transient）、`RemoteLockSession` から登録・解除
- **内容:** remote ロックの client 側状態は step ごとの `RemoteLockSession` にしかない。コントローラ横断で集約する
  レジストリを新設する。key = `lockId`、value = `serverId` / 要求内容 / state(QUEUED|ACQUIRED) / 取得済み資源名 /
  `enqueuedAt` / `acquiredAt` / 発信ビルド。**永続化しない**（再起動時は `onResume` から再登録）。
  `Run` は弱参照＋`getFullDisplayName()` のスナップショットを併せ持つ
- **副産物:** M-1（`onResume` で displayTarget が劣化する）が解消する
- **テスト:** acquire/release での登録・解除／`onResume` 後の再構築／ビルド削除時に落ちない
- **設計書:** §4.2

### C2. Remote タブ（保持中／待機中の可視化）

- [ ] `Show the remote locks on the lockable resources page`
- **対象:** `LockableResourcesRootAction`、`_content.jelly`（タブ追加）、新規 `tableRemote/table.jelly` ＋ `.properties`
- **内容:** #1035 のタブ構成（Overview / Resources / Labels / Queue）に **Remote タブを 1 つ足す**。
  列は Server（`serverId`）/ Request / State / Resources / Requested by / Since。
  **「クライアント側のキャッシュビューであり、リモートの権威状態ではない」旨をタブ内に常時表示**（仕様の明示要件）。
  **操作（cancel / release）は出さない**（Phase 1 は可視化まで）。
  待機中エントリについては、**リモートが受付停止中であることが待機理由なら**それを示す（B3 のリトライと対）
- **暫定判断:** タブにするか Resources の列にするかは **§9.4 の新旧並走比較で最終決定**する。まず (a) タブで作る
- **設計書:** §4.3 / §10 Q2 / Q6

### C3. delegated mode の表示（バッジ＋並存＋`/resources` キャッシュ）

- [ ] `Show the delegated target resources next to the local ones`
- **対象:** `_content.jelly`（バッジ）、Remote タブ、`GET /resources` のクライアント側キャッシュ（新規または `RemoteApiClient`）
- **内容:**
  - `forcedServerId` 設定時にページ上部へ **delegated バッジ**を常時表示（ローカル資源が他コントローラからは
    引き続きロック可能である旨も添える）
  - **ローカル資源は隠さない。** リモートの公開資源を**並べて**表示する（[§5.0](./design_01.md) の方針変更）。
    ローカル側には「このコントローラの `lock()` 解決には使われない」と明示する
  - `GET /resources` の結果は **TTL 10s の短期キャッシュ**（状態を含むため 60s では誤情報になる）。取得失敗時は最後に取れた内容＋stale 表示に
    フォールバック（表示は best-effort。fail-closed はロック取得の話）。取得はページ表示スレッドではなく非同期
  - **メンテナンス中の表現** — `acceptNewAcquires=false` のとき「リソースは見えるが lock はできない」と示す
    （資源の状態表示は真実のまま変えない）。C4 のサーバ側バナーと対になるクライアント側の表現
- **設計書:** §5.0 / §5.1 / §5.2

### C4. サーバ側の一時停止バナー

- [ ] `Show a banner while new remote acquires are paused`
- **対象:** `_content.jelly`（または Overview カード）
- **内容:** `acceptNewAcquires=false` のとき LR ページに一時停止バナーを出す（管理者が戻し忘れないように）
- **B3 と分ける理由:** B3 は API とクライアント挙動、こちらは画面。LR 画面系を後ろに寄せる方針に従う。
  レビュー上まとめたほうが良ければ B3 に畳んでよい
- **設計書:** §3.4

---

## Phase D: ドキュメントメンテ（2 コミット）

### D1. README

- [ ] `Document the remote lockable resources feature in the README`
- **対象:** `README.md`
- **内容:** 現状 **remote 機能への言及がゼロ**（`grep -c -i remote README.md` → 0）。追記するのは 3 点:
  1. **Permissions 表に `RemoteUse` 行**（Implied by: Jenkins.ADMINISTER）。既存表の欠落＝不整合でもある
  2. **`lock(..., serverId:)`** と delegated mode（`forcedServerId`）の説明
  3. **Configuration as Code 例**に remote 系キー（`remoteApiEnabled` / `exposeLabel` / `clientId` /
     `forcedServerId` / `acceptNewAcquires` / `remotes[]`）。テストの `configuration-as-code-remote.yml` から抜粋できる
- **設計書:** §6.2 / §10 Q7

### D2. `remote-api-curl.md`

- [ ] `Correct the remote API reference for the shipped behaviour`
- **対象:** `src/doc/examples/remote-api-curl.md`（氏が追加したドキュメント）
- **内容:**
  - 状態表: **`EXPIRED` の誤記を削除**（サーバは返さない。`maxWaitSeconds` 導入時の将来枠と明記）、**`STALE` を追記**
  - `heartbeatIntervalSeconds` が **Phase 1 ではサーバ側で使われない**旨を注記
  - **エラーコード表を更新**（B2 で細分コードが `INVALID_REQUEST` に一本化される。`ACQUIRES_PAUSED` / 503 を追加）
  - `inversePrecedence` の記述を B1 の実装に合わせて更新（現状の「適用されない」記述が実態と合わなくなる）
  - `GET /resources` の節を追加
- **設計書:** §6-2 / §3.5 / §10.1

---

## 並行作業（notes リポジトリ側）

plugin のコミットには含めない。

- [ ] **E2E シナリオ 4 本追加**（`dev/jenkins-env/scenarios/` ＋ `run-e2e.sh` 登録）
  - [ ] S19 `remote-resources-endpoint` — `GET /resources` が exposeLabel 付きのみ返す／未公開が漏れない／
        **保持中資源が `LOCKED` ＋ `heldByKind` で返る／ビルド名・reason・note が漏れていない**
  - [ ] S20 `client-side-remote-view` — A が B の資源を保持中、A の LR ページに出る／解放後に消える
  - [ ] S21 `delegated-mode-page` — `forcedServerId=b` で delegated バッジと B の公開資源が出る／
        **ローカル資源も消えていない**／解除で元に戻る
  - [ ] S22 `remote-maintenance-switch` — B を OFF にすると A の新規 `lock()` が待つ（落ちない）／
        保持中リースは heartbeat・release とも無事／ON 復帰で取得に進む／
        **`GET /resources` の `acceptNewAcquires` が false になり、A の画面に反映される**
- [ ] **設計書の追従** — 実装中に判明した相違を `design_01.md` に反映（特に §3.4 の未確定 2 点、§10 Q6）
- [ ] **PR 本文の作成** — テンプレート準拠に加え、**「#1025 仕様との乖離と、そうした理由」セクション**を含める
      （転記元は設計書 §7.11 の 11 項目）。**issue 本文は更新しない**方針に変更済み（§10 Q8）
- [ ] **#1025 への導線コメント** — PR 提出**後**に「最新仕様は PR #X にある」と短く追記する

---

## 完了条件

- [ ] `dev/run-mvn-verify.sh` — BUILD SUCCESS、全ゲート ok（spotless / spotbugs / checkstyle / pmd）
- [ ] `dev/jenkins-env/run-e2e.sh --clean-start` — 全 25 シナリオ PASS（既存 21 ＋ 新規 4）
- [ ] `dev/jenkins-env/run-load.sh --preset stress` — overlap 0 / HUNG 0。
      **LR ページが正式な挙動で更新されている状態のまま**計測する（§9.3）。
      `/resources` を **10s 間隔で相互に引く負荷を含める**（§10 Q5 で「含める」に確定。TTL 短縮で頻度が 6 倍）
- [ ] **§9.4 の新旧並走比較** — a = 新版 / b = 旧版（現 master）で LR ページを見比べ、Q6 を最終決定。
      PR 用の修正前後スクリーンショットを取得
- [ ] ドキュメント整備 — `docs-e` の ph1-ms2 ミラー（PR 提出までに作成）
- [ ] **PR 本文に乖離セクション**（§7.11）を記載 — issue 本文を直さない代わりの唯一の記録場所になる
- [ ] 直前に `upstream/master` へ追従（マージまたはリベース）し、再検証

---

## 依存関係メモ

```
A1..A5  独立（ただし A2 → A3 の順に入れると 404 の文言調整が 1 回で済む）
B1      独立
B2      A2 の後（release まわりのテストと干渉しない順序）
B3      独立。ただし C4 が B3 に依存
B4      C2 / C3 の前提
C1      C2 の前提
C2      C3 の前提（タブの器を先に作る）
C4      B3 の後
D1/D2   すべての実装コミットの後（挙動が確定してから書く）
```

---

## 更新履歴

| 日付 | 内容 |
|---|---|
| 2026-08-08 (3) | issue #1025 本文の更新を取りやめ。並行作業と完了条件を「PR 本文に乖離セクションを書く／提出後に #1025 へ導線コメント」に差し替え |
| 2026-08-08 (2) | B4 の機能仕様を確定（`GET /resources` が状態と `acceptNewAcquires` を返す）。C2 / C3 / S19 / S22 と負荷の完了条件を追従 |
| 2026-08-08 | 初版。`design_01.md` の確定内容を 15 コミット（A5 + B4 + C4 + D2）に分解 |
