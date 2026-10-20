import Foundation

public enum AlertKind: Equatable, Sendable {
    case pressureRose(PressureLevel)
    case newSuspect(IgnoreKey, title: String)
    case runaway(IgnoreKey, title: String, hint: String)
}

public struct NotificationPolicy: Sendable {
    public static let pressureCooldown: TimeInterval = 600
    private var notifiedLevel: PressureLevel = .normal
    private var lastPressureAlert: Date?
    private var seenSuspects: Set<IgnoreKey> = []

    public init() {}

    private var seenRunaways: Set<IgnoreKey> = []
    private static let runawayPrefix = "runaway:"

    public init(seen: Set<IgnoreKey>) {
        seenSuspects = Set(seen.filter { !$0.raw.hasPrefix(Self.runawayPrefix) })
        seenRunaways = Set(seen.filter { $0.raw.hasPrefix(Self.runawayPrefix) }.map { IgnoreKey(raw: String($0.raw.dropFirst(Self.runawayPrefix.count))) })
    }

    public var seen: Set<IgnoreKey> {
        seenSuspects.union(seenRunaways.map { IgnoreKey(raw: Self.runawayPrefix + $0.raw) })
    }

    public mutating func evaluate(level: PressureLevel, suspects: [Suspect], runaways: [Runaway] = [], now: Date) -> [AlertKind] {
        var alerts: [AlertKind] = []
        if level == .normal {
            notifiedLevel = .normal
        } else if level > notifiedLevel, level == .critical || (lastPressureAlert.map { now.timeIntervalSince($0) >= Self.pressureCooldown } ?? true) {
            notifiedLevel = level
            lastPressureAlert = now
            alerts.append(.pressureRose(level))
        }
        let current = Set(suspects.map { IgnoreKey.of($0.row) })
        for s in suspects {
            let key = IgnoreKey.of(s.row)
            if !seenSuspects.contains(key) {
                alerts.append(.newSuspect(key, title: [s.row.identified.title, s.row.identified.project].compactMap { $0 }.joined(separator: " · ")))
            }
        }
        seenSuspects = current
        let currentRunaways = Set(runaways.map { IgnoreKey.of($0.row) })
        for r in runaways {
            let key = IgnoreKey.of(r.row)
            if !seenRunaways.contains(key) {
                alerts.append(.runaway(key, title: [r.row.identified.title, r.row.identified.project].compactMap { $0 }.joined(separator: " · "), hint: r.hint))
            }
        }
        seenRunaways = currentRunaways
        return alerts
    }
}
