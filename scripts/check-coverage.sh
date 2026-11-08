#!/bin/bash
# Runs the test suite with coverage and fails when KTVCore line coverage is below the threshold.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

THRESHOLD=80
TARGET="Sources/KTVCore"

swift test --enable-code-coverage

BIN_DIR="$(swift build --show-bin-path)"
TEST_BINARY="$BIN_DIR/KTVLyricsPackageTests.xctest/Contents/MacOS/KTVLyricsPackageTests"
PROFDATA="$BIN_DIR/codecov/default.profdata"

REPORT="$(xcrun llvm-cov report "$TEST_BINARY" -instr-profile "$PROFDATA" "$TARGET")"
echo "$REPORT"

# The TOTAL row's tenth column is the line coverage, for example "96.21%".
LINE_COVER="$(awk '$1 == "TOTAL" { gsub("%", "", $10); print $10 }' <<< "$REPORT")"
if [[ -z "$LINE_COVER" ]]; then
  echo "error: could not read the KTVCore line coverage from the report" >&2
  exit 1
fi

if awk -v cover="$LINE_COVER" -v min="$THRESHOLD" 'BEGIN { exit !(cover + 0 >= min) }'; then
  echo "KTVCore line coverage ${LINE_COVER}% meets the ${THRESHOLD}% threshold."
else
  echo "error: KTVCore line coverage ${LINE_COVER}% is below the ${THRESHOLD}% threshold." >&2
  exit 1
fi
