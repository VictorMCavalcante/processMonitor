import Foundation
import IOKit

public struct BatteryReading: Sendable, Equatable {
    public var percent: Int
    public var onBattery: Bool
    public var charging: Bool
    public var fullyCharged: Bool
    public var systemMilliwatts: Double?
    public var healthPercent: Int?
    public var cycles: Int?
    public var temperatureC: Double?
    public var currentMah: Int?
    public var fullMah: Int?
    public var designMah: Int?

    public init(percent: Int, onBattery: Bool, charging: Bool, fullyCharged: Bool, systemMilliwatts: Double?,
                healthPercent: Int?, cycles: Int?, temperatureC: Double?, currentMah: Int? = nil, fullMah: Int? = nil, designMah: Int? = nil) {
        self.percent = percent
        self.onBattery = onBattery
        self.charging = charging
        self.fullyCharged = fullyCharged
        self.systemMilliwatts = systemMilliwatts
        self.healthPercent = healthPercent
        self.cycles = cycles
        self.temperatureC = temperatureC
        self.currentMah = currentMah
        self.fullMah = fullMah
        self.designMah = designMah
    }
}

public enum BatterySampler {
    public static func read() -> BatteryReading? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var dict: [String: Any] = [:]
        for key in keys {
            if let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() { dict[key] = value }
        }
        return parse(dict)
    }

    private static let keys = ["MaxCapacity", "CurrentCapacity", "AppleRawCurrentCapacity", "AppleRawMaxCapacity", "DesignCapacity",
                               "ExternalConnected", "IsCharging", "FullyCharged", "PowerTelemetryData", "CycleCount", "Temperature"]

    static func parse(_ p: [String: Any]) -> BatteryReading? {
        guard let capacity = number(p["MaxCapacity"]) else { return nil }
        let percent: Double
        if capacity == 100, let current = number(p["CurrentCapacity"]) {
            percent = current
        } else if let raw = number(p["AppleRawCurrentCapacity"]), let rawMax = number(p["AppleRawMaxCapacity"]), rawMax > 0 {
            percent = raw * 100 / rawMax
        } else {
            return nil
        }
        let health = number(p["AppleRawMaxCapacity"]).flatMap { raw in
            number(p["DesignCapacity"]).flatMap { $0 > 0 ? Int((raw * 100 / $0).rounded()) : nil }
        }
        return BatteryReading(
            percent: min(100, max(0, Int(percent.rounded()))),
            onBattery: !((p["ExternalConnected"] as? Bool) ?? false),
            charging: (p["IsCharging"] as? Bool) ?? false,
            fullyCharged: (p["FullyCharged"] as? Bool) ?? false,
            systemMilliwatts: number((p["PowerTelemetryData"] as? [String: Any])?["SystemLoad"]),
            healthPercent: health,
            cycles: number(p["CycleCount"]).map { Int($0) },
            temperatureC: number(p["Temperature"]).map { $0 / 100 },
            currentMah: number(p["AppleRawCurrentCapacity"]).map { Int($0) },
            fullMah: number(p["AppleRawMaxCapacity"]).map { Int($0) },
            designMah: number(p["DesignCapacity"]).map { Int($0) }
        )
    }

    private static func number(_ v: Any?) -> Double? {
        (v as? NSNumber)?.doubleValue
    }
}

public enum BatteryHealth {
    public static func parseSystemProfiler(_ text: String) -> Int? {
        guard let match = text.firstMatch(of: /Maximum Capacity: (\d+)%/) else { return nil }
        return Int(match.1)
    }
}

public struct PowerAverage: Sendable {
    private var samples: [(at: Date, milliwatts: Double)] = []

    public init() {}

    public mutating func add(_ milliwatts: Double, at: Date) {
        samples.append((at, milliwatts))
        samples.removeAll { $0.at < at.addingTimeInterval(-600) }
    }

    public func milliwatts(now: Date) -> Double? {
        let window = samples.filter { $0.at >= now.addingTimeInterval(-600) }
        return window.isEmpty ? nil : window.reduce(0) { $0 + $1.milliwatts } / Double(window.count)
    }
}

public struct BatteryForecast: Sendable {
    private var start: Date?
    private var samples: [(at: Date, percent: Int, mah: Int?)] = []
    private var fullMah: Int?

    public init() {}

    public mutating func add(percent: Int, currentMah: Int? = nil, fullMah: Int? = nil, onBattery: Bool, at: Date) {
        guard onBattery else {
            start = nil
            samples = []
            return
        }
        if start == nil { start = at }
        self.fullMah = fullMah
        samples.append((at, percent, currentMah))
        samples.removeAll { $0.at < at.addingTimeInterval(-600) }
    }

    public func minutesLeft(now: Date) -> Int? {
        guard let start, now.timeIntervalSince(start) >= 180 else { return nil }
        let window = samples.filter { $0.at >= now.addingTimeInterval(-600) }
        guard let first = window.first, let last = window.last else { return nil }
        let minutes = last.at.timeIntervalSince(first.at) / 60
        let (left, drop, minDrop): (Double, Double, Double)
        if let a = first.mah, let b = last.mah, let full = fullMah, full > 0 {
            (left, drop, minDrop) = (Double(b), Double(a - b), Double(full) / 100)
        } else {
            (left, drop, minDrop) = (Double(last.percent), Double(first.percent - last.percent), 1)
        }
        guard drop >= minDrop, drop > 0, minutes > 0 else { return nil }
        return Int((left / (drop / minutes)).rounded())
    }
}
