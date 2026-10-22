import AppKit
import MonitorCore
import SwiftUI

enum BatteryText {
    static func watts(_ mw: Double) -> String {
        "~\(Int((mw / 1000).rounded())) W"
    }

    static func forecast(_ minutes: Int?) -> String {
        guard let m = minutes else { return "calculando…" }
        return m < 60 ? "~\(m) min" : "~\(m / 60)h\(String(format: "%02d", m % 60))"
    }

    static func state(_ b: BatteryReading) -> String {
        if b.onBattery { return "na bateria" }
        if b.fullyCharged { return "carregada" }
        return b.charging ? "carregando" : "na tomada"
    }

    static func decimal(_ v: Double) -> String {
        String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }
}

struct BatteryView: View {
    let store: MonitorStore
    let onClose: (ProcessGroup, Bool) -> Void
    @State private var energyMode = GroupingMode.byApp

    var body: some View {
        let groups = store.energyGroups
        let shown = (energyMode == .byApp ? groups : Grouping.group(store.rows, mode: energyMode, sort: .energy)).filter { $0.milliwatts > 0 }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                cards
                consumers(shown)
                blockers
                suggestions(groups)
                if store.battery != nil {
                    sessions
                    sleep
                }
            }
        }
        .font(.system(size: 12.5))
    }

    private var cards: some View {
        let b = store.battery
        return HStack(spacing: 10) {
            if let b {
                card("Carga", "\(b.percent)%", note: BatteryText.state(b))
            }
            card("Potência", store.averageSystemMilliwatts.map(BatteryText.watts) ?? "–", note: "Mac inteiro · média de 10 min")
            card("Previsão", b?.onBattery == true ? BatteryText.forecast(store.minutesLeft) : "–", note: b?.onBattery == true ? "no ritmo dos últimos 10 min" : "na tomada")
            if let b {
                card("Saúde", (store.appleHealth ?? b.healthPercent).map { "\($0)%" } ?? "–", note: health(b))
                    .help(b.fullMah.flatMap { cap in b.designMah.map { "Segura \(cap) de \($0) mAh (\(b.healthPercent ?? 0)%, estimado)" } } ?? "")
            }
        }
    }

    private func health(_ b: BatteryReading) -> String {
        let source = store.appleHealth != nil ? "Apple" : b.healthPercent != nil ? "estimado" : nil
        return [source, b.cycles.map { "\($0) ciclos" }, b.temperatureC.map { "\(Int($0.rounded())) °C" }].compactMap { $0 }.joined(separator: " · ")
    }

    private func card(_ title: String, _ value: String, note: String?) -> some View {
        StatCard(title: title, value: value, note: note)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased()).font(.system(size: 10.5)).foregroundStyle(Theme.muted2)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.panel2)
            content()
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func line<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .font(.system(size: 12))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .overlay(alignment: .top) { Theme.line.frame(height: 1) }
    }

    private func empty(_ text: String) -> some View {
        line { Text(text).foregroundStyle(Theme.muted) }
    }

    private func consumers(_ groups: [ProcessGroup]) -> some View {
        let total = groups.reduce(0) { $0 + $1.milliwatts }
        return section("Quem está gastando agora") {
            line {
                Picker("", selection: $energyMode) {
                    Text("Por app").tag(GroupingMode.byApp)
                    Text("Por projeto").tag(GroupingMode.byProject)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
            }
            ForEach(groups.prefix(12)) { g in
                line {
                    AppIcon(title: g.title, appPath: g.rows.first?.identified.appBundlePath).frame(width: 22)
                    Text(g.title).fontWeight(.semibold).lineLimit(1)
                    Text(EnergyAdvisor.reason(g, blockers: store.sleepBlockers ?? [], now: store.now)).foregroundStyle(Theme.muted).lineLimit(1)
                    Spacer()
                    Text("~\(Int(g.milliwatts.rounded())) mW").frame(width: 90, alignment: .trailing)
                    Text(total > 0 ? "\(Int((g.milliwatts / total * 100).rounded()))%" : "–").foregroundStyle(Theme.muted).frame(width: 44, alignment: .trailing)
                    CloseButton(store: store, group: g) { onClose(g, false) }.frame(width: 22)
                }
            }
            if groups.isEmpty { empty("Medindo… a energia aparece a partir do segundo ciclo.") }
            if let system = store.averageSystemMilliwatts {
                line {
                    Image(systemName: "display").foregroundStyle(Theme.muted).frame(width: 22)
                    Text("Sistema e tela").fontWeight(.semibold)
                    Tag(text: "estimado", color: Theme.accent)
                    Spacer()
                    Text("~\(Int(max(0, system - total).rounded())) mW").frame(width: 90, alignment: .trailing)
                    Color.clear.frame(width: 44 + 22 + 10, height: 1)
                }
            }
        }
    }

    private var blockers: some View {
        section("Impedindo o Mac de dormir") {
            ForEach(store.sleepBlockers ?? []) { b in
                line {
                    Image(systemName: "moon.zzz").foregroundStyle(Theme.warn).frame(width: 22)
                    Text(b.title).lineLimit(1)
                    if let since = b.since { Text("há \(Format.age(since: since, now: store.now))").foregroundStyle(Theme.muted) }
                    Spacer()
                    if let g = store.ownerGroup(b.ownerPid) {
                        Button("Fechar") { onClose(g, true) }.buttonStyle(PillButton())
                    }
                }
            }
            if let list = store.sleepBlockers {
                if list.isEmpty { empty("Nada impede o Mac de dormir.") }
            } else {
                empty("Lendo…")
            }
        }
    }

    private func suggestions(_ groups: [ProcessGroup]) -> some View {
        let list = store.energySuggestions(groups)
        return section("Como economizar") {
            ForEach(list) { s in
                line {
                    Image(systemName: "leaf").foregroundStyle(Theme.ok).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title).fontWeight(.semibold).lineLimit(1)
                        Text(s.detail + (s.savingMilliwatts.map { " · economia estimada ~\(Int($0.rounded())) mW" } ?? ""))
                            .foregroundStyle(Theme.muted).lineLimit(2).textSelection(.enabled)
                    }
                    Spacer()
                    action(s.action, groups: groups)
                }
            }
            if list.isEmpty { empty("Nenhuma sugestão agora.") }
        }
    }

    @ViewBuilder
    private func action(_ a: SuggestionAction, groups: [ProcessGroup]) -> some View {
        switch a {
        case .close(let id):
            if let g = groups.first(where: { $0.id == id }), isClosable(g) {
                Button("Fechar") { onClose(g, true) }.buttonStyle(PillButton())
            }
        case .closeOwner(let pid):
            if let g = store.ownerGroup(pid) {
                Button("Fechar") { onClose(g, true) }.buttonStyle(PillButton())
            }
        case .copy(let command):
            Button("Copiar comando") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                store.lastMessage = "Comando copiado"
            }
            .buttonStyle(PillButton())
            .help(command)
        }
    }

    private func isClosable(_ g: ProcessGroup) -> Bool {
        if case .notAllowed = store.plan(for: g, mode: .normal) { return false }
        return true
    }

    private var sessions: some View {
        let all = store.batterySessions
        return section("Sessões na bateria") {
            ForEach(all.reversed().prefix(14)) { s in
                line {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(PeakText.when(s.start, now: store.now)).fontWeight(.semibold)
                            Text(Format.age(since: s.start, now: s.end ?? store.now)).foregroundStyle(Theme.muted)
                            Text("\(s.startPercent)%→\(s.endPercent)%")
                            Text(s.drainPerHour.map { "\(BatteryText.decimal($0))%/h" + (s.reconstructed ? "" : " acordado") } ?? "—").foregroundStyle(Theme.muted)
                            if s.end == nil { Tag(text: "em andamento", color: Theme.ok) }
                            if s.reconstructed { Tag(text: "do registro do sistema", color: Theme.accent) }
                        }
                        if !s.top.isEmpty {
                            Text(s.top.prefix(3).map(\.title).joined(separator: " · ")).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                        if let insight = SessionInsight.compare(s, history: all) {
                            Text(insight).foregroundStyle(Theme.warn)
                        }
                    }
                    Spacer()
                }
            }
            if all.isEmpty { empty(store.powerLogLoading ? "Lendo o registro do sistema…" : "Nenhuma sessão na bateria ainda.") }
        }
    }

    private var sleep: some View {
        let log = store.powerLog
        return section("Sono (7 dias)") {
            if log == .empty {
                empty(store.powerLogLoading ? "Lendo o registro do sistema…" : "Sem dados de sono.")
            } else {
                ForEach(log.wakes.sorted { $0.value > $1.value }, id: \.key) { cause, count in
                    line {
                        Text("Despertares: \(cause.title)")
                        Spacer()
                        Text("\(count)×").foregroundStyle(Theme.muted)
                    }
                }
                if log.thermalSleeps > 0 {
                    line {
                        Text("Alertas térmicos durante o sono").foregroundStyle(Theme.warn)
                        Spacer()
                        Text("\(log.thermalSleeps)×").foregroundStyle(Theme.muted)
                    }
                }
                if let drain = log.sleepDrainPerHour {
                    line {
                        Text("Queda da bateria dormindo")
                        Spacer()
                        Text("\(BatteryText.decimal(drain))%/h dormindo").foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }
}
