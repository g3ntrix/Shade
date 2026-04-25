#!/usr/bin/env python3
"""
Bootstrap wrapper for Shade.app.

This file is what PyInstaller freezes into `shade-core`. It re-points the
MITM CA directory (hardcoded to the script's own folder in the upstream
project) to a writable location under ~/Library/Application Support/Shade,
then hands off to `main.main()`.

Importantly, the patching must happen BEFORE `main` is imported, because
`main.py` does `from mitm import CA_CERT_FILE` which captures the constant
at import time into `main`'s namespace.
"""

import os
import sys


def _resource_dir() -> str:
    """
    Directory bundled resources live in at runtime.

    - Frozen (PyInstaller onefile): sys._MEIPASS is a temp extraction dir.
    - Frozen (one-dir): sys._MEIPASS == dir(sys.executable).
    - Interpreted: directory of this file.
    """
    meipass = getattr(sys, "_MEIPASS", None)
    if meipass:
        return meipass
    return os.path.dirname(os.path.abspath(__file__))


def _writable_app_dir() -> str:
    home = os.path.expanduser("~")
    path = os.path.join(home, "Library", "Application Support", "Shade")
    os.makedirs(path, exist_ok=True)
    return path


def _bootstrap_ssl_ca_bundle() -> None:
    """Point Python's default SSL context at certifi's CA bundle.

    On a frozen macOS app, OpenSSL's compiled-in default CA paths point
    at the build host's homebrew/system locations and aren't present on
    the user's machine, so every outbound TLS handshake fails with
    "unable to get local issuer certificate". Setting SSL_CERT_FILE /
    SSL_CERT_DIR before any ssl module use makes ssl.create_default_context()
    pick up certifi's bundle globally — covers paths we patched explicitly
    and any we haven't.
    """
    try:
        import certifi
    except Exception as exc:
        print(f"[bootstrap] certifi import failed: {exc!r}", flush=True)
        return
    cafile = certifi.where()
    if not cafile or not os.path.exists(cafile):
        print(f"[bootstrap] certifi cafile missing: {cafile!r}", flush=True)
        return
    os.environ.setdefault("SSL_CERT_FILE", cafile)
    os.environ.setdefault("SSL_CERT_DIR", os.path.dirname(cafile))
    os.environ.setdefault("REQUESTS_CA_BUNDLE", cafile)
    print(f"[bootstrap] SSL CA bundle: {cafile}", flush=True)


def _patch_ca_paths() -> None:
    """Redirect mitm.CA_DIR (and friends) into our writable app-support dir."""
    app_dir = _writable_app_dir()
    ca_dir = os.path.join(app_dir, "ca")
    print(f"[bootstrap] ensuring ca_dir exists: {ca_dir}", flush=True)
    os.makedirs(ca_dir, exist_ok=True)

    # Ensure modules can be located (PyInstaller wires this up, but be defensive
    # when running as plain Python for dev).
    res = _resource_dir()
    if res not in sys.path:
        sys.path.insert(0, res)

    print("[bootstrap] importing mitm module...", flush=True)
    import mitm
    print("[bootstrap] mitm imported, applying constants...", flush=True)
    mitm.CA_DIR = ca_dir
    mitm.CA_KEY_FILE = os.path.join(ca_dir, "ca.key")
    mitm.CA_CERT_FILE = os.path.join(ca_dir, "ca.crt")
    print("[bootstrap] ca paths patched", flush=True)


def main() -> None:
    # Print immediately to indicate the binary has started.
    # We use flush=True to ensure it bypasses any buffering.
    print("[bootstrap] shade-core starting...", flush=True)

    try:
        app_dir = _writable_app_dir()
        os.chdir(app_dir)
        print(f"[bootstrap] CWD set to: {app_dir}", flush=True)

        _bootstrap_ssl_ca_bundle()
        _patch_ca_paths()

        # Late import: after patching mitm, `main.py` will pull in the patched
        # constants via `from mitm import CA_CERT_FILE`.
        print("[bootstrap] loading main module", flush=True)
        from main import main as run
        run()
    except Exception as e:
        print(f"[bootstrap] critical crash: {e}", flush=True)
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
