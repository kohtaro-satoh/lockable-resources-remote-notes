# Remote LR 開発活動 全体レビュー（Phase 1 / M1A 時点）

> **レビュー日:** 2026-06-11
> **対象 plugin ブランチ:** `feature/1025-remote-lockable-resources-p1-m1a`（HEAD: `c782c28`、M1A Step 5 まで、347 テスト成功）
> **対象ドキュメント:** `docs-j/`（background / usecase / design-notes）、`dev/docs-j/`（LRR_DESIGN / IMPLEMENTATION_STEPS / E2E_TEST_SPECIFICATION の P1_M1・P1_M1A）
> **観点:** コードだけでなく、仕様・ユースケース・プロセスを含む俯瞰評価

---

## M1B での解消状況（2026-06-12 追記）

本レビューの指摘を受けて M1B（`LRR_DESIGN_P1_M1B.md`）を実施した。各指摘の現況:

| 指摘 | M1B での状況 |
|---|---|
| 3-1 extra 欠落 | ✅ 解消（完全実装。E2E S10 で実証） |
| 3-2 lockEnvVars 非等価 | ✅ 解消（カンマ結合。プロパティ env var は「非対応」と宣言） |
| 3-3 再起動セマンティクス | ✅ 既知制約として文書化（transient は設計通り、運用前提を明記） |
| 3-4 onResume 欠落 | ✅ 解消 |
| 3-5 STALE 解放手段なし | ✅ 解消（Force Release UI。E2E S13 で実証） |
| 4-1 1 回の通信失敗で即死 | ✅ 解消（poll リトライ予算 + heartbeat 警告継続。E2E S11 で実証。BodyExecution 保持は B 案採用により不要化） |
| 4-2 キュー意味論の乖離 | ✅ 解消（LRM 統一キューブリッジ。E2E S12 で実証） |
| 4-3 local 待機者を起こさない | ✅ 解消（統一キューで自動解決） |
| 4-4 QUEUED の TTL なし | ✅ 解消（M1B 追補 F-2: GET poll を生存シグナルとし 60 秒途絶で QUEUE_EXPIRED 失効） |
| 4-5 release と tick の競合 | ✅ 構造的に消滅（tick 昇格を廃止、キュー操作は syncResources 下に統一） |
| 4-6 充足不可能要求が永遠に QUEUED | ✅ 透過等価により設計どおりとしてクローズ（local lock() も同一挙動。timeout 指定で FAILED、client 消滅は QUEUE_EXPIRED が回収。`LRR_DESIGN_P1_M1B.md` §5 に明記、2026-06-12 決定） |
| 5-1 権限モデル | ✅ 解消（M1B 追補 F-3: 専用 RemoteUse 権限で remote API をゲート、ADMINISTER に implied） |
| 5-2 匿名リクエスト | ✅ 意図的挙動として再決定（空 credentialsId = 認証不要サーバー向けの正規ユースケース。M1B 決定 1-c） |
| ドリフト #3 exposeLabel Javadoc | ✅ 解消 |
| ドリフト #4 forcedServerId バリデーション | ✅ 解消（M1B 追補 F-1: doCheckForcedServerId + 保存時警告） |
| ドリフト #10 README 空 | ✅ 解消（索引付き README 整備） |

---

## 目次

