import AppKit
import MonitorCore
import SwiftUI

struct AppIcon: View {
    let title: String
    let appPath: String?
    var size: CGFloat = 20

    var body: some View {
        if let appPath {
            Image(nsImage: Self.icon(appPath)).resizable().frame(width: size, height: size)
        } else {
            Text(String(title.prefix(1)).uppercased())
                .font(.system(size: size * 0.55, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.25).fill(Self.color(for: title)))
        }
    }

    private static let icons = NSCache<NSString, NSImage>()

    /// NSWorkspace hits the disk per call; rows re-render every cycle.
    static func icon(_ path: String) -> NSImage {
        if let cached = icons.object(forKey: path as NSString) { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        icons.setObject(image, forKey: path as NSString)
        return image
    }

    static func color(for name: String) -> Color {
        let palette: [UInt32] = [0x5059C9, 0xD97757, 0x646CFF, 0x00758F, 0x2E7D32, 0x8E44AD, 0xC0392B, 0x16A085]
        let hash = name.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        return Color(hex: palette[Int(hash % UInt32(palette.count))])
    }
}
