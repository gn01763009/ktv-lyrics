#!/bin/bash
# Builds build/KTV Lyrics.app: the release binary, the now-playing helper, and an ad-hoc signature.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

APP="build/KTV Lyrics.app"
CONTENTS="$APP/Contents"
RESOURCES="$CONTENTS/Resources"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

scripts/build-adapter.sh

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$RESOURCES"
cp "$BIN_DIR/KTVLyrics" "$CONTENTS/MacOS/KTVLyrics"
cp Resources/Info.plist "$CONTENTS/Info.plist"
cp Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl "$RESOURCES/mediaremote-adapter.pl"
cp -R build/adapter/MediaRemoteAdapter.framework "$RESOURCES/MediaRemoteAdapter.framework"
cp THIRD_PARTY_NOTICES.md "$RESOURCES/THIRD_PARTY_NOTICES.md"

codesign --force --deep --sign - "$APP"
echo "Built $APP"
