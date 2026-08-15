#!/usr/bin/env bash
# ローカル開発用: lockable-resources-plugin を 4 コンテナで起動する
# 使い方: ./start.sh [--clean] [--in-place-build]
#   --clean          : Jenkins home ボリュームを削除してから起動（初期化）
#   --in-place-build : PLUGIN_DIR 直下で hpi をビルドする（既定は隔離 worktree）
#   --debug          : 未コミットの作業ツリーをそのままビルドする（in-place）。再現不能な実行
#
# **未コミットの変更があるとエラーで停止する。** テストは常にコミット済みコードで走らせ、
# レポートに書かれた SHA がその実行を再現できる状態を指すようにするため（2026-08-08）。
# デプロイしたコミットは .deployed-plugin に記録し、run-e2e.sh / run-load.sh が
# レポートに転記する（解析時点の HEAD を読むと、走行中にコミットしただけでズレる）。
#
# 既定では PLUGIN_DIR のコミット済み HEAD を隔離 worktree（/tmp 配下）でビルドする。
# VS Code の Java 拡張 (jdt.ls) がリポジトリ直下の target/ に ECJ コンパイル結果を
# 書き込むため、リポジトリ直下で mvn package すると Extension index 欠落の壊れた
# hpi が生成され、Jenkins が「起動待ち」のままハングする（2026-06-11 に実害確認）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# PLUGIN_DIR 環境変数が指定されている場合はそちらを優先する。
# 相対パスで渡された場合は start.sh からの相対として解決する。
# 未指定時は start.sh と同じディレクトリに lockable-resources-plugin が
# clone されていると仮定する。
if [[ -n "${PLUGIN_DIR:-}" ]]; then
  # 相対パスを絶対パスに正規化（start.sh の位置を基準）
  PLUGIN_DIR="$(cd "$SCRIPT_DIR" && cd "$PLUGIN_DIR" && pwd)"
else
  PLUGIN_DIR="$SCRIPT_DIR/lockable-resources-plugin"
fi

CLEAN=false
IN_PLACE_BUILD=false
DEBUG_MODE=false
# LRR_COVERAGE lets run-e2e.sh / run-load.sh turn this on: they call start.sh themselves, so a
# flag passed to them has to reach here somehow.
COVERAGE="${LRR_COVERAGE:-false}"
for arg in "$@"; do
  [[ "$arg" == "--clean" ]] && CLEAN=true
  [[ "$arg" == "--in-place-build" ]] && IN_PLACE_BUILD=true
  [[ "$arg" == "--debug" ]] && { DEBUG_MODE=true; IN_PLACE_BUILD=true; }
  [[ "$arg" == "--coverage" ]] && COVERAGE=true
done

# --coverage attaches the JaCoCo agent baked into the image. Off by default: instrumentation costs
# time on every instrumented method, which is exactly what the load test is measuring.
#
# includes= is not an optimisation. Without it the agent instruments all of Jenkins core, the exec
# file grows by orders of magnitude, and the report drowns the plugin in classes nobody asked about.
#
# append=true because a controller may restart mid-run (E2E does this on purpose); output=file means
# the agent writes at JVM exit, so coverage/collect.sh has to stop the containers before reading.
if $COVERAGE; then
  export LRR_COVERAGE=true
  source "$SCRIPT_DIR/lib/coverage-env.sh"
  echo "[INFO] Coverage: JaCoCo agent attached (destfile=/var/jenkins_home/jacoco.exec)"
fi

JENKINS_HOME_DIRS=(jha jhb jhc jhd)
LEGACY_JENKINS_HOME_DIRS=(jh8081 jh8082 jh8083)

# ---------------------------------------------------------------------------
# 1. Maven を特定
# ---------------------------------------------------------------------------
if [[ -x "$HOME/.local/apache-maven-3.9.9/bin/mvn" ]]; then
  MVN="$HOME/.local/apache-maven-3.9.9/bin/mvn"
else
  MVN="mvn"
fi

echo "[INFO] Plugin dir: $PLUGIN_DIR"
echo "[INFO] Maven     : $MVN"

# ---------------------------------------------------------------------------
# 2. プラグインをビルド（既定: 隔離 worktree / --in-place-build で従来動作）
# ---------------------------------------------------------------------------
BUILD_DIR="$PLUGIN_DIR"
WORKTREE_DIR=""

cleanup_worktree() {
  [[ -z "$WORKTREE_DIR" ]] && return 0
  git -C "$PLUGIN_DIR" worktree remove --force "$WORKTREE_DIR" >/dev/null 2>&1 || true
  rm -rf "$(dirname "$WORKTREE_DIR")"
}

