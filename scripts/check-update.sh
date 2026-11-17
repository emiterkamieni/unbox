#!/bin/zsh
# Checks that an older unbox updates itself to the latest published release (see check-update.swift).
# Run after scripts/build.sh and after publishing a release.
set -euo pipefail

ROOT="${0:A:h:h}"
SPARKLE="$("$ROOT/scripts/sparkle.sh")"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/unbox-update-check.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

ditto "$ROOT/build/unbox.app" "$WORK/unbox.app"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.9.0" -c "Set :CFBundleVersion 0" "$WORK/unbox.app/Contents/Info.plist"
codesign --force --sign - "$WORK/unbox.app" 2>/dev/null

# A stable path, so an outgoing firewall (LuLu, Little Snitch) only has to allow it once.
CHECKER="$ROOT/.build/check-update"
if [[ ! -x "$CHECKER" || "$ROOT/scripts/check-update.swift" -nt "$CHECKER" ]]; then
  swiftc -O -F "$SPARKLE" -framework Sparkle -Xlinker -rpath -Xlinker "$SPARKLE" \
    -o "$CHECKER" "$ROOT/scripts/check-update.swift"
fi
"$CHECKER" "$WORK/unbox.app" || true

# Sparkle's installer replaces the bundle after this process has exited.
for _ in {1..60}; do
  version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$WORK/unbox.app/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$version" != "0.9.0" && -n "$version" ]] && break
  sleep 1
done
latest="$(gh release view --repo emiterkamieni/unbox --json tagName --jq .tagName)"
if [[ "v$version" == "$latest" ]] && codesign --verify --deep --strict "$WORK/unbox.app"; then
  echo "OK: 0.9.0 was updated to $version"
else
  echo "FAIL: expected ${latest#v}, found ${version:-nothing}"
  exit 1
fi
