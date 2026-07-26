# M1D 結果（Remote lock - Phase 1 / M1D）

> **対象 plugin ブランチ:** `feature/1025-remote-lockable-resources-p1-m1d`（HEAD `819daa0`）
> **設計:** `LRR_DESIGN_P1_M1D.md` / **手順:** `LRR_IMPLEMENTATION_STEPS_P1_M1D.md`
> **位置づけ:** 真のブリッジ化 — server が lock() 意味論を再実装するのをやめ、ローカルの正準パスに委譲。

---

## 1. 達成したこと

**「機能別残件」を構造的に解消した。** server は `RemoteLockRequest` を local と同じ
`List<LockableResourcesStruct>` に変換し、同じ `getAvailableResources()` を呼ぶ。公開判定は
candidate-visibility predicate（`Predicate<LockableResource>`）として外側から注入する。

| 旧「真の非等価」（M1C 残件） | M1D での解 |
|---|---|
| リソースプロパティ env var | ✅ 透過（`LockStepExecution.buildLockEnvVars` を local/remote 共有。`VAR0_<PROP>` が body に届く） |
| ephemeral 自動作成 | ✅ 透過（`fromNames(create=true)` 経由、`allowEphemeralResources` ゲートで local と同一） |
| resourceSelectStrategy | ✅ 透過（canonical `getAvailableResources(…, strategy)` がそのまま処理） |

副次的に **extra / label / quantity(0=all) / 重複排除** も canonical 由来になり、再実装由来の
ドリフトが起きない構造になった（C-1/F-1 の再発防止）。

## 2. アーキテクチャ（2 層）

- **ブリッジ層（透過等価）**: canonical 委譲。`resolveRemoteAvailable`/`claimSelector`/
  `validateRemoteSelectors`/`generateLockEnvVars` を撤去。未知/未公開は QUEUED（local 等価）。
  返り値は `BodyExecutionCallback.TailCall` の Object パススルーで将来も透過。
- **フィルタ層（差込口）**: `RemoteResourceExposurePolicy`（`ExtensionPoint` 公開）。既定 `ExposeLabelPolicy`
  が現行 exposeLabel を再現。第三者が `@Extension` で公開制限/allowlist/認可を差し替え・拡張できる。
  ブリッジは policy を `Predicate` に畳んで canonical へ渡す。
- 既存の粗いゲート（`remoteApiEnabled` / `RemoteUse` 権限）はネットワーク制御層の入口として存続。

**残る真の非等価（橋渡し不能・設計上維持）**: 時間遅延 / fail-close / 再起動 transient のみ。

## 3. 検証結果

| 観点 | 結果 | 証跡 |
|---|---|---|
| ユニット（worktree フル） | **mvn test 375 件 / 0 失敗 / 1 skip**（既知 JENKINS-40787） | `dev/reports/20260613125351-mvn-test.log` |
| E2E（`--clean-start` 全件） | **19 シナリオ 19/19 PASS** | `dev/reports/20260613132702-e2e-test.md` |
| 新規 E2E | S16 `remote-resource-properties`（プロパティ env var 伝搬） | 同上 |
| 新規ユニット | プロパティ env var 伝搬 / 公開ポリシー隠蔽 | RemoteLockManagerTest |

S16 CP03: `S16RES0_S16_IP` がプロパティ値（例 `10.9.8.37`）と一致 → プロパティ env var が
remote body に伝搬することを実環境で実証。

## 4. 注記（透過の代償＝local 挙動の継承）

canonical 委譲により、**local の既知の癖も継承**する（透過等価の必然）:
- 同一 label を main と extra で要求するケース（`lock(label:'X', extra:[[label:'X']])`）は、local の
  `getAvailableResources` の `isPreReserved` 挙動どおり（M1C の `claimSelector` のような「別個 2 個」確保は
  しない）。M1C 専用の dedup テスト 2 件は削除（remote 固有挙動を持たないため）。
- 未知 resource/label は terminal ではなく QUEUED（local 同様、資源が後から増え得る）。

## 5. 状態

- plugin `feature/...-m1d` HEAD `819daa0`（クリーン）。**push/PR は未**（完璧化後・ユーザー指示待ち）。
- ドキュメント（DESIGN/IMPLEMENTATION_STEPS/本書、j+e）整備済み。E2E 仕様に S16/`m1d-series` 反映済み。

## 更新履歴

- 2026-06-13: 初版作成。M1D（真のブリッジ化）の結果サマリ。mvn 375 / E2E 19/19。
