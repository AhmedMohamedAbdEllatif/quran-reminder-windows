#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/Quran Reminder.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
for ARCH in arm64 x86_64; do
  xcrun swiftc -parse-as-library -swift-version 5 -O -sdk "$SDK" -target "$ARCH-apple-macos13.0" macos/Main.swift macos/Memorization.swift -o "build/QuranReminder-$ARCH"
done
lipo -create build/QuranReminder-arm64 build/QuranReminder-x86_64 -output "$APP/Contents/MacOS/QuranReminder"
cp macos/Info.plist "$APP/Contents/Info.plist"
cp verses.json mushaf-lines.json background.png "$APP/Contents/Resources/"
cp tanzil-uthmani-1.1.txt THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
codesign --force --deep --sign - "$APP"
"$APP/Contents/MacOS/QuranReminder" --check
ditto -c -k --sequesterRsrc --keepParent "$APP" build/QuranReminder-macOS.zip
