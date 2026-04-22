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


def _patch_ca_paths() -> None:
    """Redirect mitm.CA_DIR (and friends) into our writable app-support dir."""
    app_dir = _writable_app_dir()
    ca_dir = os.path.join(app_dir, "ca")
    os.makedirs(ca_dir, exist_ok=True)

    # Ensure modules can be located (PyInstaller wires this up, but be defensive
    # when running as plain Python for dev).
    res = _resource_dir()
    if res not in sys.path:
        sys.path.insert(0, res)

    # We must patch AFTER ensuring sys.path is correct, but BEFORE main executes
    import mitm

    mitm.CA_DIR = ca_dir
    mitm.CA_KEY_FILE = os.path.join(ca_dir, "ca.key")
    mitm.CA_CERT_FILE = os.path.join(ca_dir, "ca.crt")


def main() -> None:
    # Run with the writable dir as CWD so any other relative file lookups
    # (e.g. logs) land somewhere sane instead of the read-only .app bundle.
    os.chdir(_writable_app_dir())
    _patch_ca_paths()

    # Late import: after patching mitm, `main.py` will pull in the patched
    # constants via `from mitm import CA_CERT_FILE`.
    from main import main as run
    run()


if __name__ == "__main__":
    main()
