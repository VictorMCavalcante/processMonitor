import AppKit
import MonitorCore
import SwiftUI

struct MenuBarLabel: View {
    let stats: SystemStats?

    var body: some View {
        if let stats {
            HStack(spacing: 4) {
                Image(nsImage: Self.pulse(Theme.nsColor(for: stats.level)))
                Text("\(stats.pressurePercent)%")
            }
        } else {
            Image(nsImage: Self.pulse(.labelColor))
        }
    }

    static func pulse(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 15, height: 11), flipped: true) { _ in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 1, y: 6.5))
            for (x, y) in [(4, 6.5), (6, 1.5), (9, 9.5), (10.8, 4.5), (14, 4.5)] as [(CGFloat, CGFloat)] { path.line(to: NSPoint(x: x, y: y)) }
            path.lineWidth = 1.7
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            color.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }
}
