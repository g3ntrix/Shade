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
REQUIRE_UNIVERSAL="${REQUIRE_UNIVERSAL:-0}"

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

supports_arch () {
  local bin="$1"
  local arch="$2"
  /usr/bin/lipo -archs "$bin" 2>/dev/null | tr ' ' '\n' | grep -qx "$arch"
}

run_for_arch () {
  local arch="$1"
  shift
  if [[ "$arch" == "$HOST_ARCH" ]]; then
    "$@"
  else
    arch -"$arch" "$@"
  fi
}

OTHER_PYTHON="${OTHER_PYTHON:-}"
# Try to guess an opposite-arch python3 if not set.
if [[ -z "$OTHER_PYTHON" ]]; then
  if supports_arch "$HOST_PYTHON" "$OTHER_ARCH"; then
    OTHER_PYTHON="$HOST_PYTHON"
  fi

  # On arm64 macs, Rosetta python from x86_64 homebrew is a common choice.
  for cand in \
    "/usr/local/bin/python3" \
    "/opt/homebrew/bin/python3" \
    "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3" \
    "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3"; do
    [[ -n "$OTHER_PYTHON" ]] && break
    if [[ -x "$cand" ]]; then
      if supports_arch "$cand" "$OTHER_ARCH"; then
        OTHER_PYTHON="$cand"
        break
      fi
    fi
  done
fi

if [[ -n "$OTHER_PYTHON" ]] && ! supports_arch "$OTHER_PYTHON" "$OTHER_ARCH"; then
  echo "⚠︎  OTHER_PYTHON does not include $OTHER_ARCH: $OTHER_PYTHON"
  OTHER_PYTHON=""
fi

if [[ -n "$OTHER_PYTHON" ]] && [[ "$OTHER_ARCH" != "$HOST_ARCH" ]] && ! arch -"$OTHER_ARCH" /usr/bin/true >/dev/null 2>&1; then
  echo "⚠︎  Host cannot execute $OTHER_ARCH binaries; skipping universal build on this machine."
  OTHER_PYTHON=""
fi

build_for_arch () {
  local arch="$1"
  local py="$2"
  local work="$BUILD_DIR/$arch"
  rm -rf "$work"
  mkdir -p "$work"

  echo "→ [$arch] creating venv using $py"
  run_for_arch "$arch" "$py" -m venv "$work/venv"
  local vpy="$work/venv/bin/python"

  echo "→ [$arch] installing deps"
  run_for_arch "$arch" "$vpy" -m pip install --quiet --upgrade pip wheel
  # Upstream runtime deps + PyInstaller.
  run_for_arch "$arch" "$vpy" -m pip install --quiet \
    "cryptography>=41" "h2>=4.1" "pyinstaller>=6.0"

  echo "→ [$arch] running PyInstaller"
  # --onefile for a single binary. --collect-all cryptography pulls in the
  # runtime wheels pyinstaller sometimes misses on universal builds.
  run_for_arch "$arch" "$vpy" -m PyInstaller \
    --noconfirm \
    --clean \
    --onefile \
    --name "shade-core-$arch" \
    --distpath "$work/dist" \
    --workpath "$work/work" \
    --specpath "$work" \
    --paths "$REPO_ROOT" \
    --paths "$REPO_ROOT/src" \
    --hidden-import "src.mitm" \
    --hidden-import "src.proxy_server" \
    --hidden-import "src.domain_fronter" \
    --hidden-import "src.h2_transport" \
    --hidden-import "src.cert_installer" \
    --hidden-import "src.lan_utils" \
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
  if [[ "$REQUIRE_UNIVERSAL" == "1" ]]; then
    echo "error: universal shade-core required, but no runnable $OTHER_ARCH python was found." >&2
    echo "       Provide OTHER_PYTHON=/path/to/$OTHER_ARCH/python3 or build on Apple Silicon with Rosetta." >&2
    exit 1
  fi
  echo "⚠︎  No $OTHER_ARCH python3 found — building single-arch ($HOST_ARCH) only."
  echo "    Set OTHER_PYTHON=/path/to/$OTHER_ARCH/python3 to build universal."
  HOST_BIN="$(build_for_arch "$HOST_ARCH" "$HOST_PYTHON" | tail -1)"
  cp "$HOST_BIN" "$OUT"
fi

chmod +x "$OUT"
echo "✔ $OUT"
/usr/bin/file "$OUT"