# 再現性のため、ビルド対象はコミット済みでなければならない。
if ! git -C "$PLUGIN_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  echo "[ERROR] $PLUGIN_DIR is not a git repository."
  echo "        The test harness records the deployed commit in every report, so it needs one."
  exit 1
fi
PLUGIN_DIRTY="$(git -C "$PLUGIN_DIR" status --porcelain)"
if [[ -n "$PLUGIN_DIRTY" ]] && ! $DEBUG_MODE; then
  echo "[ERROR] Plugin repo has uncommitted changes:"
  git -C "$PLUGIN_DIR" status --short | sed 's/^/          /'
  echo ""
  echo "        Tests always run against committed code, so the SHA written into the report"
  echo "        identifies exactly what was measured. Commit or stash first, then re-run,"
  echo "        or pass --debug to build the working tree as-is (report is not reproducible)."
  exit 1
fi
PLUGIN_SHA="$(git -C "$PLUGIN_DIR" rev-parse --short HEAD)"
PLUGIN_SUBJECT="$(git -C "$PLUGIN_DIR" log -1 --format='%s')"
if [[ -n "$PLUGIN_DIRTY" ]]; then PLUGIN_STATE="dirty"; else PLUGIN_STATE="clean"; fi
HEAD_DESC="$PLUGIN_SHA $PLUGIN_SUBJECT"

if ! $IN_PLACE_BUILD; then
  WORKTREE_DIR="$(mktemp -d -t lrr-env-build-XXXXXX)/plugin"
  git -C "$PLUGIN_DIR" worktree add --detach "$WORKTREE_DIR" HEAD >/dev/null
  trap cleanup_worktree EXIT
  BUILD_DIR="$WORKTREE_DIR"
  echo "[INFO] Build mode: isolated worktree (HEAD: ${HEAD_DESC})"
else
  echo "[INFO] Build mode: in-place ($PLUGIN_DIR)"
  echo "[WARN] Make sure the VS Code Java extension (jdt.ls) is not running on this repo."
fi

echo ""
echo "[INFO] Building lockable-resources plugin (mvn package -DskipTests) ..."
(cd "$BUILD_DIR" && "$MVN" package -DskipTests -q)

# ---------------------------------------------------------------------------
# 3. ビルド成果物を Docker ビルドコンテキストへコピー
# ---------------------------------------------------------------------------
HPI_SRC="$(ls "$BUILD_DIR/target/lockable-resources"*.hpi 2>/dev/null | head -1 || true)"
if [[ -z "$HPI_SRC" ]]; then
  echo "[ERROR] HPI not found in $BUILD_DIR/target/. Build may have failed."
  exit 1
fi

# hpi 健全性チェック: 内部 jar に Extension index (META-INF/annotations/hudson.Extension)
# が無い hpi は @Extension が一切登録されず、Jenkins が起動待ちのままハングする。
if command -v python3 >/dev/null 2>&1; then
  if ! python3 - "$HPI_SRC" <<'PYEOF'
import io, sys, zipfile
hpi = zipfile.ZipFile(sys.argv[1])
inner = zipfile.ZipFile(io.BytesIO(hpi.read("WEB-INF/lib/lockable-resources.jar")))
sys.exit(0 if any(n.endswith("META-INF/annotations/hudson.Extension.txt") for n in inner.namelist()) else 1)
PYEOF
  then
    echo "[ERROR] Built hpi is missing the Extension annotation index (broken build)."
    echo "        Cause is usually an IDE (VS Code jdt.ls) writing into the plugin's target/."
    echo "        Re-run without --in-place-build, or stop the IDE and rebuild."
    exit 1
  fi
  echo "[INFO] HPI sanity check passed (Extension index present)"
else
  echo "[WARN] python3 not found; skipping hpi Extension index check"
fi

cp "$HPI_SRC" "$SCRIPT_DIR/docker/lockable-resources.hpi"
echo "[INFO] Copied: $HPI_SRC -> docker/lockable-resources.hpi"

# The Dockerfile always COPYs the JaCoCo agent, so it has to exist even for a run that will not use
# it. Resolved from the local repository rather than committed: it is a build artifact like the hpi,
# and this keeps its version tied to whatever the plugin build already pulled down.
JACOCO_VERSION="${JACOCO_VERSION:-0.8.15}"
if [[ ! -f "$SCRIPT_DIR/docker/jacocoagent.jar" ]]; then
  echo "[INFO] Fetching JaCoCo agent $JACOCO_VERSION ..."
  "$MVN" -q org.apache.maven.plugins:maven-dependency-plugin:3.8.1:copy \
    -Dartifact="org.jacoco:org.jacoco.agent:$JACOCO_VERSION:jar:runtime" \
    -DoutputDirectory="$SCRIPT_DIR/docker" -Dmdep.stripVersion=false >/dev/null
  mv "$SCRIPT_DIR/docker/org.jacoco.agent-$JACOCO_VERSION-runtime.jar" \
     "$SCRIPT_DIR/docker/jacocoagent.jar"
  echo "[INFO] Copied: JaCoCo agent -> docker/jacocoagent.jar"
