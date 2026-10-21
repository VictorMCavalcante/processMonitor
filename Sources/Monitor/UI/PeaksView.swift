import MonitorCore
import SwiftUI

struct PeaksView: View {
    let store: MonitorStore

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(store.peaks.reversed()) { p in card(p) }
                if store.peaks.isEmpty {
                    Text("Nenhum pico de pressão nos últimos 7 dias.").foregroundStyle(Theme.muted).font(.system(size: 12)).padding(30)
                }
            }
        }
    }

    private func card(_ p: PeakEpisode) -> some View {
        let color = PeakText.color(p.maxLevel)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(PeakText.when(p.start, now: store.now)).fontWeight(.semibold)
                Text("Pressão \(PeakText.level(p.maxLevel)) · máximo \(p.maxPressure)%").foregroundStyle(color)
                Spacer()
                Text(p.end.map { "duração " + Format.age(since: p.start, now: $0) } ?? "em andamento").foregroundStyle(Theme.muted)
            }
            ForEach(Array(p.top.enumerated()), id: \.offset) { _, item in
                HStack {
                    Text(item.title).lineLimit(1)
                    Spacer()
                    Text(Format.bytes(item.bytes)).foregroundStyle(Theme.muted)
                }
                .font(.system(size: 12))
                .padding(.leading, 19)
            }
            if let gpu = p.topGPU, !gpu.isEmpty {
                Text("GPU: " + gpu.map { "\($0.title) \(Int($0.percent))%" }.joined(separator: " · "))
                    .foregroundStyle(Theme.muted).font(.system(size: 12)).padding(.leading, 19)
            }
        }
        .font(.system(size: 12.5))
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
    }
}
