import SwiftUI
import AppKit

/// Displays the Shade brand logo with high quality.
/// It prioritizes the system application icon (which uses the multi-res .icns)
/// to ensure sharpness on all display scales.
struct ShadeBrandImage: View {
    var size: CGFloat = 36
    var cornerRadius: CGFloat = 10
    var useSystemIcon: Bool = true

    var body: some View {
        Group {
            if let img = Self.loadLogoImage(useSystemIcon: useSystemIcon) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
        .frame(width: size, height: size)
    }

    private static func loadLogoImage(useSystemIcon: Bool) -> NSImage? {
        if useSystemIcon {
            // 1. Try system application icon (best quality, handles Retina automatically)
            if let appIcon = NSApp.applicationIconImage, appIcon.size.width > 0 {
                return appIcon
            }
        }

        // 2. Try Shade.icns (multi-resolution container)
        if let url = Bundle.main.url(forResource: "Shade", withExtension: "icns"),
           let img = NSImage(contentsOf: url) {
            return img
        }

        // 3. Try Shade.png (high-res source)
        if let url = Bundle.main.url(forResource: "Shade", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            // Ensure NSImage knows it's a high-res image if it's large
            if img.size.width > 512 {
                img.size = NSSize(width: sizeForHighRes(img), height: sizeForHighRes(img))
            }
            return img
        }

        // 4. Module bundle fallbacks
        for ext in ["icns", "png"] {
            if let url = Bundle.module.url(forResource: "Shade", withExtension: ext),
               let img = NSImage(contentsOf: url) {
                return img
            }
        }

        return nil
    }

    private static func sizeForHighRes(_ img: NSImage) -> CGFloat {
        // Just a helper to return a reasonable point size for a pixel-heavy image
        // so NSImage doesn't assume it's a massive canvas in points.
        return 1024
    }
}
