import Foundation

public struct CPUTracker: Sendable {
    private var last: [Int32: (start: Date, cpu: UInt64, at: Date)] = [:]

    public init() {}

    public mutating func update(_ snaps: [ProcessSnapshot], at now: Date) -> [Int32: Double] {
        var result: [Int32: Double] = [:]
        var next: [Int32: (start: Date, cpu: UInt64, at: Date)] = [:]
        for s in snaps {
            if let prev = last[s.id], prev.start == s.startTime {
                // CPU time never goes backwards for the same process: a lower value is a failed
                // reading (the ps fallback reports 0), so keep the old baseline instead of adopting it.
                guard s.cpuTimeNs >= prev.cpu else {
                    result[s.id] = 0
                    next[s.id] = prev
                    continue
                }
                result[s.id] = now > prev.at ? Double(s.cpuTimeNs - prev.cpu) / now.timeIntervalSince(prev.at) / 1e9 * 100 : 0
            } else {
                result[s.id] = 0
            }
            next[s.id] = (s.startTime, s.cpuTimeNs, now)
        }
        last = next
        return result
    }
}
