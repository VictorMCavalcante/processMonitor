import MonitorCore
import SwiftUI

struct PortsView: View {
    let store: MonitorStore
    let onRelease: (UInt16) -> Void
    @State private var portText = ""

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("Liberar porta").foregroundStyle(Theme.muted)
                TextField("3000", text: $portText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 90)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.field))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.line))
                    .onSubmit(release)
                Button("Liberar", action: release).buttonStyle(PillButton(color: Theme.bad)).disabled(UInt16(portText) == nil)
                Spacer()
                Text("\(store.portEntries.count) porta\(store.portEntries.count == 1 ? "" : "s") em uso").foregroundStyle(Theme.muted)
            }
            .font(.system(size: 12))
            table
        }
    }

    private func release() {
        guard let port = UInt16(portText.trimmingCharacters(in: .whitespaces)) else { return }
        onRelease(port)
    }

    private var table: some View {
        VStack(spacing: 0) {
            row(cells: ["PORTA", "QUEM USA", "PROJETO", "EXPOSIÇÃO", "PID", "ABERTO HÁ"], header: true, action: nil)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.portEntries) { e in
                        row(cells: [String(e.port), e.title, e.project ?? "—", e.exposure == .local ? "só neste Mac" : "aberta na rede",
                                    pid(e), e.startTime.map { Format.age(since: $0, now: store.now) } ?? "—"],
                            header: false, exposure: e.exposure) { onRelease(e.port) }
                    }
                }
            }
            if store.portEntries.isEmpty {
                let query = store.search.trimmingCharacters(in: .whitespaces)
                if query.isEmpty {
                    Text("Nenhuma porta TCP em uso.").foregroundStyle(Theme.muted).font(.system(size: 12)).padding(20)
                } else {
                    VStack(spacing: 8) {
                        Text("Nenhuma porta corresponde a “\(query)”.").foregroundStyle(Theme.muted)
                        Button("Limpar busca") { store.search = "" }.buttonStyle(PillButton())
                    }
                    .font(.system(size: 12))
                    .padding(20)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func pid(_ e: PortEntry) -> String {
        switch e.owner {
        case .process(let r): String(r.id)
        case .container(let c): "container " + String(c.id.prefix(8))
        }
    }

    private func row(cells: [String], header: Bool, exposure: Exposure? = nil, action: (() -> Void)?) -> some View {
        let widths: [CGFloat?] = [70, nil, 170, 120, 130, 90]
        return HStack(spacing: 10) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, text in
                Group {
                    if i == 3, let exposure {
                        Text(text).foregroundStyle(exposure == .local ? Theme.muted : Theme.warn)
                    } else {
                        Text(text).lineLimit(1).fontWeight(i == 0 && !header ? .semibold : .regular)
                    }
                }
                .font(i == 0 && !header ? .system(size: 12, design: .monospaced) : .system(size: header ? 10.5 : 12))
                .frame(width: widths[i], alignment: .leading)
                .frame(maxWidth: widths[i] == nil ? .infinity : nil, alignment: .leading)
            }
            Group {
                if let action {
                    Button(action: action) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                        .buttonStyle(.plain).foregroundStyle(Theme.muted).help("Liberar porta")
                } else {
                    Color.clear
                }
            }
            .frame(width: 22, height: 14)
        }
        .foregroundStyle(header ? Theme.muted2 : Theme.text)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(header ? Theme.panel2 : .clear)
        .overlay(alignment: .top) { Theme.line.frame(height: 1) }
    }
}
