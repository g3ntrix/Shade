# Shade

**Shade** is a premium, DPI-resistant macOS proxy client designed to route traffic through **Google Apps Script** relays. It combines a high-performance Python core with a modern, native SwiftUI interface to provide a seamless and secure browsing experience.

<p align="center">
  <img src="macos-app/sc/app-dashboard.png" width="400" alt="Shade App Dashboard" />
  <img src="macos-app/sc/menubar.png" width="250" alt="Shade Menu Bar" />
</p>

[English] | [فارسی](README_FA.md)

## Key Features

- **DPI-Resistant Tunneling**: Leverages SNI fronting via Google infrastructure to bypass advanced censorship and regional blocks.
- **Smart Load Balancing**: Distribute traffic across multiple Apps Script deployments simultaneously to maximize speed and reliability.
- **Premium Native UI**: A sleek, resource-efficient macOS experience built with SwiftUI, featuring glassmorphism and real-time animations.
- **Menu Bar Control**: Monitor live speeds and toggle your connection directly from the system menu bar.
- **Zero-Config Setup**: Automatic SSL certificate installation and system-wide proxy configuration with a single click.
- **IP Scanner**: Built-in tool to find the fastest reachable Google frontend IP for your specific network.

## Getting Started

1. **Deploy Relay**: Deploy the provided `Code.gs` snippet to Google Apps Script as a Web App.
2. **Add Profile**: Paste your **Script ID** and **Auth Key** into Shade.
3. **Connect**: Hit **Start**. Toggle "Set as system proxy" to route all traffic instantly.

## Technical Snapshot

- **Local Ports**: HTTP (`1080`), SOCKS5 (`8080`) by default.
- **Architecture**: Universal binary with native support for Apple Silicon and Intel.
- **Security**: Secure TLS 1.3 tunnel to Google's Edge network.

---

## Support Development

If Shade helps you stay connected, consider supporting the project:

- **TON**: `UQCriHkMUa6h9oN059tyC23T13OsQhGGM3hUS2S4IYRBZgvx`
- **USDT (BEP20)**: `0x71F41696c60C4693305e67eE3Baa650a4E3dA796`
- **TRX (TRON)**: `TFrCzU7bDey9WSh3fhqCBqhaiMzr8VhcUV`
