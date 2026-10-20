#!/bin/sh
set -e
cd "$(dirname "$0")/.."
swift build -c release
APP=.build/Monitor.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Monitor "$APP/Contents/MacOS/Monitor"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
mkdir -p "$HOME/Applications"
pkill -x Monitor 2>/dev/null || true
rm -rf "$HOME/Applications/Monitor.app"
cp -R "$APP" "$HOME/Applications/Monitor.app"
echo "Instalado em $HOME/Applications/Monitor.app"
