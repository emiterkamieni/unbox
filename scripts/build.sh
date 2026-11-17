#!/bin/zsh
# Builds Debox.app and debox-cli into ./build without Xcode (Command Line Tools are enough).
# Usage: scripts/build.sh [--install]
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD="$ROOT/build"
APP="$BUILD/Debox.app"
TARGET="arm64-apple-macos13.0"
SWIFTC=(swiftc -O -target "$TARGET" -swift-version 5)

rm -rf "$BUILD"
mkdir -p "$BUILD/module"

"${SWIFTC[@]}" -parse-as-library -module-name DeboxKit \
  -emit-library -static -emit-module -emit-module-path "$BUILD/module/DeboxKit.swiftmodule" \
  -o "$BUILD/libDeboxKit.a" "$ROOT"/Sources/DeboxKit/*.swift

"${SWIFTC[@]}" -module-name debox_cli -I "$BUILD/module" -L "$BUILD" -lDeboxKit -lsqlite3 \
  -o "$BUILD/debox-cli" "$ROOT"/Sources/debox-cli/main.swift

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
"${SWIFTC[@]}" -parse-as-library -module-name Debox -I "$BUILD/module" -L "$BUILD" -lDeboxKit -lsqlite3 \
  -o "$APP/Contents/MacOS/Debox" "$ROOT"/Sources/Debox/*.swift

cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$BUILD/debox-cli"
codesign --force --sign - "$APP"

echo "Zbudowano: $APP"

if [[ "${1:-}" == "--install" ]]; then
  DEST="/Applications/Debox.app"
  pkill -x Debox 2>/dev/null || true
  for _ in {1..50}; do pgrep -x Debox >/dev/null || break; sleep 0.1; done
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  open "$DEST"
  echo "Zainstalowano i uruchomiono: $DEST"
fi
