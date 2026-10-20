import Foundation

public struct CPUTracker: Sendable {
    private var last: [Int32: (start: Date, cpu: UInt64, at: Date)] = [:]

    public init() {}

    public mutating func update(_ snaps: [ProcessSnapshot], at now: Date) -> [Int32: Double] {
        var result: [Int32: Double] = [:]
        var next: [Int32: (start: Date, cpu: UInt64, at: Date)] = [:]
        for s in snaps {
            if let prev = last[s.id], prev.start == s.startTime, s.cpuTimeNs >= prev.cpu, now > prev.at {
                result[s.id] = Double(s.cpuTimeNs - prev.cpu) / now.timeIntervalSince(prev.at) / 1e9 * 100
            } else {
                result[s.id] = 0
            }
            next[s.id] = (s.startTime, s.cpuTimeNs, now)
        }
        last = next
        return result
    }
}
