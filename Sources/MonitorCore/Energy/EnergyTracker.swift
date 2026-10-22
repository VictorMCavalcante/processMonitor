import Foundation

public struct EnergyRate: Sendable, Equatable {
    public var milliwatts: Double
    public var wakeupsPerSecond: Double

    public init(milliwatts: Double, wakeupsPerSecond: Double) {
        self.milliwatts = milliwatts
        self.wakeupsPerSecond = wakeupsPerSecond
    }
}

public struct EnergyTracker: Sendable {
    private struct Entry: Sendable {
        var start: Date
        var history: [(at: Date, nj: UInt64)]
        var wakeups: UInt64
    }

    private let window: TimeInterval
    private var entries: [Int32: Entry] = [:]

    public init(window: TimeInterval = 600) {
        self.window = window
    }

    public mutating func update(_ snaps: [ProcessSnapshot], at now: Date) -> [Int32: EnergyRate] {
        var result: [Int32: EnergyRate] = [:]
        var next: [Int32: Entry] = [:]
        let cutoff = now.addingTimeInterval(-window)
        for s in snaps where s.energyNj > 0 {
            guard var e = entries[s.id], e.start == s.startTime, let last = e.history.last,
                  s.energyNj >= last.nj, now > last.at else {
                result[s.id] = EnergyRate(milliwatts: 0, wakeupsPerSecond: 0)
                next[s.id] = Entry(start: s.startTime, history: [(now, s.energyNj)], wakeups: s.wakeups)
                continue
            }
            e.history.append((now, s.energyNj))
            while e.history.count > 2, e.history[1].at < cutoff { e.history.removeFirst() }
            let base = e.history[0]
            let mw = Double(s.energyNj - base.nj) / now.timeIntervalSince(base.at) / 1e6
            let wk = s.wakeups >= e.wakeups ? Double(s.wakeups - e.wakeups) / now.timeIntervalSince(last.at) : 0
            e.wakeups = s.wakeups
            result[s.id] = EnergyRate(milliwatts: mw, wakeupsPerSecond: wk)
            next[s.id] = e
        }
        entries = next
        return result
    }
}
