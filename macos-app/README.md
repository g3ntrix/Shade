# Shade — macOS client

A native macOS GUI for [MasterHttpRelayVPN](https://github.com/masterking32/MasterHttpRelayVPN). Bundles the Python listener and a SOCKS→TUN bridge so you don't need a separate SOCKS client (nekoray/v2ray/etc).

## What you enter in the UI

Just two things on the Dashboard:

- **Script ID** — the Google Apps Script deployment ID.
- **Auth Key** — the `AUTH_KEY` you set in `Code.gs`.

Everything else (ports, fronting IP, MITM CA install, TUN routes) runs automatically when you hit **Start**.

## Modes

- **SOCKS5 / HTTP (default)** — local listener on `127.0.0.1:8085` (HTTP) and `127.0.0.1:8086` (SOCKS5). Point your browser or per-app proxy at those.
- **System tunnel (TUN)** — toggle from the Dashboard. First enable asks for your password once (installs a narrowly-scoped sudoers rule); after that it flips instantly.

## Building

From the repo root:

```bash
VERSION=1.0.0 ./scripts/build-release.sh
```

Outputs:

- `macos-app/dist/Shade.app`
- `macos-app/dist/Shade-1.0.0.dmg`

### Stages (if you want to run them individually)

```bash
# 1. Freeze the Python listener into a self-contained binary.
./macos-app/scripts/build-core.sh

# 2. Download the tun2socks binary (universal).
./macos-app/scripts/fetch-tun2socks.sh

# 3. Build the Swift app and embed both binaries.
./macos-app/scripts/build-app.sh

# 4. Wrap the .app in a DMG.
./macos-app/scripts/make-dmg.sh
```

### Requirements on the build machine

- **Xcode 15+** (SwiftPM + `swift build`, `lipo`, `codesign`, `hdiutil`).
- **python3 ≥ 3.10** for the host arch.
- **Optional:** a second python3 for the *other* arch if you want a universal `shade-core`. Set `OTHER_PYTHON=/path/to/python3`. Without it the core falls back to host-arch only.
- **Internet access** the first time (PyInstaller install + tun2socks download). Downloads are cached under `.core-build/` and `.tun2socks-cache/`.

### Optional: app icon

Drop a square PNG at `macos-app/logo/Shade.png` before building. `scripts/make-icns.sh` produces a proper Big Sur+ squircle `.icns` and plugs it into the bundle. Without a logo, Finder shows the default system icon — everything still works.

## How it all fits together

```
┌──────────────────────────┐
│  Shade.app (SwiftUI)      │
│                          │
│   ┌───────────────────┐  │        ┌──────────────┐
│   │ shade-core (py)   │──┼──SOCKS─▶│ tun2socks    │──▶ utunN ──▶ system
│   │ main.py + mitm +  │  │  8086  │ (optional)   │
│   │ domain_fronter    │  │        └──────────────┘
│   └───────────────────┘  │
│   │   HTTP 8085 │ SOCKS5 │
│   │   for direct client  │
│   │   integrations       │
└──────────────────────────┘
```

- Swift writes `~/Library/Application Support/Shade/config.json` with your values and launches `shade-core -c <path>`.
- `shade-core` is `main.py` frozen via PyInstaller. The bootstrap (`macos-app/core/shade_core.py`) re-points `mitm.CA_DIR` to `~/Library/Application Support/Shade/ca` so the CA key/cert live in a writable location instead of the read-only `.app`.
- When **System tunnel (TUN)** is on, `tun2socks` attaches to a freshly-created `utun9` and pipes it through `shade-core`'s SOCKS5 listener. A tiny wrapper at `/usr/local/bin/shade-tun` (installed once under admin) handles `ifconfig` + `route` so we never need to keep root around.

## Uninstalling the TUN helper

```bash
sudo rm -f /etc/sudoers.d/shade /usr/local/bin/shade-tun
```

The app also has a hidden call path for this (`SudoPrivilege.uninstall()`) but there's no UI button wired to it yet — add one to Settings if you want.

## Unsigned app note

The build is ad-hoc codesigned, not notarized. macOS may block first launch. Right-click → **Open**, or allow under **System Settings → Privacy & Security**.
