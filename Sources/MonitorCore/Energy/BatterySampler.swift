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

    public init(percent: Int, onBattery: Bool, charging: Bool, fullyCharged: Bool, systemMilliwatts: Double?,
                healthPercent: Int?, cycles: Int?, temperatureC: Double?) {
        self.percent = percent
        self.onBattery = onBattery
        self.charging = charging
        self.fullyCharged = fullyCharged
        self.systemMilliwatts = systemMilliwatts
        self.healthPercent = healthPercent
        self.cycles = cycles
        self.temperatureC = temperatureC
    }
}

public enum BatterySampler {
    public static func read() -> BatteryReading? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }
        return parse(dict)
    }

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
            temperatureC: number(p["Temperature"]).map { $0 / 100 }
        )
    }

    private static func number(_ v: Any?) -> Double? {
        (v as? NSNumber)?.doubleValue
    }
}

public struct BatteryForecast: Sendable {
    private var start: Date?
    private var samples: [(at: Date, percent: Int)] = []

    public init() {}

    public mutating func add(percent: Int, onBattery: Bool, at: Date) {
        guard onBattery else {
            start = nil
            samples = []
            return
        }
        if start == nil { start = at }
        samples.append((at, percent))
        samples.removeAll { $0.at < at.addingTimeInterval(-600) }
    }

    public func minutesLeft(now: Date) -> Int? {
        guard let start, now.timeIntervalSince(start) >= 180 else { return nil }
        let window = samples.filter { $0.at >= now.addingTimeInterval(-600) }
        guard let first = window.first, let last = window.last else { return nil }
        let drop = Double(first.percent - last.percent)
        let minutes = last.at.timeIntervalSince(first.at) / 60
        guard drop >= 1, minutes > 0 else { return nil }
        return Int((Double(last.percent) / (drop / minutes)).rounded())
    }
}
