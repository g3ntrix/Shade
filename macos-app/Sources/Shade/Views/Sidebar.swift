import SwiftUI

struct Sidebar: View {
    @EnvironmentObject var app: AppState
    @Binding var tab: ContentView.Tab

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ShadeBrandImage(size: 30, cornerRadius: 8)
                Text("Shade")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 28)
            .padding(.bottom, 14)

            VStack(spacing: 2) {
                ForEach(ContentView.Tab.allCases) { t in
                    SidebarItem(tab: t, selected: tab == t) { tab = t }
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            StatusChip(status: app.status)
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Static gradient instead of .ultraThinMaterial: the material requires
        // a fresh real-time blur pass every frame, which is what causes the
        // stutter you see when reopening the sidebar (the column animates in
        // before the blur catches up). A cheap gradient renders instantly.
        .background(
            LinearGradient(
                colors: [
                    Color(.sRGB, red: 0.09, green: 0.10, blue: 0.14, opacity: 1),
                    Color(.sRGB, red: 0.06, green: 0.07, blue: 0.10, opacity: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
    }
}

private struct SidebarItem: View {
    let tab: ContentView.Tab
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(tab.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected
                          ? Color.accentColor.opacity(0.22)
                          : (hover ? Color.white.opacity(0.06) : .clear))
            )
            .foregroundColor(selected ? .accentColor : .primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct StatusChip: View {
    let status: AppState.Status
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.8), radius: 4)
            Text(status.label)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.06))
        )
    }
    var color: Color {
        switch status {
        case .running: return .green
        case .starting, .stopping: return .yellow
        case .error: return .red
        case .stopped: return .secondary
        }
    }
}
