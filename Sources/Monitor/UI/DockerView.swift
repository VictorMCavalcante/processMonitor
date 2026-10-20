import MonitorCore
import SwiftUI

struct DockerView: View {
    let store: MonitorStore
    let onStop: (DockerContainer) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.containers) { c in line(c) }
                }
            }
            if store.containers.isEmpty {
                Text("Nenhum container em execução.").foregroundStyle(Theme.muted).font(.system(size: 12)).padding(20)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var header: some View {
        cells("CONTAINER", "PROJETO", "IMAGEM", "ESTADO", "MEMÓRIA", "CPU", "PORTAS")
            .font(.system(size: 10.5)).foregroundStyle(Theme.muted2)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.panel2)
    }

    private func line(_ c: DockerContainer) -> some View {
        HStack(spacing: 10) {
            cells(c.name, c.composeProject ?? "—", c.image, c.state, Format.bytes(c.memoryBytes),
                  String(format: "%.1f%%", c.cpuPercent).replacingOccurrences(of: ".", with: ","),
                  c.publishedPorts.isEmpty ? "—" : c.publishedPorts.map(String.init).joined(separator: ", "))
            Button("Parar") { onStop(c) }.buttonStyle(PillButton())
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .overlay(alignment: .top) { Theme.line.frame(height: 1) }
    }

    private func cells(_ values: String...) -> some View {
        let widths: [CGFloat?] = [nil, 120, 170, 80, 80, 60, 110]
        return HStack(spacing: 10) {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                Text(v).lineLimit(1)
                    .frame(width: widths[i], alignment: .leading)
                    .frame(maxWidth: widths[i] == nil ? .infinity : nil, alignment: .leading)
            }
        }
    }
}
