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
            card("Swap", s.map { Format.bytes($0.swapUsedBytes) } ?? "–", key: "swap", color: Theme.bad)
        }
    }

    private func card(_ title: String, _ value: String, key: String, color: Color, valueColor: Color = Theme.text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11)).foregroundStyle(Theme.muted)
            Text(value).font(.system(size: 18, weight: .semibold)).foregroundStyle(valueColor)
            Sparkline(values: store.history[key]?.elements ?? [], color: color).padding(.top, 4)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
    }
}
