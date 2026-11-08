#!/bin/bash
# Builds the vendored mediaremote-adapter into build/adapter/MediaRemoteAdapter.framework.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

VENDOR="Vendor/mediaremote-adapter"
OUT="build/adapter/MediaRemoteAdapter.framework"

# The same sources the upstream CMakeLists.txt lists for the library.
SOURCES=(
  "$VENDOR/src/adapter/env.m"
  "$VENDOR/src/adapter/get.m"
  "$VENDOR/src/adapter/globals.m"
  "$VENDOR/src/adapter/keys.m"
  "$VENDOR/src/adapter/now_playing.m"
  "$VENDOR/src/adapter/repeat.m"
  "$VENDOR/src/adapter/seek.m"
  "$VENDOR/src/adapter/send.m"
  "$VENDOR/src/adapter/shuffle.m"
  "$VENDOR/src/adapter/speed.m"
  "$VENDOR/src/adapter/stream.m"
  "$VENDOR/src/adapter/test.m"
  "$VENDOR/src/private/MediaRemote.m"
  "$VENDOR/src/utility/Debounce.m"
  "$VENDOR/src/utility/helpers.m"
)

rm -rf "$OUT"
mkdir -p "$OUT"

clang -dynamiclib -fobjc-arc -fvisibility=default \
  -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 \
  -I"$VENDOR/include" -I"$VENDOR/src" \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  "${SOURCES[@]}" \
  -install_name @rpath/MediaRemoteAdapter \
  -o "$OUT/MediaRemoteAdapter"

codesign --force --sign - "$OUT"
echo "Built $OUT"
