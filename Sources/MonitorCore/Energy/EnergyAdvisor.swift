import Foundation

public enum SuggestionAction: Sendable, Equatable {
    case close(groupID: String)
    case closeOwner(pid: Int32)
    case copy(String)
}

public struct EnergySuggestion: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var savingMilliwatts: Double?
    public var action: SuggestionAction

    public init(id: String, title: String, detail: String, savingMilliwatts: Double?, action: SuggestionAction) {
        self.id = id
        self.title = title
        self.detail = detail
        self.savingMilliwatts = savingMilliwatts
        self.action = action
    }
}

public enum EnergyAdvisor {
    public static func reason(_ g: ProcessGroup, blockers: [SleepBlocker], now: Date) -> String {
        let factors: [(ratio: Double, text: String)] = [
            (g.cpuPercent / 50, "CPU alta (\(Int(g.cpuPercent))%)"),
            (g.gpuPercent / 20, "GPU (\(Int(g.gpuPercent))%)"),
            (g.wakeupsPerSecond / 100, "acorda a CPU \(Int(g.wakeupsPerSecond))×/s")
        ]
        if let top = factors.filter({ $0.ratio > 1 }).max(by: { $0.ratio < $1.ratio }) { return top.text }
        let pids = Set(g.rows.map(\.id))
        if blockers.contains(where: { pids.contains($0.ownerPid) }) { return "impede o Mac de dormir" }
        if g.kind == .devServer || g.kind == .database, now.timeIntervalSince(g.oldestStart) > 4 * 3600, g.cpuPercent < 1 {
            return "rodando há \(Format.age(since: g.oldestStart, now: now)) sem uso"
        }
        return "uso leve"
    }

    public static func suggestions(groups: [ProcessGroup], runaways: [Runaway], blockers: [SleepBlocker], log: PowerLogSummary, onBattery: Bool, quietSince: [Int32: Date], now: Date) -> [EnergySuggestion] {
        var result: [EnergySuggestion] = []
        for g in groups where g.milliwatts > 500 {
            guard let runaway = runaways.first(where: { r in g.rows.contains { $0.id == r.row.id } }) else { continue }
            result.append(EnergySuggestion(id: "runaway:\(g.id)", title: "Fechar \(g.title)", detail: runaway.hint, savingMilliwatts: g.milliwatts, action: .close(groupID: g.id)))
        }
        for b in blockers {
            guard let since = b.since, now.timeIntervalSince(since) > 1800,
                  let quiet = quietSince[b.ownerPid], now.timeIntervalSince(quiet) > 1800 else { continue }
            result.append(EnergySuggestion(id: "blocker:\(b.id)", title: b.title, detail: "há \(Format.age(since: since, now: now))", savingMilliwatts: nil, action: .closeOwner(pid: b.ownerPid)))
        }
        if onBattery {
            for g in groups where (g.kind == .devServer || g.kind == .database) && now.timeIntervalSince(g.oldestStart) > 8 * 3600 {
                result.append(EnergySuggestion(id: "long:\(g.id)", title: "\(g.title) ligado há \(Format.age(since: g.oldestStart, now: now))", detail: "Feche se não estiver usando", savingMilliwatts: g.milliwatts, action: .close(groupID: g.id)))
            }
        }
        let network = log.wakes[.network] ?? 0
        if network >= 50 {
            result.append(EnergySuggestion(id: "network-wakes", title: "O Mac acordou \(network)× pela rede enquanto dormia", detail: "Ajustes › Bateria › Opções › Acordar para acesso à rede: Nunca na bateria", savingMilliwatts: nil, action: .copy("sudo pmset -b tcpkeepalive 0")))
        }
        var seen: Set<String> = []
        result = result.filter { s in
            guard case .close(let id) = s.action else { return true }
            return seen.insert(id).inserted
        }
        return Array(result.prefix(4))
    }
}
