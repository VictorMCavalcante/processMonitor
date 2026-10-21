import AppKit
import MonitorCore
import SwiftUI

struct DetailPanel: View {
    let store: MonitorStore
    let group: ProcessGroup?
    let row: ProcessRow?
    let onClose: (ProcessGroup, TerminationMode) -> Void
    let onRestart: (ProcessGroup) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let target = target {
                content(target)
            } else {
                Text("Selecione um processo para ver os detalhes.").foregroundStyle(Theme.muted).font(.system(size: 12))
            }
            Spacer()
        }
        .padding(14)
        .frame(width: 280)
        .frame(maxHeight: .infinity)
        .background(Theme.panel)
        .overlay(alignment: .leading) { Theme.line.frame(width: 1) }
    }

    private var target: (group: ProcessGroup, primary: ProcessRow)? {
        if let row { return (ProcessWindowModel.single(row), row) }
        if let group, let first = group.rows.first { return (group, first) }
        return nil
    }

    @ViewBuilder
    private func content(_ t: (group: ProcessGroup, primary: ProcessRow)) -> some View {
        let r = t.primary
        let isSingle = row != nil || t.group.rows.count == 1
        let suspect = store.suspects.first { s in t.group.rows.contains { $0.id == s.id } }
        HStack(spacing: 10) {
            AppIcon(title: t.group.title, appPath: r.identified.appBundlePath, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(isSingle && row != nil ? r.snapshot.name : t.group.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                Text(description(t.group, r)).foregroundStyle(Theme.muted).font(.system(size: 11.5)).lineLimit(2)
            }
        }
        if let runaway = store.runaways.first(where: { r in t.group.rows.contains { $0.id == r.id } }) {
            Text(runaway.hint).font(.system(size: 11.5)).foregroundStyle(Theme.bad)
                .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bad.opacity(0.10)))
                .padding(.top, 12)
        }
        if let suspect {
            Text(suspect.hint).font(.system(size: 11.5)).foregroundStyle(Theme.warn)
                .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.warn.opacity(0.10)))
                .padding(.top, 12)
        }
        Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 7) {
            if let p = r.identified.project { field("Projeto", p) }
            if let cwd = r.snapshot.cwd { field("Pasta", abbreviate(cwd), muted: true) }
            if !r.ports.isEmpty { field("Porta", r.ports.map(String.init).joined(separator: ", ")) }
            field("Iniciado", started(t.group.oldestStart))
            field("Memória", Format.bytes(isSingle ? r.snapshot.footprintBytes : t.group.footprintBytes))
            field("CPU", Format.cpu(isSingle ? r.cpuPercent : t.group.cpuPercent, cores: ProcessInfo.processInfo.activeProcessorCount) + " do Mac")
            if isSingle {
                field("Pai", parent(r))
                field("PID", String(r.id))
                if r.snapshot.state == .stopped { field("Estado", "Suspenso (Ctrl+Z)") }
            } else {
                field("Processos", String(t.group.rows.count))
            }
        }
        .font(.system(size: 12))
        .padding(.top, 12)
        if r.identified.kind == .claudeSession {
            let sessions = (isSingle ? [r] : t.group.rows).filter { $0.identified.kind == .claudeSession }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(sessions) { session in
                    let cost = store.sessionCost(session.snapshot)
                    Text("Custo total da sessão\(sessions.count > 1 ? " " + (session.identified.project ?? String(session.id)) : ""): \(Format.bytes(cost.totalBytes))")
                        .fontWeight(.semibold)
                    ForEach(Array(cost.parts.enumerated()), id: \.offset) { _, part in
                        HStack {
                            Text(part.title).foregroundStyle(Theme.muted)
                            Spacer()
                            Text(Format.bytes(part.bytes)).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            .font(.system(size: 11.5))
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(0.08)))
            .padding(.top, 12)
        }
        let plan = store.plan(for: t.group, mode: .normal)
        let blocked: String? = if case .notAllowed(let reason) = plan { reason } else { nil }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
            Button { onClose(t.group, .normal) } label: { Text("Fechar").frame(maxWidth: .infinity) }
                .buttonStyle(PillButton(color: Theme.bad)).disabled(blocked != nil)
            Button { onClose(t.group, .force) } label: { Text("Forçar").frame(maxWidth: .infinity) }
                .buttonStyle(PillButton()).disabled(blocked != nil)
            if case .quitApp = plan {
                Button { onRestart(t.group) } label: { Text("Reiniciar").frame(maxWidth: .infinity) }
                    .buttonStyle(PillButton())
            }
            Button { if let cwd = r.snapshot.cwd { NSWorkspace.shared.open(URL(fileURLWithPath: cwd)) } } label: { Text("Abrir pasta").frame(maxWidth: .infinity) }
                .buttonStyle(PillButton()).disabled(r.snapshot.cwd == nil)
        }
        .padding(.top, 16)
        if let blocked { Text(blocked).font(.system(size: 11)).foregroundStyle(Theme.muted).padding(.top, 6) }
        Toggle("Sempre ignorar este processo", isOn: Binding(
            get: { store.ignore.contains(.of(r)) },
            set: { on in
                if on { store.ignore.add(.of(r), label: t.group.title) } else { store.ignore.remove(.of(r)) }
                Task { await store.refresh() }
            }))
            .toggleStyle(.checkbox).font(.system(size: 11)).foregroundStyle(Theme.muted).padding(.top, 10)
    }

    private func field(_ k: String, _ v: String, muted: Bool = false) -> some View {
        GridRow {
            Text(k).foregroundStyle(Theme.muted).frame(width: 70, alignment: .leading)
            Text(v).foregroundStyle(muted ? Theme.muted : Theme.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func description(_ g: ProcessGroup, _ r: ProcessRow) -> String {
        switch g.kind {
        case .devServer: "Servidor de desenvolvimento · \(r.identified.title)"
        case .claudeSession: g.rows.count > 1 ? "\(g.rows.count) sessões do Claude Code" : "Sessão do Claude Code"
        case .mcpServer: "Servidor MCP (ferramenta do Claude)"
        case .appProcess: g.rows.count > 1 ? "App com \(g.rows.count) processos" : "App"
        case .shell: "Terminal"
        case .database: "Banco de dados"
        case .system: "Processo do sistema"
        case .other: r.snapshot.arguments.joined(separator: " ").isEmpty ? r.snapshot.name : r.snapshot.arguments.joined(separator: " ")
        }
    }

    private func started(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "dd/MM 'às' HH:mm"
        return "\(f.string(from: d)) · \(Format.age(since: d, now: store.now))"
    }

    private func parent(_ r: ProcessRow) -> String {
        let p = store.allSnapshots.first { $0.id == r.snapshot.ppid }
        let name = r.snapshot.ppid == 1 ? "launchd (órfão)" : p?.name ?? "PID \(r.snapshot.ppid)"
        return [name, r.snapshot.ttyName].compactMap { $0 }.joined(separator: " · ")
    }

    private func abbreviate(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
