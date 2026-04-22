# Shade — macOS client

A native macOS GUI for routing traffic through Google Apps Script relays. It bundles a self-contained Python listener (shade-core) so you don't need a separate proxy client.

## What you enter in the UI

Just two things on the Dashboard:

- **Script ID** — the Google Apps Script deployment ID.
- **Auth Key** — the `AUTH_KEY` you set in your relay configuration.

Everything else (ports, fronting IP, MITM CA install) is handled automatically when you hit **Start**.

## Modes

- **SOCKS5 / HTTP (default)** — local listener on `127.0.0.1:8085` (HTTP) and `127.0.0.1:8086` (SOCKS5). Point your browser or per-app proxy at these.
- **System Proxy** — toggle from the Dashboard to automatically set macOS system-wide HTTP/HTTPS proxy settings to point to the local Shade listeners.

*Note: TUN/System Tunnel mode is currently not implemented.*

## Building

From the repo root:

```bash
bash macos-app/scripts/build-release.sh
```

Outputs:

- `macos-app/dist/Shade.app`
- `macos-app/dist/Shade-0.1.0-alfa.dmg`

### Stages (individual scripts)

Located in `macos-app/scripts/`:

```bash
# 1. Freeze the Python listener into a self-contained binary.
./build-core.sh

# 2. Build the Swift app and embed the shade-core binary.
./build-app.sh

# 3. Wrap the .app in a DMG.
./make-dmg.sh
```

### Requirements on the build machine

- **Xcode 15+** (SwiftPM + `swift build`, `lipo`, `codesign`, `hdiutil`).
- **python3 ≥ 3.10** for the host arch.
- **Optional:** a second python3 for the *other* arch if you want a universal `shade-core`. Set `OTHER_PYTHON=/path/to/python3`. Without it, the core falls back to host-arch only.
- **Internet access** the first time for PyInstaller and dependency installation.

### Optional: App Icon

Drop a square PNG at `macos-app/logo/Shade.png` before building. `scripts/make-icns.sh` produces a proper Big Sur+ squircle `.icns` and plugs it into the bundle.

## How it all fits together

```
┌──────────────────────────┐
│  Shade.app (SwiftUI)      │
│                          │
│   ┌───────────────────┐  │
│   │ shade-core (py)   │  │
│   │ main.py + mitm +  │  │
│   │ domain_fronter    │  │
│   └───────────────────┘  │
│   │   HTTP 8085 │ SOCKS5 │
│   │   for browser or     │
│   │   system proxy       │
└──────────────────────────┘
```

- Swift writes `~/Library/Application Support/Shade/config.json` with your values and launches `shade-core -c <path>`.
- `shade-core` is the Python logic frozen via PyInstaller. It manages the local proxy listeners.
- The app handles MITM CA management automatically, storing certificates under `~/Library/Application Support/Shade/ca` so they persist outside the read-only application bundle.

## Unsigned App Note

The build is ad-hoc codesigned, not notarized. macOS may block first launch. Right-click → **Open**, or allow under **System Settings → Privacy & Security**.
