import MonitorCore
import SwiftUI

struct PopoverView: View {
    @Bindable var store: MonitorStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            charts
            chips
            if !store.suspects.isEmpty { forgotten }
            consumers
            footer
        }
        .padding(14)
        .frame(width: 330)
        .background(Theme.glass ? Theme.glassBase.opacity(0.86) : Theme.panel.opacity(0.92))
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .tint(Theme.brand)
        .onAppear {
            // MenuBarExtra(.window) ignores Esc; close the panel ourselves while it's shown.
            escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 53, event.window?.identifier?.rawValue.hasPrefix("main") != true else { return event }
                // close() desyncs SwiftUI's open state (next click does nothing); toggle via the status item instead.
                let closed = MainActor.assumeIsolated {
                    let button = NSApp.windows.lazy.compactMap { Self.statusButton(in: $0.contentView) }.first
                    button?.performClick(nil)
                    return button != nil
                }
                return closed ? nil : event
            }
        }
        .onDisappear {
            if let escMonitor { NSEvent.removeMonitor(escMonitor) }
            escMonitor = nil
        }
    }

    @State private var escMonitor: Any?

    private static func statusButton(in view: NSView?) -> NSStatusBarButton? {
        view as? NSStatusBarButton ?? view?.subviews.lazy.compactMap(statusButton).first
    }

    private var header: some View {
        let s = store.stats
        let level = s?.level ?? .normal
        return HStack(spacing: 14) {
            PressureRing(percent: s?.pressurePercent ?? 0, color: Theme.color(for: level))
            VStack(alignment: .leading, spacing: 6) {
                Text(Theme.label(for: level)).font(.system(size: 14, weight: .semibold))
                if let s {
                    Meter(fraction: Double(s.usedBytes) / Double(max(s.totalBytes, 1)), color: Theme.chart["used"] ?? Theme.accent)
                    HStack(spacing: 0) {
                        Text(Format.bytes(s.usedBytes)).foregroundStyle(Theme.text)
                        Text(" / \(Format.bytes(s.totalBytes))").foregroundStyle(Theme.muted2)
                    }
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                }
            }
        }
    }

    private var charts: some View {
        let s = store.stats
        return Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                tile("Memória", s.map { Format.bytes($0.usedBytes) }, key: "used")
                tile("CPU", s.map { "\(Int($0.cpuPercent))%" }, key: "cpu")
            }
            GridRow {
                tile("GPU", s?.gpuPercent.map { "\(Int($0))%" }, key: "gpu")
                tile("Swap", s.map { Format.bytes($0.swapUsedBytes) }, key: "swap")
            }
        }
    }

    private func tile(_ title: String, _ value: String?, key: String) -> some View {
        let color = Theme.chart[key] ?? Theme.accent
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.muted)
            }
            Text(value ?? "–").font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
            Sparkline(values: store.history[key]?.elements ?? [], color: color, height: 26).padding(.top, 2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line.opacity(0.8)))
    }

    private var chips: some View {
        let ports = store.highlightedPorts
        return Flow(spacing: 6) {
            if store.suspects.isEmpty { Chip(icon: "checkmark.circle.fill", text: "Nada esquecido", color: Theme.ok) }
            if let b = store.battery, b.onBattery {
                Chip(icon: "battery.75percent", text: "\(b.percent)% · " + BatteryText.forecast(store.minutesLeft), color: Theme.warn)
            }
            if let peak = store.peaks.last {
                Chip(icon: "bolt.fill", text: PeakText.when(peak.start, now: store.now).replacingOccurrences(of: "hoje ", with: ""), color: PeakText.color(peak.maxLevel))
            }
            if !ports.isEmpty {
                Chip(icon: "network", text: "\(ports[0])" + (ports.count > 1 ? " +\(ports.count - 1)" : ""), color: Theme.chart["cpu"] ?? Theme.accent)
            }
        }
        .lineLimit(1)
    }

    private var forgotten: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("\(store.suspects.count) esquecido\(store.suspects.count == 1 ? "" : "s")")
                Spacer()
                Text(Format.bytes(store.suspectBytes)).monospacedDigit()
            }
            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.warn)
            ForEach(store.suspects.prefix(4)) { s in
                HStack {
                    Text([s.row.identified.title, s.row.identified.project].compactMap { $0 }.joined(separator: " · ")).lineLimit(1)
                    Spacer()
                    Text("\(Format.age(since: s.row.snapshot.startTime, now: store.now)) · \(Format.bytes(s.row.snapshot.footprintBytes))")
                        .foregroundStyle(Theme.muted).monospacedDigit()
                }
                .font(.system(size: 11.5))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.warn.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.warn.opacity(0.3)))
    }

    private var consumers: some View {
        let groups = Array(Grouping.group(store.rows, mode: .byApp).prefix(4))
        let top = Double(groups.first?.footprintBytes ?? 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text("MAIORES CONSUMIDORES").font(.system(size: 9.5, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.muted2)
            ForEach(groups) { g in
                HStack(spacing: 8) {
                    AppIcon(title: g.title, appPath: g.rows.first?.identified.appBundlePath, size: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(g.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Spacer()
                            Text(Format.bytes(g.footprintBytes)).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.muted)
                        }
                        Meter(fraction: Double(g.footprintBytes) / top, color: Theme.accent, height: 3)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                store.windowVisible = true
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Abrir janela detalhada", systemImage: "macwindow")
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.brand.opacity(0.22)))
            }
            .keyboardShortcut("d", modifiers: .command)
            Spacer()
            Button("Sair") { NSApp.terminate(nil) }.foregroundStyle(Theme.muted)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
        .font(.system(size: 12, weight: .semibold))
        .padding(.top, 2)
    }
}

struct Meter: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.07))
                Capsule().fill(color).frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
    }
}

struct Chip: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9.5, weight: .bold))
            Text(text).font(.system(size: 11, weight: .medium).monospacedDigit())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.12)))
        .fixedSize()
    }
}

/// Lays children left to right, wrapping to a new line when the row is full.
struct Flow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: .unspecified)
                x += size.width + spacing
            }
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0; var y: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            let gap = rows[rows.count - 1].items.isEmpty ? 0 : spacing
            rows[rows.count - 1].items.append(i)
            rows[rows.count - 1].width += gap + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}

struct PressureRing: View {
    let percent: Int
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.07), lineWidth: 8)
            Circle().trim(from: 0, to: CGFloat(percent) / 100)
                .stroke(AngularGradient(colors: [color.opacity(0.5), color], center: .center, startAngle: .zero, endAngle: .degrees(360 * Double(percent) / 100)), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.5), radius: 4)
            VStack(spacing: 0) {
                Text("\(percent)%").font(.system(size: 16, weight: .bold, design: .rounded))
                Text("pressão").font(.system(size: 8.5, weight: .medium)).foregroundStyle(Theme.muted)
            }
        }
        .frame(width: 66, height: 66)
    }
}

enum PeakText {
    static func when(_ d: Date, now: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "HH:mm"
        if cal.isDate(d, inSameDayAs: now) { return "hoje " + f.string(from: d) }
        if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(d, inSameDayAs: y) { return "ontem " + f.string(from: d) }
        f.dateFormat = "dd/MM HH:mm"
        return f.string(from: d)
    }

    static func level(_ raw: Int) -> String {
        raw >= PressureLevel.critical.rawValue ? "crítico" : "moderado"
    }

    static func color(_ raw: Int) -> Color {
        raw >= PressureLevel.critical.rawValue ? Theme.bad : Theme.warn
    }
}
