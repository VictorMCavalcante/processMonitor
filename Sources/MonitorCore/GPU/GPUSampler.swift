import Foundation
import IOKit

public struct GPUReading: Sendable, Equatable {
    public var utilization: Double?
    public var memoryInUse: UInt64?
    public var perPid: [Int32: UInt64]

    public init(utilization: Double?, memoryInUse: UInt64?, perPid: [Int32: UInt64]) {
        self.utilization = utilization
        self.memoryInUse = memoryInUse
        self.perPid = perPid
    }
}

public enum GPUSampler {
    public static func read() -> GPUReading? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }
        let accel = IOIteratorNext(iter)
        guard accel != 0 else { return nil }
        defer { IOObjectRelease(accel) }
        let stats = parseStats(property(accel, "PerformanceStatistics") as? [String: Any] ?? [:])
        var clients: [(creator: String, appUsage: [[String: Any]])] = []
        var children: io_iterator_t = 0
        if IORegistryEntryGetChildIterator(accel, kIOServicePlane, &children) == KERN_SUCCESS {
            defer { IOObjectRelease(children) }
            while case let child = IOIteratorNext(children), child != 0 {
                defer { IOObjectRelease(child) }
                guard IOObjectConformsTo(child, "AGXDeviceUserClient") != 0,
                      let creator = property(child, "IOUserClientCreator") as? String else { continue }
                clients.append((creator, property(child, "AppUsage") as? [[String: Any]] ?? []))
            }
        }
        return GPUReading(utilization: stats.utilization, memoryInUse: stats.memoryInUse, perPid: accumulate(clients))
    }

    static func parseStats(_ d: [String: Any]) -> (utilization: Double?, memoryInUse: UInt64?) {
        ((d["Device Utilization %"] as? NSNumber)?.doubleValue, uint64(d["In use system memory"]))
    }

    static func parseCreator(_ s: String) -> Int32? {
        guard s.hasPrefix("pid ") else { return nil }
        return Int32(s.dropFirst(4).prefix { $0.isNumber })
    }

    static func accumulate(_ clients: [(creator: String, appUsage: [[String: Any]])]) -> [Int32: UInt64] {
        var result: [Int32: UInt64] = [:]
        for c in clients {
            guard let pid = parseCreator(c.creator) else { continue }
            result[pid, default: 0] &+= c.appUsage.reduce(0) { $0 &+ (uint64($1["accumulatedGPUTime"]) ?? 0) }
        }
        return result
    }

    private static func uint64(_ v: Any?) -> UInt64? {
        guard let n = v as? NSNumber, n.int64Value >= 0 else { return nil }
        return n.uint64Value
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
