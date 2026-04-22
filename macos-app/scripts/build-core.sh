#!/usr/bin/env bash
# Freezes the upstream Python listener (main.py + mitm.py + friends) plus the
# macos-app bootstrap into a single self-contained binary via PyInstaller.
#
# Produces: macos-app/bundle/shade-core   (universal arm64 + x86_64 via lipo)
#
# Requirements:
#   - python3 (>= 3.10) on PATH for the host arch.
#   - For a universal build: a second python3 matching the OTHER arch. If
#     only one is available the script falls back to a single-arch binary.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT/.." && pwd)"
BUILD_DIR="$ROOT/.core-build"
BUNDLE_DIR="$ROOT/bundle"
OUT="$BUNDLE_DIR/shade-core"

mkdir -p "$BUNDLE_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ── Locate interpreters ─────────────────────────────────────────────────────
HOST_ARCH="$(uname -m)"
if [[ "$HOST_ARCH" == "arm64" ]]; then
  OTHER_ARCH="x86_64"
else
  OTHER_ARCH="arm64"
fi

HOST_PYTHON="${HOST_PYTHON:-$(command -v python3 || true)}"
if [[ -z "$HOST_PYTHON" ]]; then
  echo "error: python3 not found on PATH" >&2
  exit 1
fi

OTHER_PYTHON="${OTHER_PYTHON:-}"
# Try to guess an opposite-arch python3 if not set.
if [[ -z "$OTHER_PYTHON" ]]; then
  # On arm64 macs, Rosetta python from x86_64 homebrew is a common choice.
  for cand in \
    "/usr/local/bin/python3" \
    "/opt/homebrew/bin/python3" \
    "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3" \
    "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3"; do
    if [[ -x "$cand" ]]; then
      arch_of="$(/usr/bin/file -b "$cand" | grep -o 'arm64\|x86_64' | head -1 || true)"
      if [[ "$arch_of" == "$OTHER_ARCH" ]]; then
        OTHER_PYTHON="$cand"
        break
      fi
    fi
  done
fi

build_for_arch () {
  local arch="$1"
  local py="$2"
  local work="$BUILD_DIR/$arch"
  rm -rf "$work"
  mkdir -p "$work"

  echo "→ [$arch] creating venv using $py"
  arch -"$arch" "$py" -m venv "$work/venv"
  local vpy="$work/venv/bin/python"

  echo "→ [$arch] installing deps"
  arch -"$arch" "$vpy" -m pip install --quiet --upgrade pip wheel
  # Upstream runtime deps + PyInstaller.
  arch -"$arch" "$vpy" -m pip install --quiet \
    "cryptography>=41" "h2>=4.1" "pyinstaller>=6.0"

  echo "→ [$arch] running PyInstaller"
  # --onefile for a single binary. --collect-all cryptography pulls in the
  # runtime wheels pyinstaller sometimes misses on universal builds.
  arch -"$arch" "$vpy" -m PyInstaller \
    --noconfirm \
    --clean \
    --onefile \
    --name "shade-core-$arch" \
    --distpath "$work/dist" \
    --workpath "$work/work" \
    --specpath "$work" \
    --paths "$REPO_ROOT" \
    --hidden-import "mitm" \
    --hidden-import "proxy_server" \
    --hidden-import "domain_fronter" \
    --hidden-import "h2_transport" \
    --hidden-import "cert_installer" \
    --hidden-import "ws" \
    --collect-submodules "cryptography" \
    --collect-submodules "h2" \
    --target-arch "$arch" \
    "$ROOT/core/shade_core.py"

  echo "$work/dist/shade-core-$arch"
}

if [[ -n "$OTHER_PYTHON" ]]; then
  echo "Building universal shade-core:"
  echo "  $HOST_ARCH → $HOST_PYTHON"
  echo "  $OTHER_ARCH → $OTHER_PYTHON"
  HOST_BIN="$(build_for_arch "$HOST_ARCH" "$HOST_PYTHON" | tail -1)"
  OTHER_BIN="$(build_for_arch "$OTHER_ARCH" "$OTHER_PYTHON" | tail -1)"
  echo "→ lipo → $OUT"
  lipo -create "$HOST_BIN" "$OTHER_BIN" -output "$OUT"
else
  echo "⚠︎  No $OTHER_ARCH python3 found — building single-arch ($HOST_ARCH) only."
  echo "    Set OTHER_PYTHON=/path/to/$OTHER_ARCH/python3 to build universal."
  HOST_BIN="$(build_for_arch "$HOST_ARCH" "$HOST_PYTHON" | tail -1)"
  cp "$HOST_BIN" "$OUT"
fi

chmod +x "$OUT"
echo "✔ $OUT"
/usr/bin/file "$OUT"
