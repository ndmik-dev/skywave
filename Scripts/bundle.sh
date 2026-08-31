#!/bin/sh
# Assembles build/Skywave.app from the SwiftPM executable. Xcode is not involved:
# the bundle is just a directory with an Info.plist and the resource bundle.
set -eu
cd "$(dirname "$0")/.."

swift build -c release --product Skywave

APP="build/Skywave.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Skywave "$APP/Contents/MacOS/Skywave"
cp Bundling/Info.plist "$APP/Contents/Info.plist"
# Bundle.module resolves against Contents/Resources at runtime.
cp -R .build/release/Skywave_SkywaveKit.bundle "$APP/Contents/Resources/"

# Ad-hoc signature. A real certificate is only needed to hand the app to someone
# else, or to enable ShazamKit later.
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "warning: ad-hoc signing failed"

echo "built $APP"
