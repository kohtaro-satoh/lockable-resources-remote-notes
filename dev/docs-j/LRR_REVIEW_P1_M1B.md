# Remote LR 開発活動 レビュー（Phase 1 / M1B 完了時点）

> **レビュー日:** 2026-06-12
> **対象 plugin ブランチ:** `feature/1025-remote-lockable-resources-p1-m1b`（HEAD: `02fcfae`、M1B Step 1-8 + 追補 F-1〜F-3、360 テスト成功・E2E 16/16）
> **対象ドキュメント:** `dev/docs-j/`（LRR_DESIGN_P1_M1B / LRR_IMPLEMENTATION_STEPS_P1_M1B / E2E_TEST_SPECIFICATION）、`LRR_REVIEW_P1_M1A.md`
> **観点:** 元構想（[#1025](https://github.com/jenkinsci/lockable-resources-plugin/issues/1025)）・M1A レビュー指摘の解消状況・M1B 新規実装の正当性
> **前提:** フルビルド（~17分）は再実行せず、コードを静的に精読。テスト件数（360）/ E2E（16/16）は記録レポートを信頼。ただし後述のとおり、そのテスト層には盲点がある。

---

## M1C での解消状況（2026-06-12 追記）

本レビューの指摘を受けて M1C（M1B 問題解決サイクル）を実施。plugin ブランチ
`feature/1025-remote-lockable-resources-p1-m1c`（m1b ベース）。

| 指摘 | M1C での状況 |
|---|---|
| C-1 ラベル extra サイレント欠落 | ✅ 解消（`3f1e78a`。統一セレクタリゾルバ `validateRemoteSelectors` / `resolveRemoteAvailable` で即時取得・キュー昇格の両経路を一本化。label-extra を exposeLabel フィルタ + quantity + 重複なしでアトミック取得。空 exposeLabel 時の即時/キュー経路の挙動差も解消。E2E S14 + ユニット 7 件） |
| C-2 release() の QUEUED 昇格競合（孤児ロック） | ✅ 解消（`3f1e78a`。`release()` を `syncResources` 下に入れ、QUEUED は terminal 化してから unqueue。昇格を構造的に排除。ユニット `releasingQueuedRecordPreventsLaterPromotion`） |
| M-1 onResume QUEUED 再開で displayTarget 劣化 | ⏸ 後送り（表示のみ・機能影響なし。リソース名永続化が必要なため別途） |
| M-2 extra-only リクエストの client/server 非対称 | ✅ 解消（`5296b50`。server が extra-only を受理（local lock() と等価）。ユニット + HTTP テスト） |
| M-3 consecutivePollFailures が onResume でリセットされない | ✅ 解消（`5296b50`。onResume で 0 リセット） |
| F-1（M1C 追加検出）label quantity 未指定 = 全部 | ✅ 解消（`2d88834`。本レビューには無い指摘だが、ユーザーの「extra が M1A/M1B/M1C と未解決」指摘を機に発覚。M1A 以降 remote は label 未指定 quantity を 1 個に倒しており local "0 = all" と非等価だった。`claimSelector` で全プール取得＋POST 既定 0。E2E S15・ユニット 5 件） |

**検証（F-1 反映後の最終）:** `stabilize-build.sh`（worktree）で **mvn test 375 件 / 0 失敗 / 1 skip**
（既知 JENKINS-40787、`dev/reports/20260612232116-mvn-test.log`）。**E2E `run-e2e.sh --clean-start`
全 18 件 18/18 PASS**（S14/S15 含む、`dev/reports/20260612233944-e2e-test.md`）。
詳細は `LRR_IMPLEMENTATION_STEPS_P1_M1C.md` / `LRR_DESIGN_P1_M1C.md`。

---

## 目次

1. [総評](#1-総評)
2. [M1B で良くなった点](#2-m1b-で良くなった点)
3. [重大問題（push/PR 前に対処すべき）](#3-重大問題pushpr-前に対処すべき)
4. [軽微・観察](#4-軽微観察)
5. [テスト/検証層の評価](#5-テスト検証層の評価)
6. [推奨アクション（優先順）](#6-推奨アクション優先順)

---

## 1. 総評

M1A レビューの 16 指摘は、実装・文書とも丁寧に回収されている。とりわけ統一キューブリッジ（設計方針 E）への作り替えは設計として正しく、`unlockRemoteResources()` が local / remote 双方の待機者を起こす点、QUEUE_EXPIRED を `syncResources` 下で直列化した点など、M1A 4-3 / 4-5 の再発防止は構造的にきれいに達成されている。ドキュメント体系と工程追跡は前回同様に高水準。

ただし結論として、**「M1A レビュー指摘は全クローズ」は時期尚早**である。M1B が中核ゴールに掲げた「`extra` の完全実装」と「透過等価」を、**ラベル指定の extra エントリで自ら破っている**（C-1）。これは M1A の最重要 Critical（3-1 サイレント部分ロック）と同じクラスの fail-open バグであり、しかも `LRR_DESIGN_P1_M1B.md` §4 の記載とも矛盾する。加えて、クライアント起点の release に M1A 4-5 と同型の並行性ホールが残っている（C-2）。

M1A レビューが指摘した根本問題 —「『何を作るべきか』は高品質だが、『作ったものが宣言通りか』の検証層に穴がある」— は、M1B でも同じ形で再現している。C-1 はラベル extra のテストが 0 件だったために素通りした。

---

## 2. M1B で良くなった点

- **統一キューブリッジ（方針 E）が設計どおり機能している。** `proceedNextContext()` が local / remote を priority 比較で統一ディスパッチし、remote release が local 待機者を即座に起こす（M1A 4-3 の構造的解消）。
- **QUEUE_EXPIRED の競合排除が正しい。** `maybeScanStale()` の失効処理は `synchronized (syncResources)` 下で `record.getState() == QUEUED` を再チェックしてから `markFailed` + `unqueueRemote` する（`RemoteLockManager.java`）。M1A 4-5 の「昇格と失効の同時発生」をこの経路では正しく排除している。**——ただし同じガードがクライアント release には無い（C-2）。**
- **lockEnvVars のカンマ結合統一**（M1A 3-2）、**onResume の QUEUED 復帰 / ACQUIRED 後始末**（3-4）、**Force Release UI + RemoteUse 専用権限**（3-5 / 5-1）はいずれも実装・文書とも整合。
- **poll リトライ予算 + heartbeat 警告継続**（4-1）も決定 B/C のとおり実装され、E2E S11 で検証されている。

---

## 3. 重大問題（push/PR 前に対処すべき）

### 🔴 C-1. ラベル指定の `extra` エントリがサーバー側で黙って捨てられる【Critical / 排他保証の侵害】

`lock(resource: 'board-1', extra: [[label: 'gpu', quantity: 2]], serverId: 'b')` を実行すると、**`board-1` だけロックして ACQUIRED を返し、`gpu` ラベルのリソースは一切ロックされないまま body が実行される。**

経路:

- クライアントはラベル extra を正しく送信する — `remote/RemoteApiClient.java:115` が `r.getLabel()` を JSON に載せる。
- サーバーの POST ハンドラもラベル extra を受理する（400 にしない） — `actions/RemoteApiV1Action.java:144-164`。
- ところが取得ロジックは **`e.getResource()` のみ** を集計し、ラベルエントリを無視する:
  - 即時取得: `remote/RemoteLockManager.java:227-231` — `allNames` に resource しか追加しない。
  - キュー昇格時の空き判定: `LockableResourcesManager.java:1199-1205`（`checkRemoteResourcesAvailable`）— 同じく resource のみ。

**なぜ重大か:**

- 元構想の UC-1（HW ボード破壊回避）/ UC-2（ライセンス）を直撃する最悪のサイレント部分ロック。M1A 3-1 で「これが本機能の中核安全要求」と認定済みの事故そのもの。
- `LRR_DESIGN_P1_M1B.md` §4 は `{ "label": "probe", "quantity": 1 }` を**サポート例として明記**し、「label 指定エントリは exposeLabel と一致する候補 0 件なら 404 UNKNOWN_LABEL」と検証仕様まで書いている。実装はそのコードパスを持たない → **設計⇔実装ドリフト**。
- local `lock()` はラベル extra を正しくロックするため、**透過等価（`LRR_DESIGN_P1_M1B.md` §1 の大前提）に正面から反する**。

**テスト盲点:** `extra` のテストは `RemoteLockManagerTest`（`extraResourcesAreLockedAtomically` / `extraResourceNotAcquiredWhenOneIsBusy`）も `RemoteApiV1ActionTest` も**すべて resource ベースのみ**。ラベル extra のテストは 0 件。M1A レビュー §6 #5 が指摘した「検証層の穴」がそのまま再現している。

**修正方針（2択。M1C 開始前に要決定）:**

- **(a) 実装する（透過等価に全振り）:** `tryAcquireAll` とキュー判定（`checkRemoteResourcesAvailable`）をラベル extra 対応に拡張する。main label と同じ exposeLabel フィルタ + quantity を適用し、main + 全 extra を全体アトミックに取得する。`LRR_DESIGN_P1_M1B.md` §4 の記載どおりで、追加修正不要。
- **(b) M1B では未対応と倒す（事故経路をまず塞ぐ）:** POST で `extra[i].label != null` を **400 で明示拒否**し、設計書 §4 / §10 を「extra は resource 指定のみ対応」に訂正する。M1A の「実装するより先に事故経路を塞ぐ」方針と整合。

どちらでも可だが、**現状の「黙って落とす」だけは不可**。併せてラベル extra のユニット/E2E を追加すること。

### 🟠 C-2. `release()` が `syncResources` 外で状態判定 → QUEUED 昇格と競合し孤児ロック化【並行性】

`remote/RemoteLockManager.java:176-195` の `release()` は `records.remove()` の後、**ロックを取らずに** `state = record.getState()` を読んで分岐する。

QUEUED レコードに対する release（クライアント中断、onResume の best-effort 解放など）と、別スレッドの `proceedRemoteEntry`（`LockableResourcesManager.java:1031-1048`、`syncResources` 下）が次の順で交差すると孤児ロックが生まれる:

1. release: `records.remove(lockId)` → record 取得、`state == QUEUED` を読む
2. 別スレッド: リソースが空き、`proceedRemoteEntry` が `entry.isValid()`（= QUEUED、まだ真）を見て `lockForRemote` で `remoteLockedBy = lockId` を設定、`markAcquired`
3. release: `state == QUEUED` の分岐で `unqueueRemote(lockId)` → 既に除去済みで no-op

結果、**リソースは `lockId` で remote ロックされたまま、対応する record は `records` マップから消えている**。`heartbeat` / `release` / `maybeScanStale`（`records.values()` を走査）のいずれもこの lockId に到達できず、STALE 化すらせず、**Jenkins 再起動まで解放不能**。

これは M1A 4-5（release と tick の競合）と同型である。QUEUE_EXPIRED 側（`RemoteLockManager.java:354-362`）は `syncResources` 下で再チェックして正しく潰しているのに、**クライアント起点の release だけ同じガードが抜けている**。

**修正方針:** `release()` 全体を `synchronized (syncResources)` で囲み、QUEUED 分岐では先に `record.markFailed(...)`（terminal 化）してから `unqueueRemote` する。terminal 化すれば `getNextRemoteEntry` の `entry.isValid()` が false になり昇格が排除される（`syncResources` は再入可なので `unlockRemoteResources` のネストも問題なし）。

---

## 4. 軽微・観察

| # | 内容 | 重さ | 場所 |
|---|---|---|---|
| M-1 | onResume の QUEUED 再開で `displayTarget = remoteLockId` になる。リソース名が非永続のため再起動後のログ表示が lockId に劣化（機能影響なし、表示のみ） | 低 | `LockStepExecution.java:769` |
| M-2 | extra-only リクエストの非対称。クライアント `resolveRemoteDisplayTarget` は extra 単独を許容するが、サーバー POST は main resource/label 必須で 400（MISSING_TARGET）。整合させるか文書化を | 低 | `LockStepExecution.java:420` / `RemoteApiV1Action.java:102` |
| M-3 | `consecutivePollFailures` が `onResume` でリセットされない。再起動前のカウンタが永続化されて引き継がれ、長時間 QUEUED 後の再起動で予算が目減りし得る | 低 | `LockStepExecution.java:64, 762-773` |

---

## 5. テスト/検証層の評価

- **件数は十分（360 ユニット + 16 E2E）だが、ネガティブ/等価パスに穴がある。** C-1 はラベル extra のテストが 0 件だったために素通りした。これは M1A レビュー §6 #5 と同じ構造的弱点。
- **不足しているテスト（M1C で拡充すべき）:**
  - **ユニット（plugin 側）:** ラベル extra の即時取得 / QUEUED 昇格 / exposeLabel フィルタ / アトミック性（一部 busy → 全体 QUEUED）。C-2 の release-vs-昇格 競合の回帰テスト（terminal 化で昇格が排除されることの確認）。
  - **E2E（notes 側）:** ラベル extra のアトミック取得シナリオ（S10 の拡張または新規）。可能なら release-while-QUEUED の孤児ロック非発生確認。
- E2E 仕様書（`E2E_TEST_SPECIFICATION.md`）にも対応するテスト項目（P1M1C タグ）を追記すること。

---

## 6. 推奨アクション（優先順）

1. **C-1 を塞ぐ**（実装 (a) or 400 拒否 (b)。M1C 開始前に方針決定）+ ラベル extra のユニット/E2E を追加。これが片付くまで「extra 完全実装」「全クローズ」は名乗らない。
2. **C-2: `release()` を `syncResources` 下に入れ、QUEUED を terminal 化**してから unqueue。回帰テストを追加。
3. メモリ／notes の「レビュー全クローズ」記述を訂正し、C-1 / C-2 を M1C 課題として登録。
4. 軽微 M-1〜M-3 は任意（M1C に同梱するか後送りかを判断）。

---

## 更新履歴

- 2026-06-12: 初版作成。M1B 完了時点（plugin `02fcfae`）の全体レビュー。C-1（ラベル extra サイレント欠落）・C-2（release の QUEUED 昇格競合）を Critical / 並行性問題として検出。
