import Foundation

public enum AlertKind: Equatable, Sendable {
    case pressureRose(PressureLevel)
    case newSuspect(IgnoreKey, title: String)
}

public struct NotificationPolicy: Sendable {
    public static let pressureCooldown: TimeInterval = 600
    private var notifiedLevel: PressureLevel = .normal
    private var lastPressureAlert: Date?
    private var seenSuspects: Set<IgnoreKey> = []

    public init() {}

    public init(seen: Set<IgnoreKey>) {
        seenSuspects = seen
    }

    public var seen: Set<IgnoreKey> { seenSuspects }

    public mutating func evaluate(level: PressureLevel, suspects: [Suspect], now: Date) -> [AlertKind] {
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
        return alerts
    }
}
