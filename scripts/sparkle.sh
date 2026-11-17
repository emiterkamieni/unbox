#!/bin/zsh
# Downloads the pinned Sparkle release into .build/sparkle and prints its directory.
# Sparkle handles downloading, verifying (EdDSA) and installing app updates.
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="2.10.1"
DIGEST="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
CACHE="$ROOT/.build/sparkle"
ARCHIVE="$CACHE/Sparkle-$VERSION.tar.xz"
DIST="$CACHE/$VERSION"

mkdir -p "$CACHE"
if [[ ! -f "$ARCHIVE" ]]; then
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz" -o "$ARCHIVE.download"
  mv "$ARCHIVE.download" "$ARCHIVE"
fi
if [[ "$(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)" != "$DIGEST" ]]; then
  rm -f "$ARCHIVE"
  echo "Sparkle archive checksum mismatch" >&2
  exit 1
fi
if [[ ! -d "$DIST/Sparkle.framework" ]]; then
  mkdir -p "$DIST"
  tar -xf "$ARCHIVE" -C "$DIST"
fi
echo "$DIST"
