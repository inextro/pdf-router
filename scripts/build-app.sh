#!/usr/bin/env bash
# PDFRouter.app 번들을 build/에 만든다.
#   --install  ~/Applications 에 설치하고 PDF 기본 앱으로 지정한다.
#   --zip      배포용 build/PDFRouter-<버전>.zip 을 만든다.
#   되돌리기: swift scripts/set-default.swift /System/Applications/Preview.app
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/PDFRouter.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -target arm64-apple-macos14.0 -o "$APP/Contents/MacOS/PDFRouter" Sources/main.swift
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "built: $APP"

for arg in "$@"; do
  case "$arg" in
    --install)
      mkdir -p "$HOME/Applications"
      rm -rf "$HOME/Applications/PDFRouter.app"
      cp -R "$APP" "$HOME/Applications/"
      "$LSREGISTER" -f "$HOME/Applications/PDFRouter.app"
      # build/ 사본이 등록돼 있으면 기본 앱이 그쪽을 가리킬 수 있으니 등록을 지운다.
      "$LSREGISTER" -u "$APP" 2>/dev/null || true
      echo "installed: $HOME/Applications/PDFRouter.app"
      echo "PDF 기본 앱: $(swift scripts/set-default.swift "$HOME/Applications/PDFRouter.app" | tail -1)"
      ;;
    --zip)
      VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
      ZIP="build/PDFRouter-$VERSION.zip"
      rm -f "$ZIP"
      ditto -c -k --keepParent "$APP" "$ZIP"
      echo "zipped: $ZIP"
      ;;
  esac
done
