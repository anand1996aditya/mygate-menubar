#!/bin/bash
set -e
cd "$(dirname "$0")"
BUNDLE="Build/MyGate MenuBar.app"
swift build -c release
BIN=$(swift build -c release --show-bin-path)/MyGateMenuBar
rm -rf "Build"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN" "$BUNDLE/Contents/MacOS/MyGateMenuBar"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"; fi
if [ -f Resources/MenuIcon.png ]; then cp Resources/MenuIcon.png "$BUNDLE/Contents/Resources/MenuIcon.png"; fi
if [ -f Resources/BrandLogo.png ]; then cp Resources/BrandLogo.png "$BUNDLE/Contents/Resources/BrandLogo.png"; fi
cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.secureu.mygate</string>
  <key>CFBundleName</key><string>MyGate MenuBar</string>
  <key>CFBundleDisplayName</key><string>MyGate MenuBar</string>
  <key>CFBundleExecutable</key><string>MyGateMenuBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.2.7</string>
  <key>CFBundleVersion</key><string>10</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMultipleInstancesProhibited</key><true/>
</dict>
</plist>
PLIST
codesign --force --identifier com.secureu.mygate --sign - "$BUNDLE" 2>/dev/null || true
touch "Build/.metadata_never_index"
echo "Built: $BUNDLE"
