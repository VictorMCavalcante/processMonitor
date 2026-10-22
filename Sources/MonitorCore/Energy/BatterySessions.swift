import Foundation

public struct EnergyItem: Codable, Sendable, Equatable {
    public var title: String
    public var milliwattHours: Double

    public init(title: String, milliwattHours: Double) {
        self.title = title
        self.milliwattHours = milliwattHours
    }
}

public struct BatterySession: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var start: Date
    public var end: Date?
    public var startPercent: Int
    public var endPercent: Int
    public var awakeSeconds: Double
    public var top: [EnergyItem]
    public var reconstructed: Bool

    public init(id: UUID, start: Date, end: Date?, startPercent: Int, endPercent: Int, awakeSeconds: Double, top: [EnergyItem], reconstructed: Bool) {
        self.id = id
        self.start = start
        self.end = end
        self.startPercent = startPercent
        self.endPercent = endPercent
        self.awakeSeconds = awakeSeconds
        self.top = top
        self.reconstructed = reconstructed
    }

    public var drainPerHour: Double? {
        awakeSeconds < 900 ? nil : Double(startPercent - endPercent) / (awakeSeconds / 3600)
    }
}

public struct SessionRecorder: Sendable {
    public static let limit = 60
    public static let saveEvery: TimeInterval = 300
    public private(set) var sessions: [BatterySession]
    private var totals: [String: Double]
    private var lastSave: Date?

    public init(sessions: [BatterySession]) {
        self.sessions = sessions
        let open = sessions.last { $0.end == nil }
        totals = Dictionary(open?.top.map { ($0.title, $0.milliwattHours) } ?? [], uniquingKeysWith: +)
    }

    public mutating func update(battery: BatteryReading, groups: [ProcessGroup], at now: Date, interval: TimeInterval) -> Bool {
        let openIndex = sessions.lastIndex { $0.end == nil }
        guard battery.onBattery else {
            guard let i = openIndex else { return false }
            sessions[i].end = now
            sessions[i].endPercent = battery.percent
            totals = [:]
            lastSave = nil
            return true
        }
        guard let i = openIndex else {
            sessions.append(BatterySession(id: UUID(), start: now, end: nil, startPercent: battery.percent, endPercent: battery.percent, awakeSeconds: 0, top: [], reconstructed: false))
            totals = [:]
            lastSave = now
            trim()
            return true
        }
        sessions[i].awakeSeconds += interval
        sessions[i].endPercent = battery.percent
        for g in groups { totals[g.title, default: 0] += g.milliwatts * interval / 3600 }
        sessions[i].top = totals.sorted { $0.value > $1.value }.prefix(5).map { EnergyItem(title: $0.key, milliwattHours: $0.value) }
        guard now.timeIntervalSince(lastSave ?? sessions[i].start) >= Self.saveEvery else { return false }
        lastSave = now
        return true
    }

    public mutating func merge(_ log: [PowerLogSession]) {
        for l in log where !sessions.contains(where: { l.start < ($0.end ?? .distantFuture) && $0.start < l.end }) {
            sessions.append(BatterySession(id: UUID(), start: l.start, end: l.end, startPercent: l.startPercent, endPercent: l.endPercent,
                                           awakeSeconds: l.end.timeIntervalSince(l.start), top: [], reconstructed: true))
        }
        sessions.sort { $0.start < $1.start }
        trim()
    }

    private mutating func trim() {
        if sessions.count > Self.limit { sessions.removeFirst(sessions.count - Self.limit) }
    }
}

public struct BatterySessionStore: Sendable {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Monitor", isDirectory: true)
            .appendingPathComponent("battery-sessions.json")
    }

    public func load() -> [BatterySession] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([BatterySession].self, from: data)) ?? []
    }

    public func save(_ sessions: [BatterySession]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(sessions) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

public enum SessionInsight {
    public static func compare(_ s: BatterySession, history: [BatterySession]) -> String? {
        let others = history.filter { !$0.reconstructed && $0.id != s.id && $0.drainPerHour != nil }
        guard let drain = s.drainPerHour, !others.isEmpty else { return nil }
        let count = Double(others.count)
        let average = others.compactMap(\.drainPerHour).reduce(0, +) / count
        guard average > 0, drain >= 1.5 * average else { return nil }
        let factor = String(format: "%.1f", drain / average).replacingOccurrences(of: ".", with: ",")
        var usual: [String: Double] = [:]
        for item in others.flatMap(\.top) { usual[item.title, default: 0] += item.milliwattHours / count }
        let titles = s.top.map { ($0.title, $0.milliwattHours - usual[$0.title, default: 0]) }
            .filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(2).map(\.0)
        let text = "Esta sessão gastou \(factor)× mais que a sua média"
        return titles.isEmpty ? text : "\(text); principais diferenças: \(titles.joined(separator: ", "))"
    }
}
