import SwiftUI

// MARK: - Badge (profiles tagged for exit / full tunnel)

struct TunnelTagBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.turn.up.right.circle.fill")
                .font(.system(size: 8, weight: .bold))
            Text("tunnel")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(.mint)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(.mint.opacity(0.15))
                .overlay(Capsule().stroke(.mint.opacity(0.35), lineWidth: 0.5))
        )
        .fixedSize()
    }
}
