import Foundation

public struct ProcessRow: Sendable, Identifiable, Equatable {
    public var id: Int32 { snapshot.id }
    public var snapshot: ProcessSnapshot
    public var identified: Identified
    public var cpuPercent: Double
    public var ports: [UInt16]
    public var gpuPercent: Double
    public var milliwatts: Double
    public var wakeupsPerSecond: Double

    public init(snapshot: ProcessSnapshot, identified: Identified, cpuPercent: Double, ports: [UInt16], gpuPercent: Double = 0, milliwatts: Double = 0, wakeupsPerSecond: Double = 0) {
        self.snapshot = snapshot
        self.identified = identified
        self.cpuPercent = cpuPercent
        self.ports = ports
        self.gpuPercent = gpuPercent
        self.milliwatts = milliwatts
        self.wakeupsPerSecond = wakeupsPerSecond
    }
}

public enum GroupSort: Sendable, Hashable {
    case memory
    case cpu
    case gpu
    case energy
}

extension GroupSort {
    func value(_ r: ProcessRow) -> Double {
        switch self {
        case .memory: Double(r.snapshot.footprintBytes)
        case .cpu: r.cpuPercent
        case .gpu: r.gpuPercent
        case .energy: r.milliwatts
        }
    }

    func value(_ g: ProcessGroup) -> Double {
        switch self {
        case .memory: Double(g.footprintBytes)
        case .cpu: g.cpuPercent
        case .gpu: g.gpuPercent
        case .energy: g.milliwatts
        }
    }
}

public enum GroupingMode: String, Sendable, CaseIterable {
    case byApp
    case byProject
    case flat
}

public struct ProcessGroup: Sendable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var kind: ProcessKind
    public var rows: [ProcessRow]
    public var footprintBytes: UInt64
    public var cpuPercent: Double
    public var gpuPercent: Double
    public var milliwatts: Double
    public var wakeupsPerSecond: Double
    public var oldestStart: Date

    public init(id: String, title: String, subtitle: String?, kind: ProcessKind, rows: [ProcessRow], sort: GroupSort = .memory) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.rows = rows.sorted { sort.value($0) > sort.value($1) }
        footprintBytes = rows.reduce(0) { $0 + $1.snapshot.footprintBytes }
        cpuPercent = rows.reduce(0) { $0 + $1.cpuPercent }
        gpuPercent = rows.reduce(0) { $0 + $1.gpuPercent }
        milliwatts = rows.reduce(0) { $0 + $1.milliwatts }
        wakeupsPerSecond = rows.reduce(0) { $0 + $1.wakeupsPerSecond }
        oldestStart = rows.map(\.snapshot.startTime).min() ?? Date()
    }
}

public enum Grouping {
    public static func group(_ rows: [ProcessRow], mode: GroupingMode, sort: GroupSort = .memory) -> [ProcessGroup] {
        var buckets: [String: [ProcessRow]] = [:]
        var order: [String] = []
        for row in rows {
            let key = key(for: row, mode: mode)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(row)
        }
        return order.map { makeGroup(id: $0, rows: buckets[$0]!, sort: sort) }
            .sorted { sort.value($0) != sort.value($1) ? sort.value($0) > sort.value($1) : $0.title < $1.title }
    }

    private static func key(for row: ProcessRow, mode: GroupingMode) -> String {
        let id = row.identified
        switch mode {
        case .flat:
            return "pid:\(row.id)"
        case .byProject:
            if let project = id.project { return "project:\(project)" }
            return key(for: row, mode: .byApp)
        case .byApp:
            if let app = id.appBundlePath { return "app:\(app)" }
            switch id.kind {
            case .claudeSession: return "kind:\(id.kind.rawValue)"
            case .mcpServer: return "kind:\(id.kind.rawValue):\(id.title)"
            case .devServer: return "dev:\(id.project ?? "pid\(row.id)")"
            default: return "pid:\(row.id)"
            }
        }
    }

    private static func makeGroup(id: String, rows: [ProcessRow], sort: GroupSort) -> ProcessGroup {
        let first = rows[0].identified
        if id.hasPrefix("project:") {
            let project = String(id.dropFirst("project:".count))
            let kinds = Set(rows.map(\.identified.kind))
            return ProcessGroup(id: id, title: project, subtitle: summary(rows), kind: kinds.count == 1 ? first.kind : .other, rows: rows, sort: sort)
        }
        if id.hasPrefix("kind:"), first.kind == .claudeSession {
            return ProcessGroup(id: id, title: first.title, subtitle: rows.count == 1 ? first.subtitle : "\(rows.count) sessões", kind: first.kind, rows: rows, sort: sort)
        }
        if id.hasPrefix("dev:") {
            return ProcessGroup(id: id, title: first.project ?? first.title, subtitle: first.title + (rows.count > 1 ? " · \(rows.count) processos" : ""), kind: .devServer, rows: rows, sort: sort)
        }
        let subtitle = rows.count > 1 ? "\(rows.count) processos" : first.subtitle
        return ProcessGroup(id: id, title: first.title, subtitle: subtitle, kind: first.kind, rows: rows, sort: sort)
    }

    private static func summary(_ rows: [ProcessRow]) -> String {
        let titles = Array(Set(rows.map(\.identified.title))).sorted()
        return titles.prefix(3).joined(separator: ", ") + (titles.count > 3 ? "…" : "")
    }
}
