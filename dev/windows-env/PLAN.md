# Windows コンテナ単体テスト環境 構築プラン

Docker Desktop の **Windows コンテナ**上で
[kohtaro-satoh/lockable-resources-plugin](https://github.com/kohtaro-satoh/lockable-resources-plugin)
の単体テストを実行し、ci.jenkins.io の `windows-21` でのみ再現する
`LockStepWithRestartTest#testReserveOverRestart` の失敗を**手元で再現してスタックトレースを取る**
ための環境を構築する。

- 対象 PR: [jenkinsci/lockable-resources-plugin#1077](https://github.com/jenkinsci/lockable-resources-plugin/pull/1077)
- 対象ブランチ: `feature/issues-1025-remote-lr` (`bdca858`)
- 対照コミット: `148d8eb`（PR のマージベース = upstream master 相当）

> [!IMPORTANT]
> このプランの目的は「**直す**こと」ではなく「**失敗の中身を見る**こと」。
> スタックトレースを見る前に修正に着手しない（WSL2 側からの申し送り事項）。

> [!CAUTION]
> **2026-08-19 追記: 前提が間違っていた。** GitHub の check API を直接叩いて確認した結果、
> PR #1077 が赤い理由は **2 つ**あり、申し送りの「windows でこの 1 テストだけ落ちる、
> 他は全部通る」は事実と異なる。詳細は §0。このプランが組んだ環境は
> **2 つのうち片方しか、しかも CI と違うコマンドでしか見ていない**。

---

## 0. PR #1077 が実際に赤い理由（2026-08-19 実測）

GitHub の check-runs / status API から取得（ci.jenkins.io 本体は匿名だと `{}` しか返さないが、
**GitHub 側の check run の output には失敗内容が入っている**）。

| check | 結果 |
|---|---|
| `Tests / linux-25 / Build (linux-25)` | success（テストは 463 件 全 pass） |
| `Tests / windows-21 / Build (windows-21)` | **failure** |
| `Jenkins` | **failure** |
| `continuous-integration/jenkins` | **error** — "This commit cannot be built" |

### 失敗 A: linux-25 の BUILD FAILURE（javadoc）

**これが PR を赤くしている主因。テストではない。**

```
[ERROR] Failed to execute goal org.apache.maven.plugins:maven-javadoc-plugin:3.12.0:jar
        (attach-javadocs) on project lockable-resources: MavenReportException:
[ERROR] src/main/java/org/jenkins/plugins/lockableresources/remote/RemoteResolver.java:124:
        error: reference not found
[ERROR]      * {@link LockStep#validate} does for a local step: ...
[ERROR] 1 error
```

原因は単純で、**`RemoteResolver.java` が `LockStep` を import していない**。
`LockStepExecution` と `LockStepResource` は import されているのに `LockStep` だけ抜けている。
`RemoteResolver` は `...lockableresources.remote` パッケージ、`LockStep` は親の
`...lockableresources` パッケージなので、javadoc は参照を解決できない。
参照先の `LockStep#validate` 自体は実在する（`LockStep.java:317`）。

linux-25 は 463 テスト全 pass。**落ちているのは javadoc だけ。**

### 失敗 B: windows-21 の テスト失敗（1 件）

```
title: org.jenkins.plugins.lockableresources.LockStepWithRestartTest.testReserveOverRestart failed
```

申し送りのとおり。ただしこちらは windows ブランチを **UNSTABLE** にしただけで、
`Jenkins` チェックを `failure` にした直接の原因は A の方。
スタックトレースは ci.jenkins.io 側にしかなく、匿名では取得できない（確認済み）。

### CI が実際に流しているコマンド

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

JDK は linux-25 が **25**（`/opt/jdk-25/bin/javadoc`）、windows-21 が **21**。

---

## 0.1 これまでの確認方法の妥当性 → **不十分**

| # | 何が漏れていたか |
|---|---|
| 1 | **javadoc は `verify` では走らない。`install` で走る。** 既存の `run-mvn-verify.sh` は `mvn clean verify` なので、失敗 A を**構造的に検出できない**。実際 `bdca858` に対して BUILD SUCCESS を出している（`dev/reports/20260814192837-mvn-verify.md`）。同レポート内の "Generating ....javadoc" は stapler/localizer が出す別物で、maven-javadoc-plugin は動いていない |
| 2 | この Windows harness は `mvn test -Dtest=LockStepWithRestartTest`。CI の `clean install` とは走るフェーズが違い、失敗 A は原理的に出ない |
| 3 | CI は `-Penable-jacoco`。JaCoCo エージェントが全クラスを instrument するので実行が目に見えて遅くなる。**timing 依存の再起動テストにはこれが効く可能性が高い**のに、こちらは付けていない |
| 4 | CI は `-DforkCount=1C` で全スイート並列。こちらは 1 クラス単独＝競合ゼロ |
| 5 | CI は `-P-consume-incrementals` と `-Dset.changelist`。こちらは `.mvn/maven.config` の既定（`-Pconsume-incrementals`）のまま |

S7/S8 が両方 pass したのは harness の欠陥というより、**そもそも CI と違うものを測っていた**ため。

---

## 1. ゴールと完了条件

| # | ゴール | 完了条件 |
|---|---|---|
| G1 | Windows コンテナ内で単体テストが走る | 任意のテストクラスが 1 件以上 green で完走する |
| G2 | 対照実行（`148d8eb`）が取れる | `LockStepWithRestartTest` の pass/fail が記録される |
| G3 | ブランチ実行（`bdca858`）が取れる | 同上 |
| G4 | 失敗の中身が取れる | 例外／アサーション本文と**どちらの session で起きたか**が判明する |
| G5 | 再実行できる | スクリプト 1 本でリビジョンを変えて再実行でき、結果が残る |

G4 が本丸。G2 と G3 が**両方 pass** した場合は「再現できなかった」という結論を報告する
（環境差の切り分けに進む。§8 参照）。

---

## 2. 実測した前提（このマシンで確認済み）

| 項目 | 実測値 | 備考 |
|---|---|---|
| Docker Desktop | 4.53.0 (211793) / Engine 29.0.1 | context = `desktop-windows` |
| コンテナ種別 | **windows**（切替済み） | `docker info` → `OSType: windows` |
| 既定の分離モード | **hyperv** | `Default Isolation: hyperv` |
| ホスト OS | Windows 11 Pro 25H2 / build **26200**.9168 | |
| CPU / メモリ | 12 CPU / 31.91 GiB | |
| C: 空き容量 | 177 GB | 十分 |
| 取得済みイメージ | `mcr.microsoft.com/windows/servercore:ltsc2022` (4.04 GB) | ベースレイヤを再利用できる |
| Temurin Windows イメージ | `eclipse-temurin:21-jdk-windowsservercore-ltsc2022` が存在 | manifest 取得で確認済み |

プラグイン側で効いてくる設定：

| 項目 | 内容 | 影響 |
|---|---|---|
| `Jenkinsfile` | `[platform: 'windows', jdk: 21]`, `forkCount: '1C'` | JDK は **21** で揃える |
| `pom.xml` | Jenkins baseline 2.541.3 / parent 6.2211.x | Maven 3.9.x 必須 |
| `.mvn/extensions.xml` | `git-changelist-maven-extension` 1.13 | **`.git` が無いとビルドが成立しない**（後述 D3） |
| `.mvn/maven.config` | `-Pconsume-incrementals -Pmight-produce-incrementals` | incrementals リポジトリへの疎通が要る |

---

## 3. 設計方針（なぜこの構成にするか）

### D1. プロセス分離は使えない → Hyper-V 分離で行く

Windows のプロセス分離はコンテナのベース OS ビルドとホストのビルドが一致している必要があるが、
ホストは build **26200**（Windows 11 25H2）で、これに対応するベースイメージは公開されていない。
よって Hyper-V 分離（既定）を使う。`--isolation=hyperv` を明示する。

### D2. ビルドツリーと `.m2` は**コンテナ内**に置く（bind mount しない）

Hyper-V 分離ではホストディレクトリのマウントが仮想 SMB 経由になり、小さいファイルを大量に触る
Maven ビルドでは著しく遅くなる。したがって：

- ソースツリー … コンテナ内 `C:\src\lrp`
- ローカルリポジトリ … コンテナ内 `C:\m2`（`-Dmaven.repo.local=C:\m2`）
- 取り出すのは**結果だけ**（surefire レポートとログ）→ `docker cp` でホストへ回収

ホストの `..\..\lockable-resources-plugin` を**マウントしない**副次効果として、
WSL2 側で使っている作業ツリーを `target/` で汚さずに済む。

### D3. リポジトリはコンテナ内で clone する（**SSH 鍵は渡さない**）

`git-changelist-maven-extension` が `.git` を読むため、ソースは**本物の git クローン**でなければならない。
ファイルコピーでは不可。よってイメージビルド時に GitHub から **HTTPS で anonymous clone** する。
`master` と対象ブランチの両方を fetch しておき、リビジョンの切替は**実行時**に `git checkout` で行う。

**認証情報はコンテナに一切持ち込まない。** 確認済みの根拠：

```console
$ GIT_TERMINAL_PROMPT=0 git ls-remote https://github.com/kohtaro-satoh/lockable-resources-plugin.git
148d8ebc...  refs/heads/master
bdca858e...  refs/heads/feature/issues-1025-remote-lr
```

フォークは public で、対照コミット・対象コミットの両方が匿名で取得できる。
ホスト側の clone は `git@github.com:` (SSH) だが、コンテナ側は HTTPS に切り替えるだけでよい。
コンテナは**読むだけ**（clone / checkout）で push しないので、書き込み権限も不要。

> [!NOTE]
> Windows コンテナのビルドは BuildKit の `--mount=type=secret` が使えない（classic builder）ため、
> 仮に鍵が必要になっても安全に渡す手段が乏しい。認証を必要としない設計にしておくこと自体が対策になっている。

**万一フォークが private 化された場合のフォールバック**（鍵を渡すのではなく、鍵を不要にする方法）:
ホスト側の clone から `git bundle create lrp.bundle --all` を作り、ビルドコンテキストに置いて
`COPY` → `git clone lrp.bundle C:\src\lrp` する。`.git` は 3.2 MB しかないのでコストは無視できる。

### D6. 永続化ボリュームは使わない

named volume も bind mount も**状態の保存には使わない**。実行間で残るのはイメージだけ。

- 効果: 実行ごとに必ずクリーンなツリーからビルドが始まるため、前回の `target/` が結果に混ざらない
- コスト: 通常なら「`.m2` が毎回冷える」が気になるところだが、
  **このブランチは `pom.xml` を変更していない**（`git diff master...bdca858 -- pom.xml` が空）ため、
  D4 で `148d8eb` を基準に焼き込んだ `.m2` が `bdca858` の依存関係をそのまま満たす。
  再取得はほぼ発生しない
- 結果の回収はマウントではなく `docker cp` で行う（§6）

### D4. `.m2` はイメージに焼き込む（ウォームアップ）

Jenkins プラグインのビルドは初回に数百 MB〜1 GB 超を取得する。これを毎回やると再実行の回転が悪い。
イメージビルドの最後に `148d8eb` で `mvn -B -ntp test-compile` を走らせ、依存関係を
`C:\m2` に降ろした状態でレイヤに固める。ブランチ側の追加依存は実行時に差分取得されるだけで済む。

### D5. ベースイメージは Temurin 公式を使う

`eclipse-temurin:21-jdk-windowsservercore-ltsc2022` は `servercore:ltsc2022` を土台にしているため、
取得済みのベースレイヤを再利用でき、追加ダウンロードは JDK レイヤ分のみ。
JDK を自前で展開するより保守が楽で、CI の `jdk: 21` 指定にも素直に一致する。

---

## 4. ディレクトリ構成（作成予定）

```
dev/windows-env/
├── PLAN.md                  このファイル
├── .gitignore
├── docker/
│   └── Dockerfile           JDK21 + Maven + MinGit + clone + .m2 ウォーム
└── scripts/
    ├── build-image.ps1      イメージビルド
    ├── run-test.ps1         リビジョンとテスト指定を受けて実行 → 結果回収
    └── shell.ps1            コンテナに入って手作業で調べる用
```

使い方のドキュメントは `windows-env/README.md` ではなく、既存のドキュメント体系に載せる：

- `dev/docs-j/WINDOWS_TEST_ENVIRONMENT.md` … 日本語版（**先に書く / 作業原本**）
- `dev/docs-e/WINDOWS_TEST_ENVIRONMENT.md` … 英語版（最後に対にする）

実行結果は既存の `run-mvn-verify.sh` の慣習に合わせて `dev/reports/` に置く：

- `dev/reports/yyyymmddhhmmss-windows-unittest.md` … サマリ（Markdown）
- `dev/reports/yyyymmddhhmmss-windows-unittest/` … 生の surefire レポートと mvn ログ

---

## 5. Dockerfile の中身（方針）

```
FROM eclipse-temurin:21-jdk-windowsservercore-ltsc2022
```

以下を順に積む。

1. **長いパス対策** — レジストリ `LongPathsEnabled=1` を有効化し、
   `git config --system core.longpaths true` を設定する。
   Jenkins のテストハーネスは一時ディレクトリを深く掘るため、`MAX_PATH` は現実的な地雷。
2. **短い作業パス** — `TEMP`/`TMP` を `C:\t` に、ソースを `C:\src\lrp`、
   ローカルリポジトリを `C:\m2` に置いて、そもそもパスを伸ばさない。
3. **Maven 3.9.9** — zip を取得して `C:\tools\maven` に展開、`PATH` に追加。
   取得元は **`archive.apache.org`**。`dlcdn.apache.org` は最新版しか置いておらず 3.9.9 は 404 になる（確認済み）。
   WSL2 側が使っている 3.9.9 に合わせる。
4. **MinGit**（Git for Windows portable）— clone / checkout と D3 のために必要。
   フル版インストーラより軽い。`MinGit-2.55.0.4-64-bit.zip` を固定で使う。
5. **clone** — `https://github.com/kohtaro-satoh/lockable-resources-plugin.git` を
   `C:\src\lrp` へ（HTTPS / 認証なし。D3）。`master` と `feature/issues-1025-remote-lr` の両方を fetch
   （**shallow にしない**。`git-changelist` が履歴を読むため）。
6. **`.m2` ウォーム** — `148d8eb` を checkout して
   `mvn -B -ntp -Dmaven.repo.local=C:\m2 test-compile`。

7. **実行スクリプトを最終レイヤに COPY** — `C:\bin\run-test.ps1` を ENTRYPOINT にする。
   最後に置くのは、スクリプトを直したときに `.m2` ウォームまで焼き直さないため。

イメージ名: `lrr-win-test:ltsc2022-jdk21`

### 実装時に判明した注意点

- **`ENV PATH=...` を使ってはいけない。** このイメージの config には `PATH` が入っておらず
  （`JAVA_VERSION` のみ）、`${PATH}` は空に展開される。PATH の実体はイメージ内のマシン環境変数側にあり、
  `ENV PATH` を書くとそれを覆い隠して java / cmd / powershell まで解決できなくなる。
  Temurin イメージ自身と同じくマシン環境変数を書き換える方式にした
  （`setx` は 1024 文字で切れるので `[Environment]::SetEnvironmentVariable(..., 'Machine')` を使う）。
- コンテナ内の PowerShell は **5.1**（`5.1.20348.5499`）。`&&`・三項演算子・`??` は使えない。
- **PowerShell 5.1 は、`-` で始まりクォートされていないネイティブ引数を最初の `.` の位置で分割する。**
  最初のビルドはこれで落ちた。ホストで再現を取った結果：

  | 書き方 | 実際にプロセスへ渡る文字列 |
  |---|---|
  | クォート無し | `-B -ntp -Dstyle` `.color=never` `-Dmaven` `.repo.local=C:\m2 test-compile` |
  | シングルクォート | `-B -ntp -Dstyle.color=never -Dmaven.repo.local=C:\m2 test-compile` |

  Maven からは `.repo.local=C` が goal prefix に見えて
  `No plugin found for prefix '.repo.local=C'` になる。対策は**全ての mvn 引数をシングルクォートする**こと。
  - 先頭が `-` でない引数は影響を受けない（git の `core.longpaths` は無事だった）
  - 配列を `@args` で splat する場合も影響を受けない（検証済み）。
    したがって `run-test.ps1` 側は修正不要で、Dockerfile の `RUN` 行だけの問題
- PowerShell の `;` 区切りでは、ネイティブコマンドの非ゼロ終了は
  `$ErrorActionPreference='Stop'` でも**ビルドを止めない**。
  ウォームアップ後に `if ($LASTEXITCODE -ne 0) { throw }` を明示的に入れた。
- `docker build` にも `-m 4g` が要る。ビルドコンテナも Hyper-V 分離で、既定 1 GB では
  `.m2` ウォームアップが持たない（R1 のビルド時版）。

---

## 6. 実行スクリプトの仕様

### `build-image.ps1`

```powershell
.\build-image.ps1                          # インクリメンタル（キャッシュ利用）
.\build-image.ps1 -CleanBuild -Cleanup     # 全レイヤ再構築 → 旧レイヤを回収
.\build-image.ps1 -CleanupOnly             # ビルドせずディスク回収のみ
.\build-image.ps1 -CleanupOnly -PurgeImage # タグ付きイメージごと削除
.\build-image.ps1 -CleanupOnly -PurgeAll   # ベースイメージ含め全消し
.\build-image.ps1 -PurgeAll                # 全消ししてから何もない状態でビルド
```

| 引数 | 既定 | 意味 |
|---|---|---|
| `-Tag` | `lrr-win-test:ltsc2022-jdk21` | イメージ名 |
| `-Memory` | `4g` | ビルドコンテナのメモリ。**明示必須**（§9 R1 のビルド時版） |
| `-CleanBuild`（別名 `-NoCache`） | off | 全レイヤを作り直す。約 10 分 |
| `-Cleanup` | off | dangling イメージを全て回収（`docker image prune -f`） |
| `-PurgeImage` | off | タグ付きイメージも削除。ベースは残るので再ビルドにネットワーク取得は不要 |
| `-PurgeAll` | off | ベースイメージ含め未使用を全消し（`docker system prune -af`）。次回は約 4 GB 再 pull |
| `-CleanupOnly` | off | ビルドせず cleanup のみ。purge 系を単独指定した場合も同じ |

所要時間の実測: クリーンビルド **10m28s** / インクリメンタル（`run-test.ps1` 変更のみ）**2 秒**。

**cleanup は範囲を絞らない。** このマシンには永続利用する Windows コンテナが無く、
ここにあるものは全てリポジトリから再現できるので、消しすぎた場合の最悪コストは
「フルビルド + ベースイメージの再取得」で済む。

> [!IMPORTANT]
> purge 系はビルドの**前**にしか走らない。ビルド後の `-Cleanup` は常に `dangling` レベルに固定してある
> — さもないと、いま作ったばかりのイメージを自分の cleanup で消すことになる。
> `Invoke-Cleanup` がスイッチを直接読まずレベルを引数で受け取るのはこのため。

> [!NOTE]
> ビルド失敗時は cleanup を走らせない。中間レイヤは再試行の再開点であり、
> 失敗したステップのコンテナは調査に使えるため。

### `run-test.ps1`

```powershell
.\run-test.ps1 -Rev <commit-ish> [-Test <pattern>] [-Repeat <n>] [-Memory 8g] [-Cpus 6] [-Keep]
```

| 引数 | 既定 | 意味 |
|---|---|---|
| `-Rev` | （必須） | `git checkout` するリビジョン。`148d8eb` / `bdca858` |
| `-Test` | `LockStepWithRestartTest` | `-Dtest=` に渡す値 |
| `-Repeat` | `1` | flaky 判定用に同じ条件で N 回まわす |
| `-Memory` | `8g` | **明示必須**（§9 R1） |
| `-Cpus` | `6` | |
| `-Keep` | off | 失敗時にコンテナを残して手動調査する |

コンテナ内でやること：

1. `git fetch --all` → `git checkout --detach <rev>` → `git clean -xdff` → `git log -1` を記録
2. `mvn -B -ntp -Dstyle.color=never -Dmaven.repo.local=C:\m2 -Dtest=<pattern> test`
3. 終了コードに関わらず `target/surefire-reports` を丸ごと `C:\out\run-N\` へ退避し、
   mvn の全出力を `mvn.log` として保存。surefire の XML を舐めて失敗ケース名を `summary.txt` に出す

> [!NOTE]
> 当初 `-Dsurefire.useFile=false` を付ける想定だったが**やめた**。このフラグは
> `surefire-reports/*.txt` の生成自体を止めてしまう。XML（スタックトレース入り）と `.txt` と
> mvn の全ログを 3 つとも回収する方が、事後解析の材料としては確実。

ホスト側でやること：

4. `docker cp <container>:C:\out` で回収 → `dev/reports/<ts>-windows-unittest/` へ
5. サマリ Markdown を生成 → `dev/reports/<ts>-windows-unittest.md`
   （リビジョン、実行コマンド、pass/fail、失敗テストの本文）
6. コンテナを削除（`-Keep` 指定時は残す）

`docker run` に `-v` は**付けない**（D6）。`--rm` も付けず、走り終えた停止コンテナから
`docker cp` で結果を吸い出してから削除する — `--rm` だと結果ごと消えるため。

---

## 7. 実行手順（フェーズ）

| フェーズ | 内容 | 目的 |
|---|---|---|
| P0 | 前提確認 | **完了**（§2） |
| P1 | イメージビルド | 環境が組み上がること |
| P2 | スモーク: `-Test LockableResourceTest -Rev 148d8eb` | G1。軽いクラスで配管を通す |
| P3 | **対照**: `-Test LockStepWithRestartTest -Rev 148d8eb` | G2。先にこちらを回す |
| P4 | 本命: `-Test LockStepWithRestartTest -Rev bdca858` | G3・G4 |
| P5 | 結果の読み取りとレポート化 | G4 |
| P6 | 必要なら `-Repeat 5` で安定性を見る | flaky かどうかの判定 |

**P3 を P4 より先に回すことは省略しない。**「この環境ではこのテストがそもそも不安定」なのか
「ブランチが壊した」のかを分ける唯一の手段であり、WSL2 側の申し送りでも最初に指示されている。

---

## 8. 結果の解釈

| P3 (148d8eb) | P4 (bdca858) | 結論 | 次の手 |
|---|---|---|---|
| pass | **fail** | 再現成功。ブランチ起因 | スタックトレースを読む。**ここが目的地** |
| pass | pass | 再現せず | §10 Q2 へ。CI との環境差（OS ビルド、forkCount、タイミング）を詰める |
| fail | fail | この環境固有の不安定さ | CI の証跡（master は windows-21 で success）と矛盾。ブランチではなく**環境を疑う** |
| fail | pass | 想定外 | 環境が信用できない。P1 からやり直す |

失敗が取れた場合に必ず記録すること（申し送りの要求事項）：

- アサーション文または例外の**本文**
- **session 1 と session 2 のどちら**で起きたか
  - session 1 = `resource1` を reserve → `lock('resource1')` のパイプラインがブロック →
    同じリソースの freestyle ジョブを queue → Jenkins 再起動
  - session 2 = unreserve → パイプラインが lock を取得 →
    `Lock released on resource [Resource: resource1]` → `Finish` → `waitUntilNoActivity()`

### 調査済みで、蒸し返さないもの（WSL2 側からの申し送り）

- A6 タイマー: `earliestRemoteDeadline()` は空なら `Long.MAX_VALUE`、`scheduleTimeoutAt()` は
  `MAX_VALUE` / `<= 0` で早期 return。誤発火なし
- B6 監査ログ: `freeResources()` は `build == null` で早期 return、ループは
  `build.equals(resource.getBuild())` でガード済み。null 安全
- A1 `getLockCause()`: テストが待つ "is reserved by" 分岐はこのブランチで変更なし
- ファイルハンドルのリーク（Windows の古典的原因）: 新しい監査テストは in-memory Handler を
  `finally` で除去。production 側はファイルを一切開かない

---

## 9. Windows 固有の落とし穴と対策

| # | 落とし穴 | 対策 |
|---|---|---|
| R1 | **Hyper-V 分離コンテナの既定メモリは 1 GB** | `--memory 8g` を必ず明示。Jenkins のテストは再起動を伴うため、既定値では OOM という「別の失敗」を見ることになる |
| R2 | `MAX_PATH` 260 文字 | `LongPathsEnabled=1` + `core.longpaths` + 短い作業パス（`C:\src\lrp`, `C:\m2`, `C:\t`）の三段構え |
| R3 | bind mount が遅い（SMB 経由） | D2。ビルドツリーをマウントしない。回収はファイル数の少ない出力だけ |
| R4 | コンテナ内 DNS 解決に失敗することがある | 失敗したら `--dns 8.8.8.8` を付けて切り分け。イメージビルド段階で判明する |
| R5 | 初回が長い（ベース + JDK + `.m2` ウォーム） | 20〜40 分を見込む。以後はイメージ再利用で数分 |
| R6 | ウイルス対策のリアルタイムスキャン | `C:\ProgramData\Docker` を除外すると体感が変わる。必要になったら提案する（**勝手には触らない**） |
| R7 | 改行コード | `git config --system core.autocrlf false` でチェックアウトを LF のままにし、CI との差を減らす |
| R8 | `forkCount: '1C'` との差 | 1 クラス指定なので実害は小さいが、再現しない場合は CI と同じ `-DforkCount=1C` を試す候補として残す |
| R9 | ロケール / 文字コード | JDK 18+ は `file.encoding=UTF-8` が既定。コンテナのロケールは en-US。日本語ホストとの差は入らない |

---

## 10. 確定した方針と、残る未確定事項

### 確定（2026-08-18 合意）

| # | 論点 | 決定 |
|---|---|---|
| Q1 | レポートの置き場所 | **`dev/reports/`** に統一。既存の `yyyymmddhhmmss-` 命名と retention ポリシーに乗せる |
| Q3 | clone 元 | フォーク `kohtaro-satoh/lockable-resources-plugin` から HTTPS で取る。ホストツリーはマウントしない |
| Q4 | スクリプトの言語 | PowerShell。既存 `dev/` の bash とは混在するが、ディレクトリで分かれているので許容 |
| — | 永続化ボリューム | **使わない**（D6） |
| — | 使い方ドキュメント | `windows-env/README.md` ではなく `dev/docs-j/WINDOWS_TEST_ENVIRONMENT.md`（日本語が原本）。英語版 `dev/docs-e/` は最後に対にする |
| — | SSH 鍵 | **不要**。public フォークを匿名 HTTPS clone する（D3） |

### 残る未確定（P4 の結果を見てから相談）

- **Q2. 再現しなかった場合にどこまで踏み込むか** — ベースイメージを `ltsc2019` に落として
  CI エージェントに寄せる、`-DforkCount=1C` を CI に合わせる、`-Repeat` を増やす、等。
  いずれも時間を使う話なので、先に P3・P4 の結果を出してから判断する
- **Q5. ベースイメージを digest で固定するか** — 現状は
  `eclipse-temurin:21-jdk-windowsservercore-ltsc2022` というタグ指定で、時間が経てば
  別の JDK パッチ版を掴む。再現用 harness としては digest 固定が筋だが、
  セキュリティ更新を取り込めなくなるトレードオフがある。
  clean build は通っているので急ぎではない

---

## 11. 作業ステップ

- [x] S1. `dev/windows-env/` の骨組みを作る（`docker/`, `scripts/`, `.gitignore`）
- [x] S2. `docker/Dockerfile` + `docker/run-test.ps1`（コンテナ内ランナー）を書く（§5）
- [x] S3. `scripts/build-image.ps1` を書く
- [x] S4. イメージをビルドする（P1）— **完了**

  ```
  lrr-win-test:ltsc2022-jdk21   5.99 GB
  クリーンビルド（--no-cache, 18/18 ステップ, キャッシュ利用 0 件）  10m28s
  ```

  **`build-image.ps1 -NoCache` で通しのクリーンビルドが通ることを実測で確認済み。**
  最初の 2 回はレイヤキャッシュをまたいでいた（1 回目に step 1〜15、2 回目に step 16〜18）ため、
  通しでは一度も走っていなかった。

  クリーンビルドの検証にあたって、実際の穴を 1 つ塞いだ:

  > [!WARNING]
  > `git fetch` / `git checkout` / `git clone` の終了コードを見ていなかった。
  > PowerShell の `;` 区切りはネイティブコマンドの非ゼロ終了でレイヤを落とさないので、
  > `git checkout --detach 148d8eb` が失敗しても **master 先端で `.m2` をウォームした「緑の」レイヤ**が
  > 出来上がる。対照実行（§7 P3）の基準がずれても気づけないという、この harness にとって
  > 最悪の壊れ方だった。各ネイティブコマンドに `$LASTEXITCODE` チェックを入れた。
  >
  > `run-test.ps1` 側の `git fetch` だけは warning 止まりにしてある。イメージが両リビジョンを
  > 持っているのでオフライン実行も有効であり、かつレポートが引用するのは解決済みの SHA なので、
  > 古い ref が要求どおりを騙ることはできない。

  イメージ内の検証結果:

  | 項目 | 値 |
  |---|---|
  | JDK | `openjdk 21.0.11 2026-04-21 LTS` |
  | Maven | `Apache Maven 3.9.9` |
  | Git | `git version 2.55.0.windows.4` |
  | `PATH` | `C:\tools\maven\bin;C:\tools\git\cmd;C:\openjdk-21\bin;...`（java も維持されている） |
  | `TEMP` | `C:\t` |
  | リポジトリ | `148d8eb` で detached。`origin/master` と `origin/feature/issues-1025-remote-lr` の両方を保持 |
  | `C:\m2` | 0.34 GB（`test-compile` が BUILD SUCCESS） |
  | `C:\src\lrp\target` | 無し（意図どおり削除済み） |

  ウォームアップの Maven ログに
  `[WARNING] Failed to build parent project for org.6wind.jenkins:lockable-resources` が出るが、
  直後に通常どおりビルドが進んで BUILD SUCCESS する。incrementals 由来の
  `maven-hpi-plugin` を解決する過程で一度出る表示で、実害はない。

  > [!NOTE]
  > `C:\m2` が 0.34 GB とやや小さいので、`test-compile` までで足りない依存があれば
  > D6（ボリューム無し）のせいで毎回ダウンロードが走ることを懸念していたが、
  > S6 のスモーク実行での Maven ダウンロードは **0 件**だった。ウォームアップは足りている。
- [x] S5. `scripts/run-test.ps1` を書く（§6）
- [x] S6. スモーク実行（P2）で配管を通す — **完了**

  ```
  .\run-test.ps1 -Rev 148d8eb -Test LockableResourceTest
  → PASS  Tests run: 12, Failures: 0, Errors: 0, Skipped: 0   （全体 1m27s / mvn 1m08s）
  → dev/reports/20260819144659-windows-unittest{.md,/}
  ```

  コンテナ内の実行環境（`env.txt` より）:
  `Microsoft Windows Server 2022 Datacenter build 10.0.20348.0` /
  cpu 6 / memory 8703 MB / `TEMP=C:\t` / `platform encoding: UTF-8` / `Default locale: en_US`
  — `--memory 8g` と `--cpus 6` がコンテナに届いていることが確認できる。

  スモークで潰した harness のバグ 2 件:

  1. **コンテナ側が環境情報の収集で死んでいた。** `java -version` は stderr に出力するため、
     `(& java -version 2>&1)` が `$ErrorActionPreference='Stop'` 下で ErrorRecord に変換されて
     throw する。mvn の周りだけガードしていて見落としていた。`Get-ToolVersion` に切り出した。
  2. **ログが ErrorRecord の装飾で汚れていた。** ネイティブコマンドの stderr を `2>&1` すると
     1 行ごとに `... + CategoryInfo ... NativeCommandError` が付く。
     `2>&1 | ForEach-Object { "$_" }` で素のテキストに戻す。
     併せて `Out-File -Encoding utf8` が PS 5.1 では BOM を付ける件も、
     コミット対象のファイルなので BOM 無しで書くよう統一した。

  1 回目の失敗は収穫でもあった: コンテナが早期に死んでも `docker cp` は成功し、
  「surefire レポートが無い＝テスト以前に失敗」と明示したレポートが出た。異常系の配管は通っている。
- [x] S7. 対照実行（P3, `148d8eb`）— **完了 / PASS**

  ```
  .\run-test.ps1 -Rev 148d8eb
  → PASS  Tests run: 5, Failures: 0, Errors: 0, Skipped: 0  （テスト 54.85s / 全体 2m9s）
  → dev/reports/20260819155805-windows-unittest{.md,/}
  ```

  | testcase | time |
  |---|---|
  | `lockOrderRestart` | 24.59s |
  | `interoperabilityOnRestart` | 4.631s |
  | `checkQueueAfterRestart` | 13.349s |
  | **`testReserveOverRestart`** | **5.531s** |
  | `chaosOnRestart` | 6.718s |

  **本命の `testReserveOverRestart` を含め全て green。** ci.jenkins.io の証跡
  （master は windows-21 で success）と一致しており、§8 の判定表でいう
  「対照 pass」の行に乗った。これで S8 の結果が fail ならブランチ起因と言い切れる。

  Maven のダウンロードはここでも 0 件。再起動を伴うテストでもウォームアップで足りている。
- [x] S8. 本命実行（P4, `bdca858`）— **完了 / PASS（＝再現せず）**

  ```
  .\run-test.ps1 -Rev bdca858
  → PASS  Tests run: 5, Failures: 0, Errors: 0, Skipped: 0  （テスト 60.49s / 全体 2m15s）
  → dev/reports/20260819160127-windows-unittest{.md,/}
  rev.head : bdca858ec712ad7304252bce1dc2a64c6adb2cd5 [B7] Annotate the remote resources endpoint with GET
  ```

  | testcase | 対照 `148d8eb` | ブランチ `bdca858` |
  |---|---|---|
  | `lockOrderRestart` | 24.59s | 28.171s |
  | `interoperabilityOnRestart` | 4.631s | 5.312s |
  | `checkQueueAfterRestart` | 13.349s | 13.511s |
  | **`testReserveOverRestart`** | **5.531s** | **4.893s** |
  | `chaosOnRestart` | 6.718s | 8.592s |

  §8 の判定表では「pass / pass = 再現せず」の行。環境は組み上がったが、
  **CI で落ちる条件をまだ再現できていない**。所要時間にも異常の兆候は無い。

  ### なぜ再現しなかったか（Q2 の検討材料）

  CI との差で効きそうなものを、効きそうな順に:

  1. **1 クラスを単独実行している。** CI は `forkCount: '1C'` で**全スイート**を回すので、
     エージェント上では 10 前後の fork が同時に走り CPU と I/O を奪い合う。
     ログ出力を待って進む再起動テストは、負荷でタイムアウト側に倒れる典型。
     ここが一番大きい差だと見ている
  2. **CI は `mvn verify`（buildPlugin）**、こちらは `mvn test`
  3. **エージェントのスペック**が不明。こちらは 6 CPU / 8.5 GB を与えている。
     コア数が少ないほど競合は厳しくなる
  4. **Windows のビルド**。こちらは Server 2022 (20348)。ci.jenkins.io 側は未確認

  > [!NOTE]
  > 現状の `run-test.ps1` は常に `-Dtest=<pattern>` を渡すため、**全スイートを回す手段が無い**。
  > 上の 1 を試すには、パターン省略（全実行）を受け付けるようにする必要がある。
- [ ] S9. 結果をレポート化（P5）— 失敗本文と session の別を明記
- [ ] S10. `dev/docs-j/WINDOWS_TEST_ENVIRONMENT.md`（日本語）を書いてコミット
- [ ] S11. `dev/docs-e/WINDOWS_TEST_ENVIRONMENT.md`（英語版）を対で用意し、
        ルート `README.md` のドキュメント索引に 1 行追加する
