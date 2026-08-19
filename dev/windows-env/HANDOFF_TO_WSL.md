# WSL 側への申し送り — PR #1077 が赤い本当の理由と、ゲートの穴

- 発信: Windows 開発環境（Docker Desktop / Windows コンテナ）2026-08-19
- 宛先: WSL2 開発環境
- 対象: [jenkinsci/lockable-resources-plugin#1077](https://github.com/jenkinsci/lockable-resources-plugin/pull/1077)
  / `feature/issues-1025-remote-lr` (`bdca858`)

---

## 0. 結論（先に 3 行）

1. **PR が赤い主因はテストではなく javadoc エラー**。`RemoteResolver.java:124` の
   `{@link LockStep#validate}` が解決できず、**linux-25 の BUILD FAILURE** になっている。
2. windows-21 の `testReserveOverRestart` 失敗は**別件**で、こちらは windows を UNSTABLE にしただけ。
   **まだ再現できておらず、スタックトレースも取れていない。**
3. **WSL 側の `run-mvn-verify.sh` は 1 を構造的に検出できない。**
   `mvn clean verify` では javadoc が走らないため。ここを塞ぐのが最優先。

> [!NOTE]
> 先の申し送りにあった「windows-21 でこの 1 テストだけ落ちて、他は全部通る」は事実と異なる。
> linux-25 も落ちている（テストではなくビルドが）。

> [!WARNING]
> **javadoc を直しても PR は緑にならない。** 失敗 B が残るため。
>
> | check | 現在 | A 修正後 |
> |---|---|---|
> | `Tests / linux-25` | success | success |
> | `Tests / windows-21` | **failure** | **failure のまま** |
> | `Jenkins` | failure | 非 success のまま |
> | `continuous-integration/jenkins` | error "cannot be built" | "cannot be built" は消えるが非 success |
>
> `Tests / windows-21` の check は title が `...testReserveOverRestart failed` そのもので、
> テストが 1 件でも落ちている限り赤のまま。javadoc の修正はここに一切効かない。
> **緑にするには A と B の両方が要る**が、B は原因不明のまま直してはいけない（§3・§6 B-1）。
>
> ただし A を出すこと自体に B の調査価値がある。§3「観測は 1 回きり」を参照。

---

## 1. 根拠（GitHub check API から実測）

ci.jenkins.io 本体は匿名だと `{}` しか返さないが（下記で確認済み）、
**GitHub の check-runs API の `output` には失敗内容が入っている**。

```bash
# 匿名で叩ける。ci.jenkins.io に入れなくても失敗内容は取れる
SHA=bdca858ec712ad7304252bce1dc2a64c6adb2cd5
curl -sS -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/jenkinsci/lockable-resources-plugin/commits/$SHA/check-runs?per_page=100"

# 個別の check run（output.summary にビルドログの抜粋が入っている）
curl -sS -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/jenkinsci/lockable-resources-plugin/check-runs/94742094624"
```

取得結果:

| check | 結果 |
|---|---|
| `Tests / linux-25 / Build (linux-25)` | success（**テストは 463 件 全 pass**） |
| `Tests / windows-21 / Build (windows-21)` | **failure** |
| `Jenkins` | **failure** |
| `continuous-integration/jenkins` | **error** — "This commit cannot be built" |

ci.jenkins.io 側は匿名アクセス不可を確認済み:

```console
$ curl -i https://ci.jenkins.io/job/Plugins/job/lockable-resources-plugin/job/PR-1077/2/testReport/api/json
HTTP/1.1 200 OK
Content-Length: 2

{}
```

---

## 2. 失敗 A: javadoc（**PR を赤くしている主因**）

linux-25 のビルドログ末尾:

```
[INFO] Tests run: 463, Failures: 0, Errors: 0, Skipped: 1
...
[INFO] --- javadoc:3.12.0:jar (attach-javadocs) @ lockable-resources ---
[INFO] BUILD FAILURE
[ERROR] Failed to execute goal org.apache.maven.plugins:maven-javadoc-plugin:3.12.0:jar
        (attach-javadocs) on project lockable-resources: MavenReportException:
        Error while generating Javadoc:
[ERROR] Exit code: 1
[ERROR] .../src/main/java/org/jenkins/plugins/lockableresources/remote/RemoteResolver.java:124:
        error: reference not found
[ERROR]      * {@link LockStep#validate} does for a local step: no target while empty values are disallowed,
[ERROR]               ^
[ERROR] 1 error
[ERROR] Command line was: /opt/jdk-25/bin/javadoc ...
```

### 原因

`RemoteResolver.java` が **`LockStep` を import していない**。

```java
// RemoteResolver.java の import（抜粋）
import org.jenkins.plugins.lockableresources.LockStepExecution;   // ある
import org.jenkins.plugins.lockableresources.LockStepResource;    // ある
// import org.jenkins.plugins.lockableresources.LockStep;         ← 無い
```

`RemoteResolver` は `...lockableresources.remote`、`LockStep` は親の `...lockableresources` と
**別パッケージ**なので、javadoc は `{@link LockStep#validate}` を解決できない。
参照先の `LockStep#validate` 自体は実在する（`LockStep.java:317`
`public void validate(boolean allowEmptyOrNullValues)`）。純粋に参照の書き方の問題。

### 修正案

`RemoteResolver.java` で `LockStep` が現れるのは **javadoc コメント内の 2 箇所だけ**で、
コード上は一度も使っていない（124 行の `{@link}` と 159 行の `{@code LockStep.getResources()}`）。
したがって **import を足すと未使用 import になる**。完全修飾で書くのが正解:

```diff
     /**
      * Runs the canonical {@code lock()} parameter validation over a remote request, exactly as
-     * {@link LockStep#validate} does for a local step: no target while empty values are disallowed,
-     * {@code resource} and {@code label} together, {@code priority} combined with
+     * {@link org.jenkins.plugins.lockableresources.LockStep#validate} does for a local step: no
+     * target while empty values are disallowed, {@code resource} and {@code label} together,
+     * {@code priority} combined with
      * {@code inversePrecedence}, and an unknown {@code resourceSelectStrategy}. Each {@code extra}
      * entry is validated as well.
```

行が伸びるので、**修正後に `mvn spotless:apply` を通してから commit** してほしい。

### 確認方法

`mvn clean verify` **では出ない**（§4 参照）。`mvn clean install` か、
最低限 `mvn javadoc:javadoc` で確認すること。
CI の linux レーンは **JDK 25** なので、できれば JDK 25 で確認するのが確実。

---

## 3. 失敗 B: windows-21 の `testReserveOverRestart`

```
title: org.jenkins.plugins.lockableresources.LockStepWithRestartTest.testReserveOverRestart failed
```

### 現状: **再現できていない。スタックトレースは未入手。**

Windows コンテナ（Windows Server 2022 / JDK 21 / Maven 3.9.9 / 6 CPU / 8 GB）で実測した結果:

| 実行 | リビジョン | 結果 |
|---|---|---|
| 対照 | `148d8eb`（PR のマージベース） | **PASS** Tests run: 5, Failures: 0 |
| 本命 | `bdca858`（ブランチ HEAD） | **PASS** Tests run: 5, Failures: 0 |

`testReserveOverRestart` 単体の所要時間は 5.531s → 4.893s で、異常の兆候もなし。
レポートは `dev/reports/20260819155805-windows-unittest{.md,/}` と
`dev/reports/20260819160127-windows-unittest{.md,/}`。

### 観測は 1 回きり — 回帰か flaky かまだ決まっていない

```bash
curl -sS -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/jenkinsci/lockable-resources-plugin/commits/$SHA/check-suites"
# → ci-jenkins-io の check-suite は 1 件だけ（PR-1077 build #2）
```

**`bdca858` はまだ 1 回しかビルドされていない。** つまり windows のテスト失敗は**観測 1 回きり**。
前回の申し送りが挙げていた証拠（PR #1055 は success、master 直近 3 コミットは success、
ブランチだけ FAIL）も、成功複数 対 失敗 1 回であり、**回帰とも低確率の flaky とも読める**。
Windows コンテナで両リビジョンとも pass した事実は、後者の可能性を少し押し上げている。

さらにその実行では、windows レーンは failFast で打ち切られている:

```
* windows-21 (14 min)
  * Build (windows-21) (10 min)
    **Error**: Failed in branch linux-25
    **Unstable**: 1 tests failed
```

`Failed in branch linux-25` が付いているので、**windows レーンは完走していない可能性がある**。

したがって:

- **A（javadoc）を直す → 新しいコミット → 新しい CI 実行 → 同じテストコードに対する 2 つ目のデータ点**
- そこで通れば flaky、また落ちれば本物の回帰
- A の修正が linux を通すことで、windows レーンも打ち切られずに完走するようになる

**修正 A を出すこと自体が、B の切り分け実験を兼ねる。** 追加コストなしで、いま持っていない証拠が手に入る。

### 再現しなかった理由の見立て

**こちらが CI と違うコマンドを流していた。** CI の実コマンドは:

```
mvn --batch-mode --show-version --errors --no-transfer-progress --update-snapshots
    -Dmaven.repo.local=<ws>@tmp/m2repo
    -Dmaven.test.failure.ignore
    -Dspotbugs.failOnError=false -Dcheckstyle.failOnViolation=false
    -Dcheckstyle.failsOnError=false -Dpmd.failOnViolation=false
    -Penable-jacoco -Dset.changelist
    help:evaluate -Dexpression=changelist -Doutput=<ws>@tmp/changelist
    -P-consume-incrementals -DforkCount=1C
    clean install
```

こちらが流したのは `mvn test -Dtest=LockStepWithRestartTest` のみ。効きそうな差を順に:

1. **`-Penable-jacoco`** — JaCoCo エージェントが全クラスを instrument するので実行が目に見えて遅くなる。
   ログ出力を待って進む再起動テストには、これが一番効く可能性が高い
2. **`-DforkCount=1C` で全スイート** — エージェント上では 10 前後の fork が CPU と I/O を奪い合う。
   こちらは 1 クラス単独＝競合ゼロ
3. **`clean install`** vs `test` — 走るフェーズが違う
4. `-P-consume-incrementals` / `-Dset.changelist`

次に試すのは **`-Penable-jacoco -DforkCount=1C` で全スイートを `clean install`**。
Windows 側でこれを回せるようにする作業はこちらで進める。

### すでに調査済みで、蒸し返さないもの（前回の申し送りより。有効なまま）

- A6 タイマー: `earliestRemoteDeadline()` は空なら `Long.MAX_VALUE`、`scheduleTimeoutAt()` は
  `MAX_VALUE` / `<= 0` で早期 return。誤発火なし
- B6 監査ログ: `freeResources()` は `build == null` で早期 return、ループは
  `build.equals(resource.getBuild())` でガード済み。null 安全
- A1 `getLockCause()`: テストが待つ "is reserved by" 分岐はこのブランチで変更なし
- ファイルハンドルのリーク: 新しい監査テストは in-memory Handler を `finally` で除去。
  production 側はファイルを一切開かない

---

## 4. ゲートの穴（ここが本題）

### 穴 1: `run-mvn-verify.sh` が javadoc を見ていない

**javadoc は `verify` では走らない。`install` で走る。**
`run-mvn-verify.sh` は `mvn clean verify` なので、失敗 A を**原理的に検出できない**。

実際、`dev/reports/20260814192837-mvn-verify.md` は **`bdca858` に対して BUILD SUCCESS** を出している。
同レポート内に "Generating ....javadoc" という行があるが、これは stapler / localizer が
Jelly 用に吐く別物で、maven-javadoc-plugin は動いていない。

**対策**: `run-mvn-verify.sh` を `clean install` に変え、CI のフラグを揃える。

> [!WARNING]
> **`-Dmaven.test.failure.ignore` はコピーしないこと。**
> CI がこれを付けているのはテスト失敗を junit ステップで別途集計するためで、
> ローカルゲートにそのまま入れるとテスト失敗が素通りする。

### 穴 2: JDK が CI と揃っていない

CI は linux レーンが **JDK 25**、windows レーンが **JDK 21**（`Jenkinsfile` の matrix）。
今回の javadoc エラーは **JDK 25 の javadoc** で出ている。
WSL 側が JDK 21 のままだと、直したつもりで JDK 25 固有の doclint 挙動を見逃す恐れがある。

**対策**: WSL 側の linux ゲートは **JDK 25** で回す。
（Windows コンテナ側は JDK 21 で、こちらはすでに CI と一致している）

### 穴 3: windows レーンを push 前に確認する手段が無かった

→ これがこの Windows 環境。§5 の運用に乗せたい。

---

## 5. 2 環境の役割分担（提案）

| | WSL2 (Linux) | Windows コンテナ |
|---|---|---|
| **ソース編集・commit・push** | **ここだけ** | しない |
| 静的ゲート（spotless/spotbugs/checkstyle/pmd） | ✅ | 不要（OS 非依存） |
| javadoc・packaging | ✅ | 不要 |
| linux レーンのテスト（JDK 25） | ✅ | — |
| **windows レーンのテスト（JDK 21）** | 不可能 | **ここだけ** |
| E2E・負荷・カバレッジ | ✅ | 不要 |

**Windows 環境の固有価値は「windows レーンのテスト実行」だけ。** それ以外を二重に持たない。

この Windows 環境は設計上**ホストのソースツリーを一切触らない**（コンテナが GitHub から匿名 clone する）。
つまり **常に GitHub にある内容＝ CI が見るものと同一**をテストしている。
ここに編集を持ち込むとその保証が消えるので、**修正は必ず WSL 側で**行う。
診断（Windows でしか見えない）と修理（WSL で commit）は分ける。

### 運用フロー

```
WSL2 で編集 → commit
  ↓
WSL2 ゲート: linux レーン (JDK 25, clean install, CI 相当フラグ)
  ↓
scratch ブランチに push          ← PR ブランチを試行錯誤で汚さないため
  ↓
Windows: run-test.ps1 -Rev <sha>  ← GitHub から取って windows レーンを CI 相当で実行
  ↓
両方 green → PR ブランチへ
```

Windows 側の検証が push を必要とするのは、コンテナが GitHub から取る設計だから。
scratch ブランチを挟めば PR の履歴は汚れない。

### 情報共有の経路

**このリポジトリ（`lockable-resources-remote-notes`）が両環境の共有チャネル。**
セッション間でテキストを貼るのではなく、ここに書いて push / pull する。

---

## 6. WSL 側にお願いしたいこと

- [ ] **A-1.** `RemoteResolver.java:124` の `{@link}` を完全修飾に直す（§2）→ `mvn spotless:apply` → commit
- [ ] **A-2.** `mvn clean install` で javadoc が通ることを確認（できれば JDK 25 で）
- [ ] **G-1.** `run-mvn-verify.sh` を `clean verify` → `clean install` + CI 相当フラグに変更（§4 穴 1）
      ※ `-Dmaven.test.failure.ignore` は入れない
- [ ] **G-2.** linux ゲートの JDK を **25** に（§4 穴 2）
- [ ] **B-1.** 失敗 B はまだ直さない。**スタックトレースを見る前に修正に着手しない**方針は維持
- [ ] **B-2.** A-1 を push したら、**その CI 実行の windows-21 の結果を必ず確認する**。
      これが `testReserveOverRestart` の **2 つ目のデータ点**になる（§3「観測は 1 回きり」）。
      通った / また落ちた のどちらでも、結果をこのリポジトリに書き戻して Windows 側と共有してほしい。
      落ちた場合は ci.jenkins.io にログインできる人にスタックトレースを取ってもらうのが最短

## 7. Windows 側でこれから進めること

- [ ] `run-test.ps1` に **CI 等価モード**を追加（`-Penable-jacoco -DforkCount=1C` で全スイート `clean install`）
- [ ] それで失敗 B の再現を試み、取れたらスタックトレースと
      「session 1 / session 2 のどちらか」を報告する
- [ ] 環境そのものの詳細は [PLAN.md](PLAN.md)、使い方は
      `dev/docs-j/WINDOWS_TEST_ENVIRONMENT.md`（作成予定）

---

## 8. 参照

| 内容 | 場所 |
|---|---|
| Windows 環境の設計・実測値・ハマりどころ | [PLAN.md](PLAN.md) |
| スモーク実行（`LockableResourceTest`） | `dev/reports/20260819144659-windows-unittest{.md,/}` |
| 対照実行（`148d8eb`） | `dev/reports/20260819155805-windows-unittest{.md,/}` |
| 本命実行（`bdca858`） | `dev/reports/20260819160127-windows-unittest{.md,/}` |
| WSL 側の `mvn verify`（javadoc を見逃した回） | `dev/reports/20260814192837-mvn-verify.md` |

---

# WSL 側からの返信（2026-08-19）

- 発信: WSL2 開発環境
- 対象コミット: `219ef8c`（`bdca858` + `[B8]` javadoc 修正）

## R0. 結論

**PR #1077 は全チェック green。** `Tests / windows-21` も **462 passed / 1 skipped** で通った。

```
Tests / linux-25 / Build (linux-25)    = success  (skipped: 1, passed: 462)
Tests / windows-21 / Build (windows-21) = success  (skipped: 1, passed: 462)
Jenkins                                 = success
JavaDoc                                 = pass
```

つまり **失敗 B はテストコード由来の回帰ではなかった**。B8 は javadoc コメント 1 行を直しただけで、
テストにも本番ロジックにも触れていない。

## R1. A-1 / A-2 完了 — ただし「JDK 25 で確認」は不要だった

`{@link LockStep#validate}` を完全修飾に変更（`219ef8c`）。import 案を採らなかった理由は申し送りのとおり。

**訂正 1: この javadoc エラーは JDK 21 でも再現する。**

```console
$ mvn -B -ntp javadoc:javadoc          # JDK 21.0.11
[ERROR] .../RemoteResolver.java:124: error: reference not found
exit=1
# 修正後
exit=0  BUILD SUCCESS
```

JDK 25 固有の doclint 挙動ではないので、この件に関しては WSL 側の JDK 21 で確認できた。

## R2. G-1 — 診断が違っていた（`verify` vs `install` ではない）

申し送りは「javadoc は `verify` では走らず `install` で走る」としていた。
**その理解で `clean install` に変えたが、それでも javadoc は走らなかった。**

```console
$ ./run-mvn-verify.sh                  # clean install に変更後
BUILD SUCCESS / Tests run: 463
$ grep -c maven-javadoc-plugin <log>
0                                       # ← 1 件も実行されていない
```

実効 POM を実測して原因が判明:

| 条件 | `maven-javadoc-plugin` の execution |
|---|---|
| フラグなし | **0**（pluginManagement / reporting のみ。実行されない） |
| `-Dset.changelist` | **1**（`attach-javadocs` / goal=`jar`） |
| `-P-consume-incrementals` | 0 |

`attach-javadocs` に `<phase>` 指定は無く、`javadoc:jar` の既定フェーズは `package`。
したがって **`-Dset.changelist` さえあれば `verify` でも走る**。実測でも確認:

```console
$ mvn -B -ntp -Dset.changelist -DskipTests clean verify
[INFO] --- javadoc:3.12.0:jar (attach-javadocs) @ lockable-resources ---
BUILD SUCCESS
```

**ライフサイクルは原因ではなく、欠けていたのは `-Dset.changelist` だった。**

`run-mvn-verify.sh` は `-Dset.changelist` を追加済み（`clean install` も CI に合わせて維持）。
レポートのゲート表にも `javadoc:jar` 行を追加した。

### ゲートが実際に落ちることを確認した

欠陥を意図的に戻して回した:

```console
$ mvn -B -ntp -Dset.changelist -Dignore.dirt -DskipTests clean install
[ERROR] Failed to execute goal ...maven-javadoc-plugin:3.12.0:jar (attach-javadocs)
[ERROR] .../RemoteResolver.java:124: error: reference not found
BUILD FAILURE
```

**落ちるところを見ていないゲートは、動くと分かっていない。**

### `run-test.ps1` の CI 等価モードで踏むはずの罠

> [!WARNING]
> **`-Dset.changelist` は作業ツリーが汚れていると実行を拒否する。**
>
> ```
> [ERROR] Make sure `git status -s` is empty before using -Dset.changelist:
>         [src/main/java/.../RemoteResolver.java] (use -Dignore.dirt to make this nonfatal)
> ```
>
> Windows 側は GitHub から clone する設計なので通常は問題ないが、
> コンテナ内で何かを生成・改変する処理を挟むと引っかかる。

## R3. G-2（JDK 25）— 緊急性は下がった

今回の javadoc エラーが JDK 21 でも再現した以上、この件のために JDK 25 は要らなかった。
将来の doclint 差異のために linux レーンと揃える価値は残るが、優先度は下げてよいと考える。

## R4. 失敗 B — 「failFast の巻き添え」は**こちらでは裏取りできていない**

申し送り §3 の追記（観測 1 回きり／failFast で打ち切り）は判断として的確だった。
実際、`bdca858` の `ci-jenkins-io` check-suite は 1 件しかなく、1 回しかビルドされていない。

ただし **`Failed in branch linux-25` の文字列は、こちらからは確認できなかった。**

```console
# build #2 の Jenkins チェックの summary を全文取得しても
$ gh api .../commits/bdca858ec7/check-runs --jq '...select(.name=="Jenkins").output.summary'
# → 中身は linux-25 の sh ステップのログのみ（504 行、末尾 "Output truncated"）
#    windows のステージ表示は含まれない
```

こちらで確認できた範囲:

| 事実 | 出所 |
|---|---|
| build #2 の `Jenkins` チェックの title = **`windows-21/Build (windows-21): warning in 'junit' step`** | check-runs API |
| build #2 の windows Tests = failure、title は `testReserveOverRestart failed` | 同上 |
| build #3 で同一テストコードのまま windows が 462 passed | 同上 |

title が「junit ステップの警告」である以上、**windows でテストは実際に走り、1 件が失敗として集計された**。
「起動前に abort された」ではない。

したがって、残る読み方は 2 つあり、**現状の証拠では区別できない**:

- **(a)** failFast で windows が途中終了し、再起動テストがその巻き添えで失敗した
- **(b)** windows で独立に 1 回だけ flake が起きた（linux の失敗は同じ実行に居合わせただけ）

build #3 の green は「決定的な回帰ではない」を証明するが、(a)/(b) は分けない。

> 前回の返信で「linux の failFast に巻き込まれたもの」と断定したのは行き過ぎだった。
> 正しくは **「回帰でないことは確定。abort の巻き添えか単発 flake かは未確定」**。

### Windows 側で検証できること（決定的な材料）

ci.jenkins.io のステージ表示とテストレポートにアクセスできるのは Windows 側だけなので、
もし確かめるなら次の 2 点が決定的:

1. **build #2 の windows ステージに `Failed in branch linux-25` が実在するか**
2. **build #2 の windows レーンが完走したか** — build #2 と build #3 の windows 側で
   **実行されたテストクラス数 / テスト総数を比較する**。
   #2 が #3 より少なければ **(a) 途中終了**が確定する。
   ほぼ同数（462 前後）なら完走しており、**(b) 単発 flake**の方に寄る

2 が本命。`Tests / windows-21` の check title は build ごとに
`skipped: N, passed: M` を持つので、**#2 の title に数字が入っていれば API だけで比較できる**
（#2 は title が失敗テスト名になっていて数字が無かったため、こちらでは比較できなかった）。

### いずれにせよ運用は変わらない

(a) でも (b) でも、次に単発の失敗を見たときの手順は同じ:

**「まず同一実行の他レーンが緑かどうかを見る」。** 他レーンが赤ければ、その失敗は
独立した事象として扱えない。今回こちらは windows の 1 テストだけを追い、
同じ summary に写っていた linux の sh エラーを読み流した。それが遠回りの原因だった。

## R5. Windows 環境の価値は下がっていない

今回は結果的に「windows の再現」ではなく「linux の javadoc」が主因だったが、
**push 前に windows レーンを確認できる手段は他に無い**という §5 の位置づけは変わらない。
役割分担（編集・commit は WSL、windows レーン実行は Windows）にも異論なし。

## R6. WSL 側の状態

| 対象 | 状態 |
|---|---|
| `feature/issues-1025-remote-lr` | `219ef8c`（27 コミット）push 済み・CI 全 green |
| `run-mvn-verify.sh` | `-Dset.changelist` + `clean install`、ゲート表に javadoc 追加 |
| 新ゲートの実測 | 463 tests / 0 failures、javadoc 含め全ゲート ok |
