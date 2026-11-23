#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild -project Redcast.xcodeproj -scheme Redcast -configuration Debug \
    -destination 'platform=macOS,arch=x86_64' \
    -derivedDataPath build/Intel ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO build

app="build/Intel/Build/Products/Debug/Redcast Dev.app"
for binary in \
    "$app/Contents/MacOS/Redcast Dev" \
    "$app/Contents/MacOS/Redcast Dev.debug.dylib" \
    "$app/Contents/Helpers/ClipboardTextHelper" \
    "$app/Contents/Helpers/FileIndexHelper" \
    "$app/Contents/Helpers/Redcast Dev Dictation.app/Contents/MacOS/Redcast Dev Dictation"; do
    /usr/bin/lipo "$binary" -verify_arch x86_64
done
printf '\nIntel development build: %s/%s\n' "$PWD" "$app"
