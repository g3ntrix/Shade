# Shade

Lightweight, premium macOS proxy client for routing traffic through **Google Apps Script** relays. Securely bypass censorship with a sleek, native desktop interface.

<p align="center">
  <img src="macos-app/sc/app-dashboard.png" width="400" alt="Shade App Dashboard" />
  <img src="macos-app/sc/menubar.png" width="250" alt="Shade Menu Bar" />
</p>

English | [فارسی](README_FA.md)

## Core Features

- **Live Speed Meter**: Real-time download/upload speeds and cumulative data usage tracking.
- **Menu Bar Mini-App**: Control your connection, toggle system proxy, and monitor speeds directly from the macOS menu bar.
- **Unified Proxy Engine**: Integrated HTTP and SOCKS5 local proxy servers.
- **Zero-Config HTTPS**: Automatic certificate generation and installation for seamless MITM decryption.
- **Multiple Profiles**: Quickly switch between different relay nodes (Script IDs).
- **Google IP Scanner**: Built-in scanner to find working Google IPs for your relay.
- **Connectivity Testing**: Rapid ping-style latency checks to verify relay health.
- **Native Experience**: Built with SwiftUI for a premium, resource-efficient macOS experience.

## How It Works

Shade tunnels your traffic through a Google Apps Script relay. Because the initial connection is fronted by `www.google.com`, it is highly resistant to Deep Packet Inspection (DPI) and regional blocking.

## Getting Started

1. **Import Credentials**: Paste your Google Apps Script ID and Auth Key.
2. **Start Proxy**: Click the Start button.
3. **Configure Browser**: Point your browser to the local SOCKS5 or HTTP port (default: 8081).
4. **System Mode**: Toggle "Set as system proxy" to route all macOS traffic through the tunnel.

## Technical Details

- **Local Ports**: SOCKS5 (8081), HTTP (8080) by default.
- **Architecture**: Universal (Apple Silicon & Intel) support.
- **Security**: TLS 1.3 tunnel to Google Infrastructure.

## Donations

Support the development of Shade:

- **TON**: `UQCriHkMUa6h9oN059tyC23T13OsQhGGM3hUS2S4IYRBZgvx`
- **USDT (BEP20)**: `0x71F41696c60C4693305e67eE3Baa650a4E3dA796`
- **TRX (TRON)**: `TFrCzU7bDey9WSh3fhqCBqhaiMzr8VhcUV`
