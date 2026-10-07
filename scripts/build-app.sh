#!/usr/bin/env bash
# CharTodo.app 번들 생성: swift build → .app 구성 → 아이콘 → ad-hoc 서명
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/CharTodo.app"

echo "▶ swift build ($CONFIG)"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/CharTodo"

echo "▶ 번들 구성"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CharTodo"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [ ! -f build/AppIcon.icns ]; then
  echo "▶ 아이콘 생성"
  rm -rf build/AppIcon.iconset
  swift scripts/make-icon.swift build/AppIcon.iconset >/dev/null
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "▶ 서명 (ad-hoc)"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "✅ $APP"
echo "   실행: open $APP"
echo "   설치: cp -R $APP /Applications/"
