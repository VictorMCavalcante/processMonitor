import Foundation

public struct GPUTracker: Sendable {
    private var last: [Int32: (start: Date?, gpu: UInt64, at: Date)] = [:]

    public init() {}

    public mutating func update(_ perPid: [Int32: UInt64], starts: [Int32: Date], at now: Date) -> [Int32: Double] {
        var result: [Int32: Double] = [:]
        var next: [Int32: (start: Date?, gpu: UInt64, at: Date)] = [:]
        for (pid, gpu) in perPid {
            let start = starts[pid]
            if let prev = last[pid], prev.start == start, gpu >= prev.gpu, now > prev.at {
                result[pid] = min(100, Double(gpu - prev.gpu) / now.timeIntervalSince(prev.at) / 1e9 * 100)
            } else {
                result[pid] = 0
            }
            next[pid] = (start, gpu, now)
        }
        last = next
        return result
    }
}