1. [総評](#1-総評)
2. [高く評価できる点](#2-高く評価できる点)
3. [重大な問題（push/PR 前に対処すべき）](#3-重大な問題pushpr-前に対処すべき)
4. [堅牢性・意味論の問題（高優先度）](#4-堅牢性意味論の問題高優先度)
5. [セキュリティ](#5-セキュリティ)
6. [仕様⇔実装ドリフト一覧](#6-仕様実装ドリフト一覧)
7. [ユースケース観点の評価](#7-ユースケース観点の評価)
8. [推奨アクション（優先順）](#8-推奨アクション優先順)

---

## 1. 総評

**プロセスとドキュメント体系は OSS 提案活動として非常に高水準。一方、コードには「fail-closed・透過等価」という自ら掲げた中核原則を破る重大な不整合が複数あり、push/PR 前に修正が必要。**

特に以下の 2 点は M1A のゴールそのものを満たせていない:

- `extra` のサイレント欠落（部分ロックで body が実行される）
- `lockEnvVars` の非等価（local はカンマ結合、remote はスペース結合）

また、実装ステップ文書に「完了」と記録されたテストの一部が実在しないという、プロセス上の綻びも見つかった（[§6 ドリフト表 #5](#6-仕様実装ドリフト一覧)）。

「何を作るべきか・なぜか」の活動は本家提案に十分耐える完成度だが、**「作ったものが宣言通りか」の検証層（仕様⇔実装⇔テスト記録の突き合わせ）に穴があり、そこに重大バグが溜まっている。**

---

## 2. 高く評価できる点

### ドキュメントの層構造が模範的

- `docs-j/remote-lock-background-j.md`（なぜ）
  → `docs-j/remote-lock-usecase-j.md`（誰のため）
  → `docs-j/remote-lock-design-notes-j.md`（判断ログ）
  → `dev/docs-j/LRR_DESIGN_P1_M1*.md`（何を作る）

  という分離は upstream 説得の土台として強力。
- design-notes の「覆す時には理由を残す」運用方針、"federation" という語を意図的に避けたスコープ制御、§7（GET/POST 使い分け）や §9（ephemeral 禁止）の判断根拠は、本家メンテナのレビューに耐える品質。

### スコープ管理と安全側設計の一貫性

明示ルーティング・一方向通信・short-poll・自動解放禁止という 4 つの柱が、ユースケース（UC-1 の物理ボード破壊回避）から直接導出されており、議論が追跡可能。

### 実装プロセスの規律

- 1 ステップ 1 コミット、各ステップにコミットハッシュ・テスト件数・日付の記録
- worktree 隔離ビルド（stabilize-build.sh）の運用化
- 12 シナリオの E2E ハーネス（docker 3 コントローラー構成）と実行レポートの保存

個人開発としては異例の追跡性。

---

## 3. 重大な問題（push/PR 前に対処すべき）

### 3-1. `extra` がサーバー側で黙って捨てられる（排他保証の侵害）【Critical】

- クライアントは `RemoteLockRequest.from(step)` で `extra` を JSON に含めて送信する
  （`remote/RemoteApiClient.java` の `buildLockRequestJson()`、110〜120 行付近）。
- しかしサーバーの `actions/RemoteApiV1Action.java:158` は `extra` をパースせず
  **`null` 固定**で `RemoteLockRequest` を構築する。
- 結果、`lock(resource: 'r1', extra: [...], serverId: 'b')` は **r1 だけロックして
  ACQUIRED を返し、body は extra もロック済みと信じて実行される**。
- UC-1（HW 破壊）の観点で最悪のサイレント部分ロック。
- クライアント側ガードもない（`LockStepExecution.resolveRemoteDisplayTarget()` は
  むしろ extra-only リクエストを許容している）。
- `RemoteLockManager.tryAcquireAll()` は HTTP 経由では到達不能のデッドコード。
- **`extra` のテストはテストスイート全体で 0 件**（unit にも HTTP 層にも存在しない）。

**最小修正:** M1A 範囲では「extra 指定 + remote は 400 で明示拒否」に倒す。
クライアント側でも AbortException で弾く。

### 3-2. lockEnvVars が local `lock()` と等価ではない【Critical】

- local の展開は **カンマ結合**: `LockStepExecution.java:578`
  `String.join(",", lockedResources.keySet())`
- remote は **スペース結合**: `remote/RemoteLockManager.java:297`
  `String.join(" ", names)`
- `LRR_DESIGN_P1_M1A.md` 自体が `"resource1 resource2"`（スペース）と書いており、
  **local 実装を確認せずに仕様を書いた**形跡がある。
- さらに local はリソースプロパティの env var（`VAR0_<PROP>`）も注入するが、
  remote には無い。
- 「透過等価」が M1A の中心ゴールである以上、仕様バグ＋実装バグの二重ドリフト。

### 3-3. 再起動で fail-closed が崩れる（設計文書に記載なし）【Critical】

- `LockableResource.remoteLockedBy` は **transient** で、リモート（B）側 Jenkins の
  再起動で全リモートロックが消える。
- クライアント A の body は走り続けているのに、B では他者が同じリソースを取得できる
  ——**相互排他の侵害**。「自動解放しない」原則と正面から矛盾する。
- M1/M1A 設計書・design-notes のいずれも再起動セマンティクスに触れていない。
- 永続化するか、少なくとも「Phase 1 の既知の制約」として文書化と運用回避策の明記が必須。

### 3-4. クライアント側に `onResume()` がない【Critical】

- ポーリング/ハートビートのタスクは transient な `ScheduledFuture` で、
  ローカル（A）側の再起動後に再武装されない。
- **QUEUED 中に再起動するとステップは永遠にハング**。
- ACQUIRED 中なら heartbeat が止まり B 側で不当に STALE 化する。
- local フローは永続化＋再開で守られているのに対し、remote フローには
  resume 設計自体が欠落している。

### 3-5. STALE ロックを管理者が解放する手段がない【Critical（運用）】

- design-notes は「解放は明示 release か管理者の手動解放のみ」とし、STALE からの
  回復を管理者に委ねているが、`remoteLockedBy` をクリアできるのは
  `RemoteLockManager.release()`（= リモートクライアントの API 呼び出し）だけ。
- UI からの手動解放（Phase 3 予定）どころか、暫定の API・CLI 経路すら無く、
  実質「Jenkins 再起動」が唯一の回復手段（しかも 3-3 の通り再起動は全ロックを消す）。
- fail-closed 設計は「気づいて手動解放できる」ことが前提なので、簡易でも
  管理者用解放経路を M1A に含めるべき。

---

## 4. 堅牢性・意味論の問題（高優先度）

### 4-1. 1 回の通信失敗で即ビルド失敗

- poll/heartbeat とも、一度の例外で `finishRemoteFailure()` に直行する。
- サーバーは heartbeat 6 回欠落（60 秒）まで許容するのに、クライアントは 0 回許容。
- 数時間の HW テスト（UC-1）が 5 秒のネットワーク瞬断で死ぬ。
- リトライ予算（例: STALE しきい値と同等まで再試行）が必要。
- あわせて、body 実行中の失敗時に `BodyExecution` を保持していないため body を
  キャンセルできず、`onFailure` 後の挙動が不定。

### 4-2. キュー意味論が local と別物

- QUEUED レコードの再試行は `ConcurrentHashMap` の反復順（事実上ランダム）で
  FIFO ですらない。
- `priority` / `inversePrecedence` / `timeoutForAllocateResource` はワイヤで運ばれる
  だけで**全部未実装**（state 図にある EXPIRED は到達不能）。
- M1A 設計書の「キュー制御・timeout 判定は remote 側の従来 lock ポリシー責務」という
  記述に反し、実装は従来ポリシーを使わない簡易並行アルゴリズム。
- 文書の主張を実装に合わせて狭めるか、従来キューへ統合するかの判断が必要。

### 4-3. リモート解放がローカル待機者を起こさない

- `RemoteLockManager.release()` は `proceedNextContext()` / `refreshQueue()` を
  呼ばないため、B 側でそのリソースを待つローカル pipeline は 15 秒周期の安全網
  （`LockWaitTimeoutPeriodicWork`）まで放置される。
- 逆方向（local unlock → remote 待機者は 1 秒 tick）と合わせ、混在環境での
  公平性が崩れている。

### 4-4. 死んだクライアントの QUEUED レコードが後からリソースを掴む

- QUEUED に TTL・生存確認がないため、クライアント消滅後もレコードが残り、
  空きが出た瞬間に ACQUIRED → 誰も heartbeat しない → STALE で塞がる、という経路。
- GET ポーリング自体を生存シグナルにする（一定時間 poll が無い QUEUED を
  失効させる）のが自然な対策。

### 4-5. release と tick の競合（孤児ロック）

- QUEUED レコードの `release()` は `syncResources` 外で map から remove するため、
  tick スレッドが同時に ACQUIRED へ昇格させると、**レコードなしの `remoteLockedBy`
  が孤児化**する（再起動以外で回復不能）。
- 昇格処理内での再確認（map に残っているかのチェック）が必要。

### 4-6. label + quantity が総数超過だと永遠に QUEUED

- 充足不可能な要求が FAILED にも EXPIRED にも倒れない。

---

## 5. セキュリティ

### 5-1. 全エンドポイントが `Jenkins.READ` のみ

- READ 権限さえあれば acquire/heartbeat/release が可能で、lockId（UUID）が唯一の防壁。
- design-notes §10 が予告した「Lock 権限相当のチェック」は未実装。
- upstream レビューで真っ先に指摘される箇所。専用 Permission か既存の plugin 権限
  への紐付けを推奨。

### 5-2. credentialsId 未設定時に匿名リクエストを送る

- `LRR_DESIGN_P1_M1.md` は「credentials 未設定は fail-closed（ビルド失敗）」と明記
  しているが、実装（`LockStepExecution.resolveAuthorizationHeader()`）は空文字を
  返して **Authorization ヘッダなしで送信**する。
- 匿名 READ が許可されたリモートでは認証なしで通ってしまい、仕様とも矛盾する。

---

## 6. 仕様⇔実装ドリフト一覧

| # | 内容 | 重さ |
|---|---|---|
| 1 | M1 設計「事前登録必須・自動作成しない」⇔ M1A 設計「remote 側ポリシーに委譲」。実装は自動作成しないが、design-notes §9 の中核保証が M1A 文書から消えている | 中 |
| 2 | M1A §3 の DSL 解決擬似コードに `forcedServerId` 分岐がない（§2/§6・実装と不整合） | 低 |
| 3 | `LockableResourcesManager.java` の `exposeLabel` Javadoc「空なら全リソース公開」は**実挙動（opt-in、空なら非公開）の正反対** | 中（危険なコメント） |
| 4 | `forcedServerId` の保存時バリデーション（remotes キー存在チェック）: 設計書・実装ステップ文書に「完了」とあるが**未実装**（`configure()` は素の bindJSON） | 中 |
| 5 | 実装ステップ文書 Step 2/5 が記録する「resource + extra テスト」「forcedServerId の config round-trip テスト」が**テストコードに存在しない**（`extra` はテスト全体で 0 件、forcedServerId テストは LockStepRemoteTest のみ） | 中（プロセス） |
| 6 | label 不一致のエラーコード: E2E 仕様は `UNKNOWN_RESOURCE`、実装は `UNKNOWN_LABEL`。また resource は 404 即時拒否、label は 202+FAILED と経路が非対称（文書化なし） | 低 |
| 7 | GET レスポンスの `message` フィールド: Step 3 で追加予定と記録、未実装（クライアントはパースするが常に null） | 低 |
| 8 | `serverId` 前後スペースの自動トリム（設計書記載）未実装 | 低 |
| 9 | remote 時に `step.validate()` を完全スキップ: `resource`+`label` 同時指定など local では拒否される DSL が remote では黙って通る（resource 優先で label 無視）— 透過等価に反する | 中 |
| 10 | notes リポジトリの `README.md` が空 — 良質な文書群への入口がない | 低 |

補足（仕様追記で済む差分）:

- `POST /acquire` レスポンスに `state` が追加されている（設計書は `lockId` のみ）。
  additive で害はないが文書化すべき。

---

## 7. ユースケース観点の評価

- UC-1（HW ボード）と UC-2（ライセンス）が安全性要求の源泉だが、
  3-1（extra 欠落）、3-3（再起動）、3-5（STALE 回復不能）はいずれも
  **この 2 つの UC を直撃**する。
- 4-1（1 回の瞬断で即失敗）は、ロックは保持されたままビルドだけ死ぬため、
  UC-1 では「テストは失敗し、ボードは塞がったまま」という最悪の組み合わせになる。
- UC-2（ライセンス）には quantity 意味論と公平性が重要で、4-2 / 4-6 が関連する。

### E2E カバレッジのギャップ

E2E は正常系＋fail-closed の 12 シナリオをカバーしているが、
**設計思想が最も問われるシナリオが未収載**:

- リモート（B）再起動中のロック保持
- クライアント（A）再起動からの復帰
- body 実行中のネットワーク分断（瞬断・長断の両方）

M1A の安全主張を裏付けるのはまさにここなので、E2E 拡張の優先候補。

---

## 8. 推奨アクション（優先順）

1. **`extra` + remote を 400 で明示拒否**（実装するより先にまず事故経路を塞ぐ）
   ＋ クライアント側でも AbortException
2. **lockEnvVars の結合文字を local に合わせる**（カンマ）。
   プロパティ env var の扱いを設計書で明示（含めるなら実装、含めないなら「非対応」と宣言）
3. **`onResume()` 実装**（poll/heartbeat タスク再武装、QUEUED ハング解消）
4. **管理者用のリモートロック解放経路**を最小限で追加（STALE 回復手段の確保）
5. **再起動セマンティクスを設計書に明記**
   （transient 採用の理由と限界、将来の永続化方針）
6. poll/heartbeat に**リトライ予算**を導入し、`BodyExecution` を保持して
   失敗時に body を中断
7. ドリフト表 #3, #4（危険な Javadoc と未実装バリデーション）を修正し、
   実装ステップ文書の「完了」記録を実テストと突き合わせて訂正
8. upstream PR 前に**権限モデル**（READ → 専用権限）と匿名送信の fail-closed 化

---

## 更新履歴

- 2026-06-11: 初版作成。M1A Step 5 完了時点（plugin `c782c28`）の全体レビュー。
