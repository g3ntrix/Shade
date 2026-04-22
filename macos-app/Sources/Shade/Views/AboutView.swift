import SwiftUI
import AppKit

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    ShadeBrandImage(size: 72, cornerRadius: 16)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Shade")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("A native macOS client for MasterHttpRelayVPN. Ships the relay core and proxy in a single app so you don't need a separate SOCKS client.")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 13))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }
                    Spacer()
                }

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Credits")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Client developed by g3ntrix")
                            .font(.system(size: 13, weight: .medium))
                        Link("Telegram — @g3ntrix",
                             destination: URL(string: "https://t.me/g3ntrix")!)
                            .font(.system(size: 13, weight: .medium))
                        Link("Upstream project: MasterHttpRelayVPN (masterdnsvpn)",
                             destination: URL(string: "https://github.com/masterking32/MasterHttpRelayVPN")!)
                            .font(.system(size: 13, weight: .medium))
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Donations")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        
                        DonationRow(label: "TON", address: "UQCriHkMUa6h9oN059tyC23T13OsQhGGM3hUS2S4IYRBZgvx")
                        DonationRow(label: "USDT (BEP20)", address: "0x71F41696c60C4693305e67eE3Baa650a4E3dA796")
                        DonationRow(label: "TRX (TRON)", address: "TFrCzU7bDey9WSh3fhqCBqhaiMzr8VhcUV")
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What's inside")
                            .font(.system(size: 13, weight: .semibold))
                        BulletRow(icon: "shippingbox", text: "Bundled Python core (shade-core) — no system Python required.")
                        BulletRow(icon: "lock.shield", text: "Auto MITM CA management under ~/Library/Application Support/Shade/ca.")
                    }
                }

                Spacer(minLength: 12)
            }
        }
    }
}

private struct BulletRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DonationRow: View {
    let label: String
    let address: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 90, alignment: .leading)
            Text(verbatim: address)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(address, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    copied = false
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
