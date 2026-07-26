# M1J 設計（Remote lock - Phase 1 / M1J：remote 設定画面の help リンク 404 対策）

> 起点: PR #1055 レビュー（reviewer が remote 設定画面のスクリーンショットで報告）
> ブランチ: `feature/1025-remote-lr-p1-m1`（M1J コミット `e83534b`、reviewer が `upstream/master` `4dbbfc1` 上へ
> rebase した PR head `7fd218b` の上に積み上げ）
> 位置づけ: **M1H/M1I 完了・PR #1055 提出後**の、UI ヘルプの軽微な表示バグ 1 点の是正。挙動変更なし・
> ロジック不変（jelly の help URL 文字列のみ）。

## 1. 目的

`Manage Jenkins > System` の **Remote Lockable Resources（Server / Client）** 各設定項目の (?) ヘルプアイコンを
クリックしたとき、ヘルプ本文を正しく表示すること。修正前は 8 項目すべてで
**「ERROR: Failed to load help file: Not Found」（HTTP 404）**になっていた。

## 2. 真因

- `f:entry` の明示 `help=` 属性を **`help-<field>`（ハイフン区切り）**で書いていた。
  例: `help="/descriptor/org.jenkins.plugins.lockableresources.LockableResourcesManager/help-remoteApiEnabled"`
- Jenkins core（`hudson.model.Descriptor#getHelpFile`）が実際に生成し、Stapler が解決できるヘルプ URL は
  **`/descriptor/<FQCN>/help/<field>`（スラッシュ区切り）**。`getHelpFile` は `page = "/descriptor/"+id+"/help"`
  に `page += '/' + fieldName` を連結する（`jenkins-core` の実装で確認）。
- ディスク上のヘルプ HTML の**ファイル名**は `help-<field>.html`（例 `help-exposeLabel.html`）という規約だが、
  **配信 URL のパスはスラッシュ**（`help/<field>`）。ファイル名の `-` を URL にそのまま持ち込んだのが誤り。
- ハイフン形の URL は存在しないパスなので 404 → (?) ポップアップが本文取得に失敗し
  「Failed to load help file: Not Found」を表示。
- **潜在バグ**: 最初の #1025 コミット（`4f3577f`、`config.jelly` と `help-*.html` が同時追加された時点）から
  一度も直っていない。ロック機能・API 動作には無関係で、ヘルプ表示だけの問題。

## 3. 設計（最小修正）

- `config.jelly` 2 ファイルの明示 `help=` を全 8 箇所、`help-<field>` → **`help/<field>`** に置換。ロジック・
  ファイル名・文言は変更しない。

| ファイル | 修正した help 属性 |
|---|---|
| `LockableResourcesManager/config.jelly` | `remoteApiEnabled` / `exposeLabel` / `clientId` / `forcedServerId` / `remotes`（5） |
| `RemoteConnection/config.jelly` | `serverId` / `url` / `credentialsId`（3） |

> 補足: `help=` を明示せず `f:entry field="..."` だけにすれば core が `getHelpFile(field)` で URL を自動導出する
> （＝そもそもハイフンを書く余地がない）。ただし本修正は差分最小・レビュー容易性を優先し、既存の明示 help 記法を
> 維持したままスラッシュへ揃える方針とした。

## 4. テスト方針

- **実機確認（正本）**: 稼働中コンテナに対し 8 本のヘルプ URL を直接叩き、修正前 404 → 修正後 **200＋正しい本文**を確認。
  - 例: `GET /jenkins/descriptor/org.jenkins.plugins.lockableresources.LockableResourcesManager/help/remoteApiEnabled`
    → 200 `Enables or disables the remote lock REST API ...`
  - 8/8 すべて 200。旧ハイフン形は引き続き 404（存在しないパスとして正しい）。
- **回帰ゲート**: `run-mvn-verify.sh`（`mvn clean verify`）＋ `run-e2e.sh` 全件＋ `run-load.sh --preset stress`。
  jelly 変更のためコンパイル/テストへの影響は無いが、rebase 後（`7fd218b` 上）でも全ゲート緑を確認する。
- **デプロイ注意**: jhX ボリュームに前回の `.jpi` が残ると ref/plugins seed が上書きされず旧プラグインのまま。
  未コミットの作業ツリー fix を E2E に反映するには `start.sh --clean --in-place-build`（`--clean` だけだと
  コミット済み HEAD をビルドするので fix が乗らない点にも注意）。

## 5. 含まない（M1J スコープ外）

| 項目 | 備考 |
|---|---|
| help 本文（`help-*.html`）の加筆 | 今回は URL 解決のみ。文言は不変 |
| 明示 help 属性の撤去（field 自動導出への統一） | 差分最小を優先。別途整理する場合は follow-up |
| クライアント UI / read-only ミラー | Phase 2（issue #1025） |

## 6. 検証

開発サイクル（`作業手順一覧.md`）に従い、`run-mvn-verify.sh` ＋ `run-e2e.sh` ＋ `run-load.sh` を動確の正本とする。
plugin `e83534b`（rebase 後 `7fd218b` の上）で以下を確認済み（レポートは `dev/reports/` に同梱）。

- `mvn verify`: **BUILD SUCCESS**、テスト **386 / Failures 0 / Errors 0 / Skipped 1**（既知の JENKINS-40787 恒常スキップ）、
  静的ゲート（spotless/spotbugs/checkstyle/pmd）すべて ok。
- E2E: **21 / 21 PASS**（fail 0 / skip 0）。
- 高負荷（`--preset stress`、4×50 = 200 並行ジョブ）: **182 SUCCESS / 18 FAILURE（全 18 が clean な `LOCK_WAIT_TIMEOUT`）**、
  **相互排他違反 0 / HUNG 0**。M1I の性質（枯渇 timeout は clean な `LOCK_WAIT_TIMEOUT`）が rebase 後も維持されていることを再確認。

## 変更ファイル一覧（plugin、コミット `e83534b`）

| ファイル | 変更 |
|---|---|
| `LockableResourcesManager/config.jelly` | 明示 help 5 箇所を `help-<field>` → `help/<field>` |
| `RemoteConnection/config.jelly` | 明示 help 3 箇所を `help-<field>` → `help/<field>` |

合計 2 ファイル / +8・-8（文字列置換のみ）。

## 更新履歴

- 2026-07-19: 初版作成。PR #1055 レビューで報告された remote 設定画面のヘルプリンク 404（潜在バグは `4f3577f`）への
  最小修正を M1J 開発サイクルとして定義。8 箇所の help URL をスラッシュ形へ是正、実機 8/8=200 で確認、
  rebase 後（`7fd218b`）で mvn verify 386/0/1skip・E2E 21/21・load stress 200 全緑。
