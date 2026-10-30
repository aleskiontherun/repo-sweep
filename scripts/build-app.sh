#!/usr/bin/env bash
# Builds a release RepoSweep.app into ./build. Pass --install to also copy it
# into /Applications.
set -euo pipefail

cd "$(dirname "$0")/.."
name=RepoSweep
app="build/$name.app"
version=$(git describe --tags --always 2>/dev/null || echo 0.1.0)

swift build -c release --arch arm64 --arch x86_64
bin=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/$name" "$app/Contents/MacOS/$name"
# Compiles the Icon Composer icon: Assets.car holds the Liquid Glass icon
# macOS 26 renders, AppIcon.icns a flattened fallback for older systems.
xcrun actool Resources/AppIcon.icon --compile "$app/Contents/Resources" \
    --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon \
    --output-partial-info-plist "build/icon-partial.plist" >/dev/null

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$name</string>
    <key>CFBundleDisplayName</key><string>$name</string>
    <key>CFBundleIdentifier</key><string>me.vesnin.reposweep</string>
    <key>CFBundleExecutable</key><string>$name</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>${version#v}</string>
    <key>CFBundleVersion</key><string>${version#v}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough to run locally. Not notarized.
codesign --force --sign - "$app"
echo "Built $app"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/$name.app"
    cp -R "$app" /Applications/
    echo "Installed /Applications/$name.app"
fi