fi

# ---------------------------------------------------------------------------
# 4. ボリューム削除（--clean 指定時のみ）
# ---------------------------------------------------------------------------
cd "$SCRIPT_DIR"
if $CLEAN; then
  echo ""
  echo "[INFO] --clean: stopping containers and removing Jenkins home directories ..."
  docker compose down --remove-orphans 2>/dev/null || true
  for jh in "${JENKINS_HOME_DIRS[@]}"; do
    if [[ -d "$SCRIPT_DIR/$jh" ]]; then
      rm -rf "$SCRIPT_DIR/$jh"
      echo "[INFO] Removed $SCRIPT_DIR/$jh"
    fi
  done
  # 旧命名からの移行後片付け（存在する場合のみ削除）
  for jh in "${LEGACY_JENKINS_HOME_DIRS[@]}"; do
    if [[ -d "$SCRIPT_DIR/$jh" ]]; then
      rm -rf "$SCRIPT_DIR/$jh"
      echo "[INFO] Removed legacy $SCRIPT_DIR/$jh"
    fi
  done
fi

# ---------------------------------------------------------------------------
# 5. Jenkins home ディレクトリを用意
# ---------------------------------------------------------------------------
for jh in "${JENKINS_HOME_DIRS[@]}"; do
  if [[ ! -d "$SCRIPT_DIR/$jh" ]]; then
    mkdir -p "$SCRIPT_DIR/$jh"
    echo "[INFO] Created $SCRIPT_DIR/$jh"
  fi
done

# root 所有のまま残ると Jenkins コンテナが起動ループするため、Docker 経由で権限を補正する。
echo "[INFO] Ensuring Jenkins home directory ownership (uid/gid 1000) ..."
for jh in "${JENKINS_HOME_DIRS[@]}"; do
  docker run --rm -v "$SCRIPT_DIR/$jh:/target" alpine:3.20 sh -c 'chown -R 1000:1000 /target' >/dev/null
done

# ---------------------------------------------------------------------------
# 6. Docker イメージをビルド
# ---------------------------------------------------------------------------
echo ""
echo "[INFO] Building Docker images ..."
docker compose build

# ---------------------------------------------------------------------------
# 6. コンテナを起動
# ---------------------------------------------------------------------------
echo ""
echo "[INFO] Starting containers ..."
docker compose up -d

# デプロイしたコミットを記録する。run-e2e.sh / run-load.sh はこれを読んでレポートに書く。
printf '%s\t%s\t%s\n' "$PLUGIN_SHA" "$PLUGIN_SUBJECT" "$PLUGIN_STATE" > "$SCRIPT_DIR/.deployed-plugin"
echo "[INFO] Deployed plugin: $HEAD_DESC"


# ---------------------------------------------------------------------------
# 8. 起動確認（ポートごとにポーリング）
# ---------------------------------------------------------------------------
echo ""
echo "[INFO] Waiting for Jenkins instances to become ready ..."
for node in a b c d; do
  case "$node" in
    a) port=8081 ;;
    b) port=8082 ;;
    c) port=8083 ;;
    d) port=8084 ;;
  esac

  ready=false
  for i in $(seq 1 120); do
    if curl -fsS "http://127.0.0.1:${port}/jenkins/login" >/dev/null 2>&1; then
      echo "[OK]   Jenkins ${node} (port ${port}) is up (${i}s)"
      ready=true
      break
    fi
    sleep 2
  done
  if ! $ready; then
    echo "[WARN] Jenkins ${node} (port ${port}) did not become ready within 240s"
    echo "       Check logs: docker compose logs jenkins-${node}"
  fi
done

echo ""
echo "----------------------------------------------------------------------"
echo " Jenkins 4-controller dev environment"
echo "----------------------------------------------------------------------"
echo "  http://localhost:8081/jenkins/  (admin / admin)"
echo "  http://localhost:8082/jenkins/  (admin / admin)"
echo "  http://localhost:8083/jenkins/  (admin / admin)"
echo "  http://localhost:8084/jenkins/  (admin / admin)"
echo ""
echo " Logs  : docker compose logs -f"
echo " Stop  : ./stop.sh"
echo " Clean : ./start.sh --clean   (removes jha-jhd directories)"
echo "----------------------------------------------------------------------"
