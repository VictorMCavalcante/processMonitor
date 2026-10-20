import MonitorCore
import SwiftUI

struct PopoverView: View {
    @Bindable var store: MonitorStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            forgotten.padding(.horizontal, 12).padding(.bottom, 10)
            consumers.padding(.horizontal, 14).padding(.bottom, 12)
        }
        .frame(width: 310)
        .background(Theme.panel.opacity(0.92))
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 14) {
            PressureRing(percent: store.stats?.pressurePercent ?? 0, color: Theme.color(for: store.stats?.level ?? .normal))
            VStack(alignment: .leading, spacing: 3) {
                Text(Theme.label(for: store.stats?.level ?? .normal)).font(.system(size: 13, weight: .semibold))
                if let s = store.stats {
                    Text("\(Format.bytes(s.usedBytes)) de \(Format.bytes(s.totalBytes)) · swap \(Format.bytes(s.swapUsedBytes))")
                        .foregroundStyle(Theme.muted)
                    Text("CPU \(Int(s.cpuPercent))%").foregroundStyle(Theme.muted)
                }
            }
            .font(.system(size: 12))
        }
        .padding(14)
    }

    private var forgotten: some View {
        VStack(alignment: .leading, spacing: 5) {
            if store.suspects.isEmpty {
                Text("Nada esquecido").foregroundStyle(Theme.ok).font(.system(size: 12, weight: .semibold))
            } else {
                Text("\(store.suspects.count) esquecido\(store.suspects.count == 1 ? "" : "s") · \(Format.bytes(store.suspectBytes))")
                    .foregroundStyle(Theme.warn).font(.system(size: 12, weight: .semibold))
                ForEach(store.suspects.prefix(4)) { s in
                    HStack {
                        Text([s.row.identified.title, s.row.identified.project].compactMap { $0 }.joined(separator: " · ")).lineLimit(1)
                        Spacer()
                        Text("\(Format.age(since: s.row.snapshot.startTime, now: store.now)) · \(Format.bytes(s.row.snapshot.footprintBytes))")
                            .foregroundStyle(Theme.muted)
                    }
                    .font(.system(size: 11.5))
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill((store.suspects.isEmpty ? Theme.ok : Theme.warn).opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke((store.suspects.isEmpty ? Theme.ok : Theme.warn).opacity(0.3)))
    }

    private var consumers: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("MAIORES CONSUMIDORES").font(.system(size: 10.5)).foregroundStyle(Theme.muted2)
            ForEach(Grouping.group(store.rows, mode: .byApp).prefix(3)) { g in
                HStack {
                    Text(g.title + (g.subtitle.map { " · \($0)" } ?? "")).lineLimit(1)
                    Spacer()
                    Text(Format.bytes(g.footprintBytes)).foregroundStyle(Theme.muted)
                }
                .font(.system(size: 12))
            }
            HStack(spacing: 12) {
                Button("Abrir janela detalhada") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut("d", modifiers: .command)
                Spacer()
                Button("Sair") { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .font(.system(size: 12, weight: .semibold))
            .padding(.top, 8)
        }
    }
}

struct PressureRing: View {
    let percent: Int
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(Theme.panel2, lineWidth: 7)
            Circle().trim(from: 0, to: CGFloat(percent) / 100).stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
            Text("\(percent)%").font(.system(size: 13, weight: .bold))
        }
        .frame(width: 60, height: 60)
    }
}
