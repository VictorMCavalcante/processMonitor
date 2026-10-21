#!/bin/sh
set -e
cd "$(dirname "$0")/.."
swift build -c release
APP=.build/Vernio.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Monitor "$APP/Contents/MacOS/Monitor"
cp Resources/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
mkdir -p "$HOME/Applications"
pkill -x Monitor 2>/dev/null && while pgrep -x Monitor >/dev/null; do sleep 0.2; done || true
rm -rf "$HOME/Applications/Monitor.app" "$HOME/Applications/Vernio.app"
cp -R "$APP" "$HOME/Applications/Vernio.app"
echo "Instalado em $HOME/Applications/Vernio.app"
open "$HOME/Applications/Vernio.app"
