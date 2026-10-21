import MonitorCore
import SwiftUI

struct ForgottenBanner: View {
    let store: MonitorStore
    @State private var unchecked: Set<Int32> = []

    var body: some View {
        let selected = Set(store.suspects.map(\.id)).subtracting(unchecked)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(store.suspects.count) esquecido\(store.suspects.count == 1 ? "" : "s")").foregroundStyle(Theme.warn).fontWeight(.semibold)
                Text("· liberaria \(Format.bytes(store.suspectBytes))").foregroundStyle(Theme.muted)
                Spacer()
                Button("Fechar \(selected.count) selecionado\(selected.count == 1 ? "" : "s")") {
                    Task { await store.closeSuspects(selected) }
                }
                .buttonStyle(PillButton(color: Theme.bad))
                .disabled(selected.isEmpty)
            }
            FlowChips(suspects: store.suspects, now: store.now, unchecked: $unchecked)
        }
        .font(.system(size: 12))
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [Theme.warn.opacity(0.14), Theme.warn.opacity(0.04)], startPoint: .leading, endPoint: .trailing)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.warn.opacity(0.35)))
        .onAppear { unchecked = Set(store.suspects.filter { if case .suspendedSession = $0.reason { true } else { false } }.map(\.id)) }
    }
}

private struct FlowChips: View {
    let suspects: [Suspect]
    let now: Date
    @Binding var unchecked: Set<Int32>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(suspects) { s in
                    Toggle(isOn: Binding(get: { !unchecked.contains(s.id) }, set: { on in if on { unchecked.remove(s.id) } else { unchecked.insert(s.id) } })) {
                        Text([s.row.identified.title, s.row.identified.project, Format.age(since: s.row.snapshot.startTime, now: now)].compactMap { $0 }.joined(separator: " · "))
                    }
                    .toggleStyle(.checkbox)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.04)))
                    .overlay(Capsule().stroke(Theme.line))
                }
            }
        }
    }
}

struct PillButton: ButtonStyle {
    var color: Color = Theme.panel2
    var textColor: Color = Color(hex: 0x1A0B0B)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .foregroundStyle(color == Theme.panel2 ? Theme.text : textColor)
            .background(RoundedRectangle(cornerRadius: 7).fill(color.opacity(configuration.isPressed ? 0.7 : 1)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.line, lineWidth: color == Theme.panel2 ? 1 : 0))
    }
}
