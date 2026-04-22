#!/usr/bin/env bash
# End-to-end release build for Shade.app.
#
# Orchestrates:
#   1. Freeze the Python listener into shade-core (PyInstaller, universal).
#   2. Download tun2socks (universal).
#   3. Build Shade.app (SwiftPM, universal) + embed binaries.
#   4. Package Shade-<version>.dmg.
#
# Usage:
#   VERSION=1.0.0 ./scripts/build-release.sh
#
# Env overrides:
#   SKIP_CORE=1          — reuse existing bundle/shade-core.
#   SKIP_TUN2SOCKS=1     — reuse existing bundle/tun2socks.
#   OTHER_PYTHON=/path   — opposite-arch python3 for a universal shade-core.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/macos-app"
VERSION="${VERSION:-0.1.0-alfa}"

echo "Repo:           $ROOT"
echo "Release version: $VERSION"
echo

if [[ "${SKIP_CORE:-0}" != "1" ]]; then
  echo "=== 1) Freeze shade-core ==="
  "$APP_DIR/scripts/build-core.sh"
else
  echo "=== 1) shade-core: skipped (SKIP_CORE=1) ==="
fi

if [[ "${SKIP_TUN2SOCKS:-0}" != "1" ]]; then
  echo "=== 2) Fetch tun2socks ==="
  "$APP_DIR/scripts/fetch-tun2socks.sh"
else
  echo "=== 2) tun2socks: skipped (SKIP_TUN2SOCKS=1) ==="
fi

echo "=== 3) Build Shade.app ==="
VERSION="$VERSION" "$APP_DIR/scripts/build-app.sh"

echo "=== 4) Package DMG ==="
VERSION="$VERSION" "$APP_DIR/scripts/make-dmg.sh"

echo
echo "✔ Release artifacts under $APP_DIR/dist/:"
echo "   - Shade.app"
echo "   - Shade-$VERSION.dmg"
