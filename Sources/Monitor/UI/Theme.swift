import MonitorCore
import SwiftUI

enum Theme {
    static var glass: Bool { if #available(macOS 26.0, *) { true } else { false } }
    static let bg = Color(hex: 0x120E1A)
    static let panel = Color(hex: 0x1C1726)
    static let glassBase = Color(hex: 0x282C34) // One Dark gray
    static var panel2: Color { glass ? .white.opacity(0.05) : Color(hex: 0x241E31) }
    static let line = Color(hex: 0x2E2640)
    static let text = Color(hex: 0xF3EFFA)
    static let muted = Color(hex: 0x9A90AD)
    static let muted2 = Color(hex: 0x6B6380)
    static let brand = Color(hex: 0x8B3DFF)
    static let accent = Color(hex: 0xB48CFF)
    static let mist = Color(hex: 0xD9C7FF)
    static let field = Color(hex: 0x0E0B15)
    static var row: Color { glass ? .white.opacity(0.025) : Color(hex: 0x181321) }
    static let barTop = Color(hex: 0x1E1829)
    static var barBottom: Color { glass ? .clear : Color(hex: 0x181321) }
    static let ok = Color(hex: 0x3DDC84)
    static let warn = Color(hex: 0xFFB340)
    static let bad = Color(hex: 0xFF5C5C)

    static func color(for level: PressureLevel) -> Color {
        switch level {
        case .normal: ok
        case .warning: warn
        case .critical: bad
        }
    }

    static func nsColor(for level: PressureLevel) -> NSColor {
        switch level {
        case .normal: NSColor(red: 0.24, green: 0.86, blue: 0.52, alpha: 1)
        case .warning: NSColor(red: 1, green: 0.70, blue: 0.25, alpha: 1)
        case .critical: NSColor(red: 1, green: 0.36, blue: 0.36, alpha: 1)
        }
    }

    static func label(for level: PressureLevel) -> String {
        switch level {
        case .normal: "Pressão normal"
        case .warning: "Pressão moderada"
        case .critical: "Pressão crítica"
        }
    }
}

extension View {
    /// Liquid Glass panel on macOS 26+, flat panel before.
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = 10) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular.tint(Theme.brand.opacity(0.14)), in: .rect(cornerRadius: cornerRadius))
        } else {
            background(RoundedRectangle(cornerRadius: cornerRadius).fill(Theme.panel))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Theme.line))
        }
    }

    /// Translucent window (desktop shows through, tinted) on macOS 26+.
    @ViewBuilder
    func glassWindowBackground() -> some View {
        if #available(macOS 26.0, *) {
            background(Theme.brand.opacity(0.16)).background(Theme.glassBase.opacity(0.86)).containerBackground(.ultraThinMaterial, for: .window)
        } else {
            background(Theme.bg)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
