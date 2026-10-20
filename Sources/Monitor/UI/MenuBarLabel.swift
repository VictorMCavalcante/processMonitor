import AppKit
import MonitorCore
import SwiftUI

struct MenuBarLabel: View {
    let stats: SystemStats?

    var body: some View {
        if let stats {
            HStack(spacing: 4) {
                Image(nsImage: Self.dot(Theme.nsColor(for: stats.level)))
                Text("\(stats.pressurePercent)%")
            }
        } else {
            Image(systemName: "memorychip")
        }
    }

    static func dot(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 9, height: 9), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
