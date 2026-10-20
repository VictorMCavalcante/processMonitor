import Foundation

public struct PeakItem: Codable, Sendable, Equatable {
    public var title: String
    public var bytes: UInt64

    public init(title: String, bytes: UInt64) {
        self.title = title
        self.bytes = bytes
    }
}

public struct PeakEpisode: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var start: Date
    public var end: Date?
    public var maxLevel: Int
    public var maxPressure: Int
    public var top: [PeakItem]

    public init(id: UUID, start: Date, end: Date?, maxLevel: Int, maxPressure: Int, top: [PeakItem]) {
        self.id = id
        self.start = start
        self.end = end
        self.maxLevel = maxLevel
        self.maxPressure = maxPressure
        self.top = top
    }
}

public struct PeakRecorder: Sendable {
    public static let retention: TimeInterval = 7 * 86_400
    public static let topCount = 5
    public private(set) var episodes: [PeakEpisode]

    public init(episodes: [PeakEpisode] = []) {
        self.episodes = episodes
    }

    public mutating func update(stats: SystemStats, groups: [ProcessGroup], at now: Date) -> Bool {
        let openIndex = episodes.lastIndex { $0.end == nil }
        if stats.level == .normal {
            guard let i = openIndex else { return false }
            episodes[i].end = now
            return true
        }
        let top = groups.sorted { $0.footprintBytes > $1.footprintBytes }.prefix(Self.topCount).map { PeakItem(title: $0.title, bytes: $0.footprintBytes) }
        guard let i = openIndex else {
            episodes.append(PeakEpisode(id: UUID(), start: now, end: nil, maxLevel: stats.level.rawValue, maxPressure: stats.pressurePercent, top: Array(top)))
            return true
        }
        var changed = false
        if stats.level.rawValue > episodes[i].maxLevel {
            episodes[i].maxLevel = stats.level.rawValue
            changed = true
        }
        if stats.pressurePercent > episodes[i].maxPressure {
            episodes[i].maxPressure = stats.pressurePercent
            episodes[i].top = Array(top)
            changed = true
        }
        return changed
    }

    public mutating func prune(now: Date) {
        episodes.removeAll { now.timeIntervalSince($0.end ?? $0.start) > Self.retention && $0.end != nil }
    }
}

public struct PeakStore: Sendable {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Monitor", isDirectory: true)
            .appendingPathComponent("peaks.json")
    }

    public func load() -> [PeakEpisode] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([PeakEpisode].self, from: data)) ?? []
    }

    public func save(_ episodes: [PeakEpisode]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(episodes) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
