#!/usr/bin/env bash
# ローカル開発用: lockable-resources-plugin を 4 コンテナで起動する
# 使い方: ./start.sh [--clean] [--in-place-build]
#   --clean          : Jenkins home ボリュームを削除してから起動（初期化）
#   --in-place-build : PLUGIN_DIR 直下で hpi をビルドする（既定は隔離 worktree）
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
for arg in "$@"; do
  [[ "$arg" == "--clean" ]] && CLEAN=true
  [[ "$arg" == "--in-place-build" ]] && IN_PLACE_BUILD=true
done

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

if ! $IN_PLACE_BUILD; then
  HEAD_DESC="$(git -C "$PLUGIN_DIR" log -1 --format='%h %s')"
  if [[ -n "$(git -C "$PLUGIN_DIR" status --porcelain)" ]]; then
    echo "[WARN] Plugin repo has uncommitted changes. Worktree build uses committed HEAD only."
    echo "       Use --in-place-build to build the working tree as-is (stop the VS Code Java extension first)."
  fi
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
