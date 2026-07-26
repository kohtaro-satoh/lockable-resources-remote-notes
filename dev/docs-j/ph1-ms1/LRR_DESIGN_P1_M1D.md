# Remote Lockable Resources 仕様書（Phase 1 / M1D）

> **出典:** [jenkinsci/lockable-resources-plugin #1025](https://github.com/jenkinsci/lockable-resources-plugin/issues/1025)
> **前提文書:** `LRR_DESIGN_P1_M1C.md`（M1C 仕様）/ `LRR_RESULT_P1_M1C.md`（M1C 結果）
> **対象スコープ:** Phase 1 M1D（**真のブリッジ化** — lock() のネットワーク越し透過等価）

---

## 目次

1. [M1D の設計思想（なぜ機能別残件が出たのか）](#1-m1d-の設計思想なぜ機能別残件が出たのか)
2. [2 層アーキテクチャ](#2-2-層アーキテクチャ)
3. [ブリッジ層：正準パスへの委譲](#3-ブリッジ層正準パスへの委譲)
4. [フィルタ層：RemoteResourceExposurePolicy（ExtensionPoint）](#4-フィルタ層remoteresourceexposurepolicyextensionpoint)
5. [返り値・例外の透過](#5-返り値例外の透過)
6. [撤去するコード / 残すコード](#6-撤去するコード--残すコード)
7. [真の非等価（橋渡し不能）](#7-真の非等価橋渡し不能)
8. [スコープ整理](#8-スコープ整理)

---

## 1. M1D の設計思想（なぜ機能別残件が出たのか）

M1A→M1B→M1C を通じて `extra`/`label` の不具合が「直したつもり」で再発し続けた（C-1, F-1）。
根本原因は **server が lock() の解決・env var 生成を再実装している**こと:

```text
現状（M1C まで）:
  client が lock 引数を JSON 化 → server が JSON をパースして
    「どのリソースをいくつロックするか」「env var をどう作るか」を
    RemoteLockManager / claimSelector / generateLockEnvVars で独自に再導出
  ⇒ lock() の意味論の各次元（extra / label / quantity / プロパティ / selectStrategy /
     ephemeral）を一つずつ別個に実装することになり、一つずつ独立にドリフトしうる
```

local lock() には「機能別残件」が存在しない。なぜなら**唯一の正準パス**を通るから:

```text
local LockStepExecution.start():
  step.getResources()                    → List<LockableResourcesStruct>（main + 各 extra）
  → getAvailableResources(structs, strategy)   ← 解決の唯一の真実（label/quantity(0=all)/extra/selectStrategy）
  → lock(available, build)
  → proceed(name→properties マップ)            ← env var の唯一の真実（VAR / VAR0 / VAR0_<PROP>）
```

**M1D の方針:** server も同じ正準パスに通す。再実装をやめれば、機能別残件は**構造的に発生しない**。
> remote 機能は「時間的遅延」「ネットワーク障害時の fail-close」「再起動 transient」を除けば、
> ローカルと透過等価。M1D で残りの意味論差を全消しする。

## 2. 2 層アーキテクチャ

フィルタ（公開/非公開・認可）はブリッジの**外側の層**に分離する。ブリッジはフィルタが定義する
**公開サーフェスの内側で完全透過**。

```text
┌─ アクセスポリシー層（remote 固有・ネットワーク制御層の外側）
│    RemoteResourceExposurePolicy（ExtensionPoint、§4）。既定 = exposeLabel。
│    「どのリソースが remote に見えるか」を Predicate<LockableResource> として供給。
│    将来: 公開制限 / per-client allowlist / 認可 をここに差し込む。
│      ↓ Predicate<LockableResource> visible
├─ ネットワーク制御層（ブリッジ）= lock() の透過等価。M1D で完成。
│    可視サーフェスの上で local と同一解決（§3）。lock() 意味論は一切再実装しない。
│    既存の粗いゲート（remoteApiEnabled=ブリッジ開閉、RemoteUse 権限=呼び出し認可）は入口に残す。
└─ 真の非等価（橋渡し不能、§7）= 時間遅延 / fail-close / 再起動 transient のみ。
```

「透過等価」は**可視サーフェスの内側**で成立すればよい。exposeLabel は local lock() に無い remote 固有の
概念なので、ブリッジに直書きせずフィルタ層に置くのが正しい（M1C までは解決コードに混入していた）。

## 3. ブリッジ層：正準パスへの委譲

### 3-1. 解決：`getAvailableResources` に委譲

`RemoteLockRequest` を `List<LockableResourcesStruct>`（`LockStep.getResources()` を鏡写し）に変換し、
**local と同じ** `getAvailableResources` を呼ぶ。可視性は predicate で渡す:

```text
getAvailableResources(structs, logger, selectStrategy, Predicate<LockableResource> candidateFilter)
  ├ label 構造体: getFreeResourcesWithLabel(...) が
  │    候補を candidateFilter で絞った後に amount 選択（amount<=0 → 可視マッチ全部 = "0 = all"）
  └ name 構造体: fromNames(names, create=true)（ephemeral は allowEphemeralResources が透過適用）
                  candidateFilter を満たさない名前は不可視 → 取得不可
```

これ一本で **extra / label / quantity(0=all) / resourceSelectStrategy / 重複排除 / ephemeral** が
すべて canonical 由来になる（個別実装しない）。空き判定は既存 `isFree()`（`isLocked()` は
`remoteLockedBy` を含む）が remote ロックを正しく尊重するため、二重ロックは起きない。

**コア追加は後方互換オーバーロードのみ:** `getAvailableResources(...)` / `getFreeResourcesWithLabel(...)` に
`Predicate<LockableResource>` 引数版を足し、既存版は `r -> true` で委譲。local は無改修。

### 3-2. env var：local と共有関数化

`proceed()` 内のインライン env var 生成を共有関数に抽出し、**local と remote が同じ関数を呼ぶ**:

```text
buildLockEnvVars(variable, LinkedHashMap<resourceName, List<LockableResourceProperty>>)
  → { VAR: "r1,r2", VAR0: "r1", VAR0_<PROP>: <値>, VAR1: "r2", ... }
```

server は acquire 確定時に `name→properties` マップ（手持ちの `LockableResource` から取得）でこれを呼び、
結果を `lockEnvVars` として client に返す。プロパティは name/value 文字列＝シリアライズ可能なので透過。
→ **リソースプロパティ env var が透過化**、remote の `generateLockEnvVars`（部分実装）を撤去。

### 3-3. キューも収束

remote キューエントリも `List<LockableResourcesStruct>` を持ち、昇格判定で
`getAvailableResources(structs, candidateFilter)` を呼ぶ。local の
`getNextQueuedContextEntry`→`getAvailableResources(entry.getResources())` と同型になり、
remote 固有の `resolveRemoteAvailable` を撤去。

## 4. フィルタ層：RemoteResourceExposurePolicy（ExtensionPoint）

公開/非公開の判定を **Jenkins `ExtensionPoint`** として分離・公開する:

```java
@Restricted(Beta.class) // SPI
public interface RemoteResourceExposurePolicy extends ExtensionPoint {
    /** この lockId 要求の文脈で resource が remote クライアントに見えるか。 */
    boolean isExposed(LockableResource resource, RemoteLockRequest request /*, Authentication caller*/);
}
```

- ブリッジは全 `@Extension` を畳んで `Predicate<LockableResource>` を作り、§3-1 のコアへ渡す。
- **既定実装 `ExposeLabelPolicy`（`@Extension`）** = 現行 exposeLabel 挙動（resource が exposeLabel を持てば公開）。
  → 既定で今までどおり動く。
- 第三者は `@Extension` を足すだけで公開制限/allowlist/認可に差し替え・拡張できる。
  **「フィルタ機構を用意してある」ことを PR でコード・docs 両方に示す。**
- policy メソッドは文脈リッチ（resource + request + 将来 caller）にしておき、ブリッジが
  `Predicate<LockableResource>` に畳む。コアは単純 predicate しか見ない（関心の分離）。
- テストは `@TestExtension` で任意 policy を注入可能。

> 注: `remoteApiEnabled`（サーバー全体の開閉）と `RemoteUse` 権限（呼び出し認可）は
> **ネットワーク制御層の入口ゲート**として残す（per-resource 解決フィルタではない）。

## 5. 返り値・例外の透過

- **lock() の返り値**: remote フローは **step 自体が client 側で走り**、body も client 側で実行される。
  body の結果は `BodyExecutionCallback.TailCall` が `Object` として**自動パススルー**する
  （local の `Callback` と同じ）。→ **将来 lock() が boolean/string/任意 Object を返すようになっても、
  ブリッジは何もせず透過**。M1D は TailCall を壊さない（`onSuccess(null)` で握り潰さない）ことだけ守る。
- **例外**: server 側エラーは errorCode にマップし、client 側で対応する例外（AbortException 等）に
  復元。fail-close 系（通信失敗）は §7 のとおり保持して失敗。

## 6. 撤去するコード / 残すコード

| 撤去（lock() 意味論の再実装） | 置き換え先（canonical / 共有） |
|---|---|
| `LRM.resolveRemoteAvailable` / `claimSelector` | `getAvailableResources(structs, candidateFilter)` |
| `LRM.validateRemoteSelectors` / `validateSelector` / `hasExposedCandidate` | フィルタ層（policy）＋ canonical の充足判定（不足は QUEUED、local と同じ） |
| `RemoteLockManager.generateLockEnvVars` | 共有 `buildLockEnvVars`（local と同一） |
| `RemoteLockManager.tryAcquireRecord` の独自分岐 | request→structs アダプタ ＋ canonical 呼び出し |

**残す（真に remote 固有）:** トランスポート（HTTP/wire）、耐障害性（poll/heartbeat/onResume・リトライ予算）、
ロック表現（`remoteLockedBy`・`RemoteLockRecord`・STALE・QUEUE_EXPIRED）、フィルタ層（policy）、
管理者 Force Release。これらは lock() 意味論ではなくネットワーク/運用の都合。

## 7. 真の非等価（橋渡し不能）

純ブリッジでも残る、ネットワーク越し故の制約（M1B §1 で既出）:

- **時間遅延**（往復レイテンシ）。
- **ネットワーク障害時の fail-close**（死んだ回線は橋渡しできない。lock は自動解放しない）。
- **再起動セマンティクス**（server 再起動で transient な `remoteLockedBy` が消失）。

これら以外は M1D で透過化する。**未知ラベル/未存在リソースの扱いも local に合わせる**:
local は充足不能要求を QUEUED で待つ（資源は後から増え得る、M1B §5）。remote も同様に QUEUED とし、
M1C の即時 `UNKNOWN_RESOURCE`/`UNKNOWN_LABEL` terminal 化はフィルタ層の admission（明示拒否）に整理する。

## 8. スコープ整理

### 含む（M1D）

| 項目 | 内容 |
|---|---|
| 解決の canonical 委譲 | `getAvailableResources(structs, strategy, candidateFilter)`。extra/label/quantity(0=all)/selectStrategy/重複排除/ephemeral を一括透過 |
| env var 共有 | `buildLockEnvVars`（プロパティ env var 含む）を local/remote 共有 |
| フィルタ ExtensionPoint | `RemoteResourceExposurePolicy`（既定 = exposeLabel）を公開。docs/コードに seam 明記 |
| 返り値透過 | TailCall 維持（body の Object 結果パススルー） |
| キュー収束 | remote キューも canonical 充足判定へ |

### 含まない（M1D スコープ外）

| 項目 | 備考 |
|---|---|
| M-1 onResume displayTarget 劣化 | 表示のみ・後送り（リソース名永続化が必要） |
| フィルタの実装拡充（allowlist 等） | seam のみ用意。実装は将来（P1+） |
| 真の非等価（§7） | 設計上の制約として維持 |

## 更新履歴

- 2026-06-13: 初版作成。M1D（真のブリッジ化）を定義。解決を canonical へ委譲、env var を local と共有、
  公開判定を `RemoteResourceExposurePolicy`（ExtensionPoint、既定 exposeLabel）として分離。返り値は
  TailCall による Object パススルーで将来も透過。
