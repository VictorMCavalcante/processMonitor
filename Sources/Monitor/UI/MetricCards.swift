import MonitorCore
import SwiftUI

struct MetricCards: View {
    let store: MonitorStore

    var body: some View {
        let s = store.stats
        HStack(spacing: 10) {
            card("Pressão de memória", s.map { "\($0.pressurePercent)%" } ?? "–", key: "pressure", color: Theme.color(for: s?.level ?? .normal), valueColor: Theme.color(for: s?.level ?? .normal))
            card("Memória usada", s.map { Format.bytes($0.usedBytes) } ?? "–", key: "used", color: Theme.accent)
            card("CPU", s.map { "\(Int($0.cpuPercent))%" } ?? "–", key: "cpu", color: Theme.ok)
            card("GPU", s?.gpuPercent.map { "\(Int($0))%" } ?? "–", key: "gpu", color: Theme.accent, note: s?.gpuMemoryBytes.map { "\(Format.bytes($0)) de memória de GPU" })
            card("Swap", s.map { Format.bytes($0.swapUsedBytes) } ?? "–", key: "swap", color: Theme.bad)
        }
    }

    private func card(_ title: String, _ value: String, key: String, color: Color, valueColor: Color = Theme.text, note: String? = nil) -> some View {
        StatCard(title: title, value: value, valueColor: valueColor, note: note) {
            Sparkline(values: store.history[key]?.elements ?? [], color: color).padding(.top, 4)
        }
    }
}

struct StatCard<Footer: View>: View {
    let title: String
    let value: String
    var valueColor = Theme.text
    let note: String?
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11)).foregroundStyle(Theme.muted)
            Text(value).font(.system(size: 18, weight: .semibold)).foregroundStyle(valueColor).lineLimit(1).minimumScaleFactor(0.6)
            Text(note ?? " ").font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1)
            footer
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel()
    }
}

extension StatCard where Footer == EmptyView {
    init(title: String, value: String, note: String?) {
        self.init(title: title, value: value, note: note) { EmptyView() }
    }
}
