import SwiftUI
import AppKit

/// Loads `Shade.png` from the SwiftPM resource bundle or the flat Resources
/// dir (the build script copies it there so both paths work).
struct ShadeBrandImage: View {
    var size: CGFloat = 36
    var cornerRadius: CGFloat = 10

    var body: some View {
        Group {
            if let img = Self.loadNSImage() {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private static func loadNSImage() -> NSImage? {
        if let url = Bundle.main.url(forResource: "Shade", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let url = Bundle.module.url(forResource: "Shade", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let bundles = Bundle.main.urls(forResourcesWithExtension: "bundle", subdirectory: nil) {
            for b in bundles {
                let u = b.appendingPathComponent("Shade.png")
                if let img = NSImage(contentsOf: u) { return img }
            }
        }
        return nil
    }
}
