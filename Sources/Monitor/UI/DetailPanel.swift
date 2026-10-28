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
                overview
            }
            Spacer()
        }
        .padding(14)
        .frame(width: 280)
        .frame(maxHeight: .infinity)
        .background(Theme.glass ? .clear : Theme.panel)
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
            field("GPU", Format.cpu(isSingle ? r.gpuPercent : t.group.gpuPercent, cores: 1) + " da GPU")
            if isSingle {
                field("Pai", parent(r))
                field("PID", String(r.id))
                if let path = r.snapshot.executablePath { field("Caminho", abbreviate(path), muted: true) }
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

    private var overview: some View {
        let groups = Grouping.group(store.rows, mode: .byApp)
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let cpu = groups.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(4).filter { $0.cpuPercent >= 0.5 }
        let grew = groups.compactMap { g -> (ProcessGroup, Int64)? in
            guard let before = store.growthBaseline[g.id] else { return nil }
            let delta = Int64(g.footprintBytes) - Int64(before)
            return delta >= 20 << 20 ? (g, delta) : nil
        }.sorted { $0.1 > $1.1 }.prefix(4)
        let minutes = max(1, Int(store.now.timeIntervalSince(store.growthSince) / 60))
        return VStack(alignment: .leading, spacing: 18) {
            section("Mais CPU agora", color: Theme.chart["cpu"] ?? Theme.accent) {
                if cpu.isEmpty { empty("Tudo em repouso") }
                let top = max(cpu.first?.cpuPercent ?? 1, 1)
                ForEach(Array(cpu)) { g in
                    bar(g, value: Format.cpu(g.cpuPercent, cores: cores), fraction: g.cpuPercent / top, color: Theme.chart["cpu"] ?? Theme.accent)
                }
            }
            section("Mais cresceu · \(minutes) min", color: Theme.chart["used"] ?? Theme.accent) {
                if grew.isEmpty { empty("Nada cresceu mais de 20 MB") }
                let top = Double(grew.first?.1 ?? 1)
                ForEach(Array(grew), id: \.0.id) { g, delta in
                    bar(g, value: "+" + Format.bytes(UInt64(delta)), fraction: Double(delta) / top, color: Theme.chart["used"] ?? Theme.accent)
                }
            }
            if let peak = store.peaks.last {
                section("Último pico", color: PeakText.color(peak.maxLevel)) {
                    HStack(spacing: 6) {
                        Chip(icon: "bolt.fill", text: PeakText.when(peak.start, now: store.now), color: PeakText.color(peak.maxLevel))
                        Chip(icon: "gauge.with.dots.needle.67percent", text: "\(peak.maxPressure)%", color: PeakText.color(peak.maxLevel))
                    }
                    ForEach(peak.top.prefix(3), id: \.title) { item in
                        HStack {
                            Text(item.title).lineLimit(1)
                            Spacer()
                            Text(Format.bytes(item.bytes)).foregroundStyle(Theme.muted).monospacedDigit()
                        }
                        .font(.system(size: 11.5))
                    }
                }
            }
            Text("Selecione um processo para ver os detalhes.").foregroundStyle(Theme.muted2).font(.system(size: 11))
        }
    }

    private func section<Content: View>(_ title: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.muted)
            }
            content()
        }
    }

    private func bar(_ g: ProcessGroup, value: String, fraction: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            AppIcon(title: g.title, appPath: g.rows.first?.identified.appBundlePath, size: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(g.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer()
                    Text(value).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.muted)
                }
                Meter(fraction: fraction, color: color, height: 3)
            }
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text).font(.system(size: 11.5)).foregroundStyle(Theme.muted2)
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
