#!/bin/bash
# Builds Markdown Preview (app + Quick Look extension) with only the Xcode
# Command Line Tools; Xcode itself isn't required.
#
#   ./build.sh               build build/MarkdownPreview.app
#   ./build.sh install       build, install to ~/Applications and register
#   ./build.sh uninstall     remove the installed app
#   ./build.sh test          render Tests/*.md and compare with the expected HTML
#   ./build.sh test --update rewrite the expected HTML
#   ./build.sh render FILE   print the rendered HTML for FILE
#   ./build.sh icon          regenerate Resources/AppIcon.icns
set -euo pipefail
cd "$(dirname "$0")"

VERSION=1.0.0
BUILD_NUMBER=1
BUNDLE_ID="${BUNDLE_ID:-io.github.randhindi.MarkdownPreview}"
MIN_MACOS=12.0

OUT=build
APP=$OUT/MarkdownPreview.app
EXT=$APP/Contents/PlugIns/MarkdownPreviewExtension.appex
DEST="$HOME/Applications/MarkdownPreview.app"
KATEX=Resources/katex/katex.min.js
mkdir -p "$OUT"

# Pick the newest SDK the installed compiler can actually use (Command Line
# Tools sometimes ship a default SDK newer than their Swift compiler).
find_sdk() {
  [[ -n "${SDKROOT:-}" ]] && return
  local dev; dev=$(xcode-select -p)
  for sdk in $(ls -d "$dev"/SDKs/MacOSX[0-9]*.sdk "$dev"/Platforms/MacOSX.platform/Developer/SDKs/MacOSX[0-9]*.sdk 2>/dev/null |
               awk -F/ '{print $NF" "$0}' | sort -Vr | cut -d" " -f2); do
    if echo 'import Foundation' | swiftc -sdk "$sdk" -module-cache-path "$OUT/cache" -typecheck - >/dev/null 2>&1; then
      SDKROOT=$sdk; return
    fi
  done
  echo "No usable macOS SDK found. Install the Command Line Tools: xcode-select --install" >&2
  exit 1
}

swift_flags() { echo -O -swift-version 5 -sdk "$SDKROOT" -module-cache-path "$OUT/cache"; }

build_render_tool() {
  find_sdk
  swiftc $(swift_flags) Sources/Shared/*.swift Tools/render/main.swift -o "$OUT/render" >&2
}

build_app() {
  find_sdk
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$EXT/Contents/MacOS"

  for arch in arm64 x86_64; do
    swiftc $(swift_flags) -target "$arch-apple-macos$MIN_MACOS" -module-name MarkdownPreviewExtension \
      -application-extension -Xlinker -e -Xlinker _NSExtensionMain -framework QuickLookUI \
      Sources/Extension/*.swift Sources/Shared/*.swift -o "$OUT/ext-$arch"
    swiftc $(swift_flags) -target "$arch-apple-macos$MIN_MACOS" -module-name MarkdownPreview \
      Sources/App/*.swift Sources/Shared/*.swift -o "$OUT/app-$arch"
  done
  lipo -create "$OUT"/ext-arm64 "$OUT"/ext-x86_64 -output "$EXT/Contents/MacOS/MarkdownPreviewExtension"
  lipo -create "$OUT"/app-arm64 "$OUT"/app-x86_64 -output "$APP/Contents/MacOS/MarkdownPreview"
  rm -f "$OUT"/ext-* "$OUT"/app-*

  cp Resources/App-Info.plist "$APP/Contents/Info.plist"
  cp Resources/Extension-Info.plist "$EXT/Contents/Info.plist"
  cp "$KATEX" Resources/AppIcon.icns "$APP/Contents/Resources/" # KaTeX is shared with the extension

  local pb=/usr/libexec/PlistBuddy
  for plist in "$APP/Contents/Info.plist" "$EXT/Contents/Info.plist"; do
    $pb -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD_NUMBER" \
        -c "Set :LSMinimumSystemVersion $MIN_MACOS" "$plist"
  done
  $pb -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
  $pb -c "Set :CFBundleIdentifier $BUNDLE_ID.QuickLook" "$EXT/Contents/Info.plist"

  # Ad-hoc signing is enough to run locally. Sign the extension first, then the app.
  codesign --force --sign - --options runtime --entitlements Resources/Extension.entitlements "$EXT"
  codesign --force --sign - --options runtime "$APP"
  echo "Built $APP $VERSION ($(du -sh "$APP" | cut -f1))"
}

install_app() {
  build_app
  mkdir -p "$HOME/Applications"
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R "$DEST"
  pluginkit -a "$DEST/Contents/PlugIns/MarkdownPreviewExtension.appex"
  pluginkit -e use -i "$BUNDLE_ID.QuickLook"
  qlmanage -r >/dev/null 2>&1 || true
  qlmanage -r cache >/dev/null 2>&1 || true
  echo "Installed to $DEST"
}

uninstall_app() {
  pkill -f "$DEST/Contents/MacOS/MarkdownPreview" 2>/dev/null || true
  [[ -d "$DEST" ]] && /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$DEST" || true
  rm -rf "$DEST"
  qlmanage -r >/dev/null 2>&1 || true
  echo "Removed $DEST"
}

run_tests() {
  build_render_tool
  local failed=0
  for md in Tests/*.md; do
    local expected="${md%.md}.expected.html" actual="$OUT/${md##*/}.html"
    KATEX=$KATEX "$OUT/render" "$md" > "$actual"
    if [[ "${1:-}" == "--update" ]]; then
      cp "$actual" "$expected"; echo "updated $expected"
    elif diff -u "$expected" "$actual" > "$OUT/test.diff"; then
      echo "ok   $md"
    else
      echo "FAIL $md"; cat "$OUT/test.diff"; failed=1
    fi
  done
  return $failed
}

case "${1:-build}" in
  build)     build_app ;;
  install)   install_app ;;
  uninstall) uninstall_app ;;
  test)      run_tests "${2:-}" ;;
  render)    build_render_tool; KATEX=$KATEX exec "$OUT/render" "${2:?usage: ./build.sh render FILE}" ;;
  icon)      find_sdk; swiftc $(swift_flags) Tools/make-icon.swift -o "$OUT/make-icon" && "$OUT/make-icon" Resources/AppIcon.icns ;;
  *)         sed -n '2,12p' "$0"; exit 2 ;;
esac
