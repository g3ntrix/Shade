#!/usr/bin/env bash
# Freezes the upstream Python listener (main.py + mitm.py + friends) plus the
# macos-app bootstrap into self-contained binaries via PyInstaller.
#
# Produces:
#   macos-app/bundle/shade-core-arm64    (Apple Silicon)
#   macos-app/bundle/shade-core-x86_64   (Intel)
#
# IMPORTANT: We intentionally do NOT `lipo -create` these two binaries.
# PyInstaller's `--onefile` mode appends a CArchive payload after the
# Mach-O sections; lipo-ing two onefile executables produces a binary
# that looks universal to `file`, but the bootloader in whichever slice
# runs will extract the WRONG payload (causing errors like "Python
# shared library ... mach-o file, but is an incompatible architecture").
# Shipping both binaries separately and letting the Swift launcher pick
# the right one at runtime is the reliable pattern.
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
OUT_ARM64="$BUNDLE_DIR/shade-core-arm64"
OUT_X86_64="$BUNDLE_DIR/shade-core-x86_64"
REQUIRE_UNIVERSAL="${REQUIRE_UNIVERSAL:-0}"

mkdir -p "$BUNDLE_DIR"
# Clear any stale outputs (including pre-lipo legacy "shade-core").
rm -f "$OUT_ARM64" "$OUT_X86_64" "$BUNDLE_DIR/shade-core"
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

  # ── Install deps ──────────────────────────────────────────────────────────
  local vendor_dir="$ROOT/vendor"
  mkdir -p "$vendor_dir"

  install_deps () {
    local pkgs=("$@")
    if run_for_arch "$arch" "$vpy" -m pip install --quiet \
         --no-index --find-links="$vendor_dir" \
         "${pkgs[@]}" 2>/dev/null; then
      echo "  [offline] installed ${pkgs[*]} from $vendor_dir"
      return 0
    fi
    echo "  [online]  vendor cache miss — fetching ${pkgs[*]} from PyPI"
    run_for_arch "$arch" "$vpy" -m pip install --quiet "${pkgs[@]}"
    run_for_arch "$arch" "$vpy" -m pip download --quiet \
      --dest "$vendor_dir" --only-binary=:all: \
      "${pkgs[@]}" 2>/dev/null || true
  }

  echo "→ [$arch] installing pip & wheel"
  install_deps pip wheel

  echo "→ [$arch] installing core deps + PyInstaller"
  install_deps "cryptography>=41" "h2>=4.1" "certifi>=2024.2.2" "pyinstaller>=6.0"

  echo "→ [$arch] running PyInstaller"
  run_for_arch "$arch" "$vpy" -m PyInstaller \
    --noconfirm \
    --clean \
    --onefile \
    --noupx \
    --name "shade-core-$arch" \
    --distpath "$work/dist" \
    --workpath "$work/work" \
    --specpath "$work" \
    --paths "$REPO_ROOT" \
    --paths "$REPO_ROOT/src" \
    --hidden-import "mitm" \
    --hidden-import "proxy_server" \
    --hidden-import "domain_fronter" \
    --hidden-import "h2_transport" \
    --hidden-import "cert_installer" \
    --hidden-import "lan_utils" \
    --hidden-import "logging_utils" \
    --hidden-import "constants" \
    --hidden-import "codec" \
    --collect-submodules "cryptography" \
    --collect-submodules "h2" \
    --collect-data "certifi" \
    --hidden-import "certifi" \
    --target-arch "$arch" \
    "$ROOT/core/shade_core.py"

  local bin_path="$work/dist/shade-core-$arch"
  if [[ ! -f "$bin_path" ]]; then
    echo "error: PyInstaller failed to produce $bin_path" >&2
    exit 1
  fi
  # Export for the caller
  GLOBAL_BIN_PATH="$bin_path"
}

place_output () {
  local arch="$1"
  local src="$2"
  local dst
  case "$arch" in
    arm64)  dst="$OUT_ARM64" ;;
    x86_64) dst="$OUT_X86_64" ;;
    *) echo "error: unknown arch $arch" >&2; exit 1 ;;
  esac
  cp "$src" "$dst"
  chmod +x "$dst"
  echo "✔ $dst"
  /usr/bin/file "$dst"
}

if [[ -n "$OTHER_PYTHON" ]]; then
  echo "Building shade-core for both architectures:"
  echo "  $HOST_ARCH  → $HOST_PYTHON"
  echo "  $OTHER_ARCH → $OTHER_PYTHON"
  
  echo "--- Building $HOST_ARCH ---"
  GLOBAL_BIN_PATH=""
  build_for_arch "$HOST_ARCH" "$HOST_PYTHON"
  place_output "$HOST_ARCH" "$GLOBAL_BIN_PATH"
  
  echo "--- Building $OTHER_ARCH ---"
  GLOBAL_BIN_PATH=""
  build_for_arch "$OTHER_ARCH" "$OTHER_PYTHON"
  place_output "$OTHER_ARCH" "$GLOBAL_BIN_PATH"
else
  if [[ "$REQUIRE_UNIVERSAL" == "1" ]]; then
    echo "error: universal shade-core required, but no runnable $OTHER_ARCH python was found." >&2
    exit 1
  fi
  echo "⚠︎  No $OTHER_ARCH python3 found — building single-arch ($HOST_ARCH) only."
  GLOBAL_BIN_PATH=""
  build_for_arch "$HOST_ARCH" "$HOST_PYTHON"
  place_output "$HOST_ARCH" "$GLOBAL_BIN_PATH"
fi
