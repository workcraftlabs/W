#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release "$@"
APP="$PWD/dist/W.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release "$@" --show-bin-path)/W" "$APP/Contents/MacOS/W"
cp -R "$(swift build -c release "$@" --show-bin-path)/W_W.bundle" "$APP/Contents/Resources/"
cp scripts/Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign "${W_SIGNING_IDENTITY:--}" "$APP"
echo "Built $APP"
