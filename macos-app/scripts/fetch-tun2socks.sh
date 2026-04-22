#!/usr/bin/env bash
# Downloads prebuilt tun2socks (xjasonlyu/tun2socks) binaries for darwin-arm64
# and darwin-amd64 and lipos them into a single universal binary.
#
# Output: macos-app/bundle/tun2socks
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_DIR="$ROOT/bundle"
CACHE_DIR="$ROOT/.tun2socks-cache"
OUT="$BUNDLE_DIR/tun2socks"

VERSION="${TUN2SOCKS_VERSION:-v2.5.2}"
BASE="https://github.com/xjasonlyu/tun2socks/releases/download/$VERSION"

mkdir -p "$BUNDLE_DIR" "$CACHE_DIR"

download () {
  local asset="$1"
  local dest="$CACHE_DIR/$asset"
  if [[ ! -f "$dest" ]]; then
    echo "→ downloading $asset"
    curl -fsSL --retry 5 --http1.1 -o "$dest" "$BASE/$asset"
  fi
  echo "$dest"
}

ARM_ZIP="$(download "tun2socks-darwin-arm64.zip")"
X86_ZIP="$(download "tun2socks-darwin-amd64.zip")"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/tun2socks.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

unzip -q -o "$ARM_ZIP" -d "$WORK/arm64"
unzip -q -o "$X86_ZIP" -d "$WORK/amd64"

ARM_BIN="$(find "$WORK/arm64" -type f -perm -u+x | head -1)"
X86_BIN="$(find "$WORK/amd64" -type f -perm -u+x | head -1)"
if [[ -z "$ARM_BIN" || -z "$X86_BIN" ]]; then
  echo "error: couldn't locate extracted tun2socks binaries" >&2
  exit 1
fi

lipo -create "$ARM_BIN" "$X86_BIN" -output "$OUT"
chmod +x "$OUT"
echo "✔ $OUT"
/usr/bin/file "$OUT"
