#!/bin/bash
# SMBToggle.app（メニューバー）と smbctl（CLI）をビルドし、
# アプリを ~/Applications に入れる。
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build

swiftc -O -o build/smbctl SMBCore.swift cli/main.swift

APP=build/SMBToggle.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp app/Info.plist "$APP/Contents/"
swiftc -O -o "$APP/Contents/MacOS/SMBToggle" SMBCore.swift app/main.swift
codesign --force --sign - "$APP"

mkdir -p ~/Applications
pkill -x SMBToggle 2>/dev/null && sleep 1 || true
rm -rf ~/Applications/SMBToggle.app
cp -R "$APP" ~/Applications/
ln -sf "$PWD/build/smbctl" /opt/homebrew/bin/smbctl
echo "built: ~/Applications/SMBToggle.app, /opt/homebrew/bin/smbctl"
