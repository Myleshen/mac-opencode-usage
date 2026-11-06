#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="build/OpenCodeUsage.app"
# Local builds take the version from the last tag, so a release never has to
# commit anything back to main; the release workflow passes its own VERSION.
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0}"
BUILD="${BUILD:-1}"
# ARCHS="arm64 x86_64" produces a universal binary; default is this machine.
ARCHS="${ARCHS:-$(uname -m)}"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# No Xcode project, no packages: one swiftc call per arch, then lipo.
SLICES=()
for arch in $ARCHS; do
  swiftc -O -parse-as-library \
    -target "$arch-apple-macos14.0" \
    Sources/*.swift \
    -o "build/OpenCodeUsage-$arch"
  SLICES+=("build/OpenCodeUsage-$arch")
done
lipo -create "${SLICES[@]}" -output "$APP/Contents/MacOS/OpenCodeUsage"

cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.myleshen.opencode-usage</string>
  <key>CFBundleName</key><string>OpenCodeUsage</string>
  <key>CFBundleExecutable</key><string>OpenCodeUsage</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" 2>/dev/null
echo "Built $APP $VERSION"
echo "Run: open $PWD/$APP"
