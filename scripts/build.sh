#!/bin/zsh
# Builds unbox.app and unbox-cli into ./build without Xcode (Command Line Tools are enough).
# Usage: scripts/build.sh [--install]
# Image assets in Support/ are generated from docs/*.svg by scripts/make-icons.swift.
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD="$ROOT/build"
APP="$BUILD/unbox.app"
CONTENTS="$APP/Contents"
TARGET="arm64-apple-macos13.0"
SWIFTC=(swiftc -O -target "$TARGET" -swift-version 5)
SPARKLE="$("$ROOT/scripts/sparkle.sh")"

rm -rf "$BUILD"
mkdir -p "$BUILD/module" "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"

"${SWIFTC[@]}" -parse-as-library -module-name UnboxKit \
  -emit-library -static -emit-module -emit-module-path "$BUILD/module/UnboxKit.swiftmodule" \
  -o "$BUILD/libUnboxKit.a" "$ROOT"/Sources/UnboxKit/*.swift

"${SWIFTC[@]}" -module-name unbox_cli -I "$BUILD/module" -L "$BUILD" -lUnboxKit -lsqlite3 \
  -o "$BUILD/unbox-cli" "$ROOT"/Sources/unbox-cli/main.swift

"${SWIFTC[@]}" -parse-as-library -module-name Unbox -I "$BUILD/module" -L "$BUILD" -lUnboxKit -lsqlite3 \
  -F "$SPARKLE" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$CONTENTS/MacOS/unbox" "$ROOT"/Sources/Unbox/*.swift

cp "$ROOT/Support/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Support/AppIcon.icns" "$ROOT/Support/MenuBarIcon.pdf" "$ROOT/Support/Logo.pdf" "$CONTENTS/Resources/"
cp -R "$ROOT/Resources/Localizations" "$CONTENTS/Resources/Localizations"
cp "$ROOT/LICENSE" "$CONTENTS/Resources/LICENSE"
cp "$SPARKLE/LICENSE" "$CONTENTS/Resources/Sparkle-LICENSE"
# Sparkle keeps its upstream signatures, including those of its nested helpers.
ditto "$SPARKLE/Sparkle.framework" "$CONTENTS/Frameworks/Sparkle.framework"

codesign --force --sign - "$BUILD/unbox-cli"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"

echo "Zbudowano: $APP"

if [[ "${1:-}" == "--install" ]]; then
  DEST="/Applications/unbox.app"
  pkill -x unbox 2>/dev/null || true
  for _ in {1..50}; do pgrep -x unbox >/dev/null || break; sleep 0.1; done
  rm -rf "$DEST"
  ditto "$APP" "$DEST"
  open "$DEST"
  echo "Zainstalowano i uruchomiono: $DEST"
fi
