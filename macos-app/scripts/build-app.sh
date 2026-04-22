#!/usr/bin/env bash
# Builds the SwiftPM app, assembles a universal .app bundle, embeds
# shade-core (bundled Python listener) and tun2socks.
#
# Output: macos-app/dist/Shade.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Shade"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

# 1. Make sure core is present (build if needed).
if [[ ! -x "$ROOT/bundle/shade-core" ]]; then
  echo "→ shade-core missing; building"
  "$ROOT/scripts/build-core.sh"
fi

# 2. Regenerate the icon if the source changed (or it's missing).
if [[ -f "$ROOT/logo/Shade.png" && ( ! -f "$ROOT/Sources/Shade/Resources/Shade.icns" || "$ROOT/logo/Shade.png" -nt "$ROOT/Sources/Shade/Resources/Shade.icns" ) ]]; then
  "$ROOT/scripts/make-icns.sh"
fi

# 3. Build Swift binary universal (arm64 + x86_64).
echo "→ swift build (arm64)"
swift build --package-path "$ROOT" -c release \
  --triple arm64-apple-macosx13.0 \
  --disable-sandbox
ARM_BIN="$(find "$ROOT/.build" -path '*arm64*release*' -name "$APP_NAME" -type f -not -path '*dSYM*' | head -1)"

echo "→ swift build (x86_64)"
swift build --package-path "$ROOT" -c release \
  --triple x86_64-apple-macosx13.0 \
  --disable-sandbox
X86_BIN="$(find "$ROOT/.build" -path '*x86_64*release*' -name "$APP_NAME" -type f -not -path '*dSYM*' | head -1)"

if [[ -z "$ARM_BIN" || -z "$X86_BIN" ]]; then
  echo "error: couldn't locate swift build outputs" >&2
  exit 1
fi
echo "  arm64: $ARM_BIN"
echo "  x86_64: $X86_BIN"

# 4. Assemble the .app
echo "→ assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

lipo -create "$ARM_BIN" "$X86_BIN" -output "$APP/Contents/MacOS/$APP_NAME"
chmod +x "$APP/Contents/MacOS/$APP_NAME"

cp "$ROOT/bundle/shade-core" "$APP/Contents/Resources/shade-core"
chmod +x "$APP/Contents/Resources/shade-core"

# Copy SwiftPM-generated resource bundle (contains Shade.png/icns).
ARM_RELEASE_DIR="$(dirname "$ARM_BIN")"
for b in "$ARM_RELEASE_DIR"/*.bundle; do
  [[ -e "$b" ]] || continue
  cp -R "$b" "$APP/Contents/Resources/"
done

# Also copy logo flat so CloakBrandImage's primary path resolves.
if [[ -f "$ROOT/Sources/Shade/Resources/Shade.png" ]]; then
  cp "$ROOT/Sources/Shade/Resources/Shade.png" "$APP/Contents/Resources/Shade.png"
fi
if [[ -f "$ROOT/Sources/Shade/Resources/Shade.icns" ]]; then
  cp "$ROOT/Sources/Shade/Resources/Shade.icns" "$APP/Contents/Resources/Shade.icns"
fi

# 5. Info.plist
VERSION="${VERSION:-1.0.0}"
ICON_ENTRY=""
if [[ -f "$APP/Contents/Resources/Shade.icns" ]]; then
  ICON_ENTRY="<key>CFBundleIconFile</key><string>Shade</string>"
fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>app.shade.mac</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Shade</string>
    <key>CFBundleDisplayName</key><string>Shade</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key><string>Shade — MasterHttpRelayVPN client</string>
    $ICON_ENTRY
</dict>
</plist>
PLIST

# 6. Ad-hoc codesign with hardened runtime + entitlements.
#
# On Apple Silicon (M1/M2/M3), PyInstaller's onefile loader extracts and jumps
# into dynamically-mapped code, which the hardened runtime blocks unless the
# `allow-unsigned-executable-memory` / `allow-jit` entitlements are present.
# Without them users see "The application can't be opened." even though the
# binary is universal and runs fine on Intel. Sign nested binaries FIRST, then
# the outer bundle, so every Mach-O gets the same entitlements (--deep is
# deprecated and often leaves nested frameworks with mismatched flags).
ENTITLEMENTS="$ROOT/scripts/entitlements.plist"
echo "→ ad-hoc codesigning (hardened runtime, with entitlements)"
codesign --force --sign - \
  --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --timestamp=none \
  "$APP/Contents/Resources/shade-core"
codesign --force --sign - \
  --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --timestamp=none \
  "$APP/Contents/MacOS/$APP_NAME"
codesign --force --sign - \
  --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --timestamp=none \
  "$APP"

# Strip quarantine attr from the freshly-built bundle so local runs don't
# hit Gatekeeper. (Downloaded DMGs still need `xattr -cr` on the user end —
# see README for the one-liner.)
xattr -cr "$APP" 2>/dev/null || true

# Verify the signature covers every nested binary.
codesign --verify --deep --strict --verbose=2 "$APP" || {
  echo "error: codesign verification failed — app will not launch on M-series Macs" >&2
  exit 1
}

echo
echo "✔ built: $APP"
echo "  run with: open '$APP'"
