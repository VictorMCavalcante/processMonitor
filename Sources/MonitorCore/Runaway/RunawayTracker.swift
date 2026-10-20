import Foundation

public enum RunawayReason: Sendable, Equatable {
    case cpu(minutes: Int)
    case memory(from: UInt64, to: UInt64, minutes: Int)
}

public struct Runaway: Sendable, Identifiable, Equatable {
    public var id: Int32 { row.id }
    public var row: ProcessRow
    public var reason: RunawayReason

    public init(row: ProcessRow, reason: RunawayReason) {
        self.row = row
        self.reason = reason
    }

    public var hint: String {
        switch reason {
        case .cpu(let minutes): "CPU acima de 80% há \(minutes) min."
        case .memory(let from, let to, let minutes): "Memória cresceu de \(Format.bytes(from)) para \(Format.bytes(to)) em \(minutes) min."
        }
    }
}

public struct RunawayTracker: Sendable {
    public static let cpuThreshold = 80.0
    public static let cpuDuration: TimeInterval = 300
    public static let memoryDuration: TimeInterval = 1800
    public static let memoryRatio = 1.5
    public static let memoryMinimumGrowth: UInt64 = 500 * 1_048_576
    public static let memoryDropTolerance = 0.05
    private static let buildMarkers = ["gradle", "kotlin-daemon", "bazel", "cargo", "swift-build", "tsc --watch", "rustc", "clang"]

    private struct State: Sendable {
        var cpuSince: Date?
        var memoryStart: (at: Date, bytes: UInt64)
        var memoryLast: UInt64
    }

    private var states: [String: State] = [:]

    public init() {}

    public mutating func update(_ rows: [ProcessRow], at now: Date, myUid: UInt32, ignore: IgnoreList) -> [Runaway] {
        var next: [String: State] = [:]
        var found: [Runaway] = []
        for row in rows {
            guard row.snapshot.uid == myUid, row.identified.kind != .system, !ignore.contains(.of(row)) else { continue }
            let key = "\(row.id):\(row.snapshot.startTime.timeIntervalSince1970)"
            let bytes = row.snapshot.footprintBytes
            var state = states[key] ?? State(cpuSince: nil, memoryStart: (now, bytes), memoryLast: bytes)
            if row.cpuPercent >= Self.cpuThreshold {
                if state.cpuSince == nil { state.cpuSince = now }
            } else {
                state.cpuSince = nil
            }
            if Double(bytes) < Double(state.memoryLast) * (1 - Self.memoryDropTolerance) {
                state.memoryStart = (now, bytes)
            }
            state.memoryLast = bytes
            next[key] = state
            if let since = state.cpuSince, now.timeIntervalSince(since) >= Self.cpuDuration, !isBuildDaemon(row) {
                found.append(Runaway(row: row, reason: .cpu(minutes: Int(now.timeIntervalSince(since) / 60))))
                continue
            }
            let elapsed = now.timeIntervalSince(state.memoryStart.at)
            let start = state.memoryStart.bytes
            if elapsed >= Self.memoryDuration, start > 0, Double(bytes) >= Double(start) * Self.memoryRatio, bytes >= start + Self.memoryMinimumGrowth {
                found.append(Runaway(row: row, reason: .memory(from: start, to: bytes, minutes: Int(elapsed / 60))))
            }
        }
        states = next
        return found
    }

    private func isBuildDaemon(_ row: ProcessRow) -> Bool {
        let text = ([row.snapshot.name] + row.snapshot.arguments).joined(separator: " ").lowercased()
        return Self.buildMarkers.contains { text.contains($0) }
    }
}
