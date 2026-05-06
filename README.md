# Shade

**Shade** is a DPI-resistant macOS proxy client built for censored networks. It combines a high-performance Python core with a native SwiftUI app and routes traffic through **Google Apps Script** and **tunnel-node** transports for reliable browsing and app connectivity.

<table align="center">
  <tr>
    <td width="50%" align="center" valign="top">
      <img src="macos-app/sc/app-dashboard.png" width="100%" alt="Shade App Dashboard" />
    </td>
    <td width="50%" align="center" valign="top">
      <img src="macos-app/sc/wizard.png" width="100%" alt="Shade Setup Wizard" />
    </td>
  </tr>
  <tr>
    <td width="39%" align="center" valign="top">
      <img src="macos-app/sc/profile.png" width="100%" alt="Shade Profile Sharing and Import" />
    </td>
    <td width="39%" align="center" valign="top">
      <img src="macos-app/sc/setup-guide.png" width="100%" alt="Shade Guided Setup" />
    </td>
    <td width="22%" align="center" valign="top">
      <img src="macos-app/sc/menubar.png" width="100%" alt="Shade Menu Bar" />
    </td>
  </tr>
</table>

[English] | [فارسی](README_FA.md)

## Key Features

- **Easy Setup**: Interactive setup wizard guides you step by step and writes your config automatically.
- **Full Tunnel Mode**: End-to-end tunnel mode for broader app compatibility, including SOCKS clients on other devices.
- **Share & Import Profiles**: Export your working profile and import it on another device without manual re-entry.
- **DPI-Resistant Transport**: Uses Google-fronted relay paths for restrictive networks.
- **Smart Load Balancing**: Distributes relay traffic across multiple deployments for speed and stability.
- **Native macOS Experience**: SwiftUI dashboard, setup flow, and menu bar controls with live status.
- **SOCKS5 + UDP Support**: Improved SOCKS handling for real-world mobile apps and browser traffic.
- **IP Scanner**: Built-in scanner to find the best reachable Google frontend IP.

## Getting Started

1. **Open Setup Wizard** in Shade and choose your setup method.
2. **Deploy Relay**:
   - Use `apps_script/Code.gs` for standard mode.
   - Use `apps_script/CodeFull.gs` for standard + full tunnel mode.
3. **Configure Automatically**: wizard validates inputs and writes config for you.
4. **Connect**: start Shade and enable system proxy if needed.

## Sharing & Importing Profiles

- Use the app's share/export flow to generate a setup-ready profile from a working configuration.
- Import that profile on another device to apply script IDs, keys, and related settings quickly.
- This is the fastest way to replicate a known-good setup across devices and avoid manual mistakes.

## Setup Wizard

- Interactive, guided, and beginner-friendly.
- Validates server and relay inputs before saving.
- Handles config creation so users do not need to manually edit JSON for common paths.
- Includes improved VPS lifecycle guidance and cleanup instructions.

## Apps Script Modes (Copy/Paste Friendly)

- **`apps_script/Code.gs`**: standard relay mode (works with current normal setup).
- **`apps_script/CodeFull.gs`**: backward compatible with normal relay mode **and** required for Full Tunnel Mode.

If you use `CodeFull.gs`, set these constants before deploying:

```javascript
const AUTH_KEY = "YOUR_AUTH_KEY";
const TUNNEL_SERVER_URL = "https://YOUR_TUNNEL_NODE_URL";
const TUNNEL_AUTH_KEY = "YOUR_TUNNEL_AUTH_KEY";
```

Compatibility notes:

- `CodeFull.gs` still supports regular single/batch relay payloads used by normal mode.
- Exit-node (`en`) requests are also supported in `CodeFull.gs`.
- Full Tunnel Mode in Shade requires a deployment built from `CodeFull.gs` (old `Code.gs` returns `bad url` for tunnel ops).

## Technical Snapshot

- **Local Ports**: HTTP (`1080`), SOCKS5 (`8080`) by default.
- **Architecture**: Universal binary with native support for Apple Silicon and Intel.
- **Security**: TLS-protected transport through Google-fronted relay paths.

---

## Support Development

If Shade helps you stay connected, consider supporting the project:

- **TON**: `UQCriHkMUa6h9oN059tyC23T13OsQhGGM3hUS2S4IYRBZgvx`
- **USDT (BEP20)**: `0x71F41696c60C4693305e67eE3Baa650a4E3dA796`
- **TRX (TRON)**: `TFrCzU7bDey9WSh3fhqCBqhaiMzr8VhcUV`
