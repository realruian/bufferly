#!/usr/bin/env bash
# 构建 PastePop，覆盖安装到 /Applications，验签后启动。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="PastePop.app"
BUILD_APP="$ROOT_DIR/.build/$APP_NAME"
INSTALL_DIR="${PASTEPOP_INSTALL_DIR:-/Applications}"
INSTALL_APP="$INSTALL_DIR/$APP_NAME"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

case "$INSTALL_APP" in
  */PastePop.app) ;;
  *)
    echo "Refusing to install to unexpected path: $INSTALL_APP" >&2
    exit 1
    ;;
esac

bash "$ROOT_DIR/scripts/build-app.sh"

if pgrep -x PastePop >/dev/null 2>&1; then
  echo "Quitting running PastePop..."
  osascript -e 'tell application "PastePop" to quit' >/dev/null 2>&1 || true

  for _ in {1..20}; do
    if ! pgrep -x PastePop >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
fi

if pgrep -x PastePop >/dev/null 2>&1; then
  echo "PastePop is still running. Quit it and rerun this script." >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_APP"
ditto "$BUILD_APP" "$INSTALL_APP"
codesign --verify --deep --strict "$INSTALL_APP"

echo "Registering PastePop with Launch Services..."
"$LSREGISTER" -f "$INSTALL_APP"

echo "Importing PastePop into Spotlight..."
mdimport "$INSTALL_APP"

open "$INSTALL_APP"
echo "Installed and launched $INSTALL_APP"
