import Foundation

public enum AlertKind: Equatable, Sendable {
    case pressureRose(PressureLevel)
    case newSuspect(IgnoreKey, title: String)
    case runaway(IgnoreKey, title: String, hint: String)
}

public struct NotificationPolicy: Sendable {
    public static let pressureCooldown: TimeInterval = 600
    /// A suspect that blinks out for a cycle or two (CPU blip, half-written status file) is not new when
    /// it comes back; only one gone for this long gets notified again.
    public static let suspectForgetAfter: TimeInterval = 3600
    private var notifiedLevel: PressureLevel = .normal
    private var lastPressureAlert: Date?
    private var lastAlertedLevel: PressureLevel = .normal
    private var seenSuspects: [IgnoreKey: Date] = [:]

    public init() {}

    public static let runawayCooldown: TimeInterval = 3600
    private var runawayNotifiedAt: [IgnoreKey: Date] = [:]
    private static let runawayPrefix = "runaway:"

    public init(seen: Set<IgnoreKey>) {
        seenSuspects = Dictionary(seen.filter { !$0.raw.hasPrefix(Self.runawayPrefix) }.map { ($0, Date()) }, uniquingKeysWith: { a, _ in a })
        let restored = seen.filter { $0.raw.hasPrefix(Self.runawayPrefix) }.map { IgnoreKey(raw: String($0.raw.dropFirst(Self.runawayPrefix.count))) }
        runawayNotifiedAt = Dictionary(restored.map { ($0, Date()) }, uniquingKeysWith: { a, _ in a })
    }

    public var seen: Set<IgnoreKey> {
        Set(seenSuspects.keys).union(runawayNotifiedAt.keys.map { IgnoreKey(raw: Self.runawayPrefix + $0.raw) })
    }

    /// Stable per alert, so a repeat replaces the old banner in Notification Center instead of stacking.
    public static func identifier(_ alert: AlertKind) -> String {
        switch alert {
        case .pressureRose: "pressure"
        case .newSuspect(let key, _): "suspect:" + key.raw
        case .runaway(let key, _, _): runawayPrefix + key.raw
        }
    }

    public mutating func evaluate(level: PressureLevel, suspects: [Suspect], runaways: [Runaway] = [], now: Date) -> [AlertKind] {
        var alerts: [AlertKind] = []
        if level == .normal {
            notifiedLevel = .normal
        } else if level > notifiedLevel {
            // Within the cooldown only an escalation past the last alert (warning → critical) notifies,
            // so pressure flapping around a threshold doesn't alert every cycle.
            let cooledDown = lastPressureAlert.map { now.timeIntervalSince($0) >= Self.pressureCooldown } ?? true
            if cooledDown || level > lastAlertedLevel {
                notifiedLevel = level
                lastPressureAlert = now
                lastAlertedLevel = level
                alerts.append(.pressureRose(level))
            }
        }
        seenSuspects = seenSuspects.filter { now.timeIntervalSince($0.value) < Self.suspectForgetAfter }
        for s in suspects {
            let key = IgnoreKey.of(s.row)
            if seenSuspects[key] == nil {
                alerts.append(.newSuspect(key, title: [s.row.identified.title, s.row.identified.project].compactMap { $0 }.joined(separator: " · ")))
            }
            seenSuspects[key] = now
        }
        runawayNotifiedAt = runawayNotifiedAt.filter { now.timeIntervalSince($0.value) < Self.runawayCooldown }
        for r in runaways {
            let key = IgnoreKey.of(r.row)
            if runawayNotifiedAt[key] == nil {
                runawayNotifiedAt[key] = now
                alerts.append(.runaway(key, title: [r.row.identified.title, r.row.identified.project].compactMap { $0 }.joined(separator: " · "), hint: r.hint))
            }
        }
        return alerts
    }
}
