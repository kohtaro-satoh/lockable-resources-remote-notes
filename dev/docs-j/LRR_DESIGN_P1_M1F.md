# Remote Lockable Resources 仕様書（Phase 1 / M1F）

> **出典:** [jenkinsci/lockable-resources-plugin #1025](https://github.com/jenkinsci/lockable-resources-plugin/issues/1025)
> **前提文書:** `LRR_DESIGN_P1_M1E.md`（M1E 仕様）/ `LRR_REVIEW_P1_M1E.md`（M1E 完了レビュー）
> **対象スコープ:** Phase 1 M1F（**M1E レビュー指摘の選別対応** — ネットワークブリッジのトランスポート/境界層の堅牢化のみ実施。
>   lock() ロジック由来の穴と remote 独自判定の増加は意図的に見送り、設計ドキュメントに「残置する懸念」として明記）

---

## 1. M1F の位置づけ — レビュー指摘の「観点による選別」

M1F は機能追加サイクルではない。`LRR_REVIEW_P1_M1E.md` で挙げた指摘を、ユーザー協議で確定した**一本の観点**で選別し、
該当するものだけを実施する整理サイクルである。

> **観点（2026-06-14 ユーザー確定）:** 「**lock() の既存ロジックに最大限乗り、ネットワークブリッジ由来以外の remote 独自判定を増やさない**」。
> したがって —
> - **lock() ロジック由来の穴 → そのまま放置**（remote だけ特別扱いするコードを足さない）。設計ドキュメントに懸念として明記。
> - **ネットワークブリッジ（トランスポート/HTTP 境界）の堅牢化 → 実施**（lock() 意味論にも canonical 委譲にも無干渉）。

## 2. 選別結果

| レビュー指摘 | 区分 | M1F 判断 | 根拠 |
|---|---|---|---|
| **M1E-1**（QUEUED 中に削除された名前指定リソースが昇格スキャンの `fromNames(create=true)` で ephemeral 再生成・孤児化） | **lock() ロジック由来** | **コード放置・ドキュメント明記** | `create=true` は canonical の name 解決そのもの（local の on-demand ephemeral 機能）。remote だけ `create=false` にするのは「remote 独自判定の追加」であり観点に反する。狭く・非 fail-open・孤児 1 個に収束するため受容 |
| **admission**（unknown/unexposed → 即時 404） | remote 終端ポリシー | **維持** | 2026-06-13 確定済（存在秘匿＋無限 QUEUE 回避）。enqueue の単一ソース。再議論しない |
| **M1E-2**（resource と label 同時指定で admission は resource・解決は label を見る） | local 由来の曖昧さ・非 fail-open | **放置（ドキュメント明記）** | local lock() 自身が label 優先で resource を無視する挙動。candidateFilter が公開を強制するためバイパス不成立。remote で独自判定を足さない |
| **M1E-3**（lease 操作が REMOTE 権限のみで lockId 所有者を非検証） | 設計上の信頼モデル | **放置（ドキュメント明記）** | 所有者一致チェックは新しい remote 判定。小規模・相互信頼前提では不要。多テナント化時に P1+ |
| **L-b**（`RemoteConnection.url` のスキーム未検証 — `file:` 等が通る） | **ブリッジ堅牢化** | **実施** | url は HTTP トランスポート（`RemoteApiClient`）専用。非 http(s) を入口で弾く |
| **L-c**（POST ボディを上限なく読み切る） | **ブリッジ堅牢化** | **実施** | 認証済みでも巨大ボディで OOM 誘発し得る。HTTP 境界に上限 |
| **L-d**（POST が `FAILED`（非 `UNKNOWN_*`）を 202 にフォールスルー） | **ブリッジ堅牢化** | **実施** | HTTP ステータス写像の防御。`FAILED` は必ず 4xx（現状到達不能でも将来コードに堅い） |
| **L-a**（`setRemotes` だけ binding 途中で `save()`） | ブリッジ設定の見た目・無害 | **放置** | `configure()` が `BulkChange` で包み `bc.commit()` で一括保存するため、フォーム経路では eager save は既に抑止されアトミック。堅牢性の実害なし |
| **L-e**（`getExposeLabels()` 毎回 `split`） | 性能ナノ最適化 | **放置** | 堅牢性ではなく性能。small-scale で無視可能。状態追加の割に得が薄い |

> **実施は L-b / L-c / L-d の 3 点のみ**。いずれも remote のトランスポート/HTTP 境界に閉じ、lock() ロジック・canonical 委譲・
> 透過等価の意味論には一切触れない。

## 3. 実施項目の詳細

### 3-1. L-b: remote base URL のスキーム検証

- `RemoteConnection.validate()` に「`url` は `http://` または `https://` で始まること」を追加（非 http(s) は `IllegalArgumentException`）。
  `validate()` は `setRemotes`（フォーム `configure` 経由・CasC 経由の両方）から呼ばれる**永続前の唯一のゲート**なので、ここが実質強制点。
- あわせて `RemoteConnection.DescriptorImpl` を `@Extension` 登録し `doCheckUrl`（`FormValidation`）を追加 → 設定 UI で即時フィードバック。
- 判定は共有ヘルパ `isHttpUrl`（trim ＋ 小文字化して prefix 判定）。`RemoteApiClient.resolve` の `URI.create` と整合。
- **非該当の懸念（残置）:** url の到達性・FQDN 妥当性・ポートなどは検証しない（運用設定値・ネットワーク依存のため）。スキーム種別のみを弾く。

### 3-2. L-c: POST ボディサイズ上限

- `RemoteApiV1Action.parseJsonBody` に**文字数上限 `MAX_BODY_CHARS`（1 MiB）**を導入。読み取り累積が上限超過で
  `PayloadTooLargeException`（private、`IOException` サブクラス）を投げ、POST ハンドラが **413 `PAYLOAD_TOO_LARGE`** にマップ。
- 既存の不正 JSON 経路（`400 INVALID_JSON`）は維持。413 を先に catch して区別。
- **上限値 1 MiB の根拠:** 正当な lockRequest（resource/label/extra/reason 等の短い文字列）は通常 KB オーダー。1 MiB は実用上十分な余裕。

### 3-3. L-d: POST の FAILED → 4xx 写像一般化

- POST `/acquire` で `enqueue` が `FAILED` を返した場合、`UNKNOWN_RESOURCE`/`UNKNOWN_LABEL` は従来どおり **404**、
  **それ以外の `FAILED` は 400**（errorCode をそのまま、無ければ `ACQUIRE_FAILED`）にマップ。`FAILED` が 202 成功にフォールスルーする経路を塞ぐ。
- **防御的変更:** 現状 `enqueue` 内の非 `UNKNOWN_*` な `FAILED` は `MISSING_TARGET` のみで、これは境界の `MISSING_TARGET`
  チェックで到達不能。したがって本変更は将来コードに対する防御であり、現行の観測挙動は変えない（既存 404 テストはそのまま緑）。

## 4. 意図的に残置する懸念（再議論防止のための明文化）

以下は M1F で**意図的に触らない**と確定した。今後「直すべきでは」と蒸し返さないため記録する。

- **M1E-1【残置・既知】昇格経路の `fromNames(create=true)` による ephemeral 再生成。**
  QUEUED 中に admin が名前指定リソースを削除すると、昇格スキャンが当該名を ephemeral として再生成し（直後に exposeLabel
  フィルタが弾くので非ロック・孤児化）`config` に永続する。**これは canonical の name 解決ロジックそのものに由来する**（local lock()
  の on-demand ephemeral 機能と同一コードパス）。remote だけ `create=false` にする＝ブリッジ由来でない remote 独自判定の追加であり、
  「lock() 既存ロジックに乗る」観点に反するため**採らない**。発火条件は狭く（exposed・busy・QUEUED 中削除）、fail-open ではなく
  （誤ったロックは付与されない）、孤児は名前あたり 1 個に収束、admin 操作起因。受容コストとして残置する。
  - 将来この観点を変える（remote 独自の no-create を許容する）場合のみ、canonical シームに `create` フラグを一段通す案
    （local は `true`／remote は `false`、`candidateFilter` と同じ追加方式）を再検討する。それまでは触らない。
- **M1E-2【残置・非 fail-open】resource と label の同時指定。** local lock() が label 優先で resource を無視する挙動を継承。
  公開は `candidateFilter` が強制するためバイパスはない。remote で独自に弾く判定は足さない。
- **M1E-3【残置・設計上】lease 操作の所有者非検証。** トラストバウンダリ＝REMOTE 権限という既存モデルを維持。多テナント化は P1+。
- **L-a / L-e【残置・無害】** §2 のとおり（BulkChange で eager save は無害／getExposeLabels の split は性能のみ）。

## 5. スコープ整理

### 含む（M1F）

| 項目 | 内容 |
|---|---|
| L-b | `RemoteConnection` url スキーム検証（`validate` 強制 ＋ `doCheckUrl` UI） |
| L-c | POST ボディ上限 1 MiB → 413 `PAYLOAD_TOO_LARGE` |
| L-d | POST の `FAILED`（非 `UNKNOWN_*`）→ 400 `ACQUIRE_FAILED`（202 フォールスルー封鎖） |
| ドキュメント | M1E-1/M1E-2/M1E-3/L-a/L-e を「意図的に残置する懸念」として明文化（再議論防止） |

### 含まない（M1F スコープ外）

| 項目 | 備考 |
|---|---|
| M1E-1 のコード修正 | lock() ロジック由来。観点により残置（§4） |
| M1E-2 / M1E-3 のコード修正 | 残置（§4） |
| L-a / L-e | 残置（無害／性能のみ） |
| admission の撤去・変更 | remote 終端ポリシーとして維持 |

## 更新履歴

- 2026-06-14: 初版作成。M1E レビュー指摘を「lock() ロジック由来は放置・ネットワークブリッジ堅牢化は実施」の観点で選別。
  実施は L-b（url スキーム検証）/ L-c（ボディ上限 413）/ L-d（FAILED→4xx）の 3 点。M1E-1（昇格経路 ephemeral 再生成）は
  canonical の `create=true` 由来として**意図的に残置**し、本書 §4 に明文化（再議論防止）。M1E-2/M1E-3/L-a/L-e も残置理由を記録。
