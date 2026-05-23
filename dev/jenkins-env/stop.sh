#!/usr/bin/env bash
# コンテナを停止する（Jenkins home ボリュームは保持）
# ボリュームも削除したい場合は --clean フラグを使う
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CLEAN=false
for arg in "$@"; do
  [[ "$arg" == "--clean" ]] && CLEAN=true
done

JENKINS_HOME_DIRS=(jha jhb jhc jhd)
LEGACY_JENKINS_HOME_DIRS=(jh8081 jh8082 jh8083)

if $CLEAN; then
  echo "[INFO] Stopping containers and removing Jenkins home directories ..."
  docker compose down --remove-orphans
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
  echo "[INFO] Jenkins home directories removed."
else
  echo "[INFO] Stopping containers (Jenkins home volumes preserved) ..."
  docker compose down --remove-orphans
  echo "[INFO] Containers stopped."
  echo "[INFO] To also delete volumes: ./stop.sh --clean"
fi
