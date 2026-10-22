import Foundation

public enum WakeCause: String, Sendable, CaseIterable, Codable {
    case network, timer, user, power, other

    public var title: String {
        switch self {
        case .network: "Wi‑Fi/Bluetooth (rede e notificações)"
        case .timer: "Relógio (tarefas agendadas)"
        case .user: "Teclado, mouse ou tampa"
        case .power: "Carregador/USB‑C"
        case .other: "Outros"
        }
    }

    static func from(_ reason: String) -> WakeCause {
        func has(_ words: [String]) -> Bool { words.contains { reason.contains($0) } }
        if has(["wifibt", "Network"]) { return .network }
        if has(["rtc", "RTC"]) { return .timer }
        if has(["HID", "UserActivity", "lid", "Lid"]) { return .user }
        if has(["USB-C_plug", "USB2_wake", "AC"]) { return .power }
        return .other
    }
}

public struct PowerLogSession: Sendable, Equatable {
    public var start: Date
    public var end: Date
    public var startPercent: Int
    public var endPercent: Int

    public init(start: Date, end: Date, startPercent: Int, endPercent: Int) {
        self.start = start
        self.end = end
        self.startPercent = startPercent
        self.endPercent = endPercent
    }
}

public struct PowerLogSummary: Sendable, Equatable {
    public var sessions: [PowerLogSession]
    public var wakes: [WakeCause: Int]
    public var thermalSleeps: Int
    public var sleepDrainPerHour: Double?

    public static let empty = PowerLogSummary(sessions: [], wakes: [:], thermalSleeps: 0, sleepDrainPerHour: nil)

    public init(sessions: [PowerLogSession], wakes: [WakeCause: Int], thermalSleeps: Int, sleepDrainPerHour: Double?) {
        self.sessions = sessions
        self.wakes = wakes
        self.thermalSleeps = thermalSleeps
        self.sleepDrainPerHour = sleepDrainPerHour
    }
}

public enum PowerLog {
    public static func load(runner: CommandRunner = SystemCommandRunner()) -> PowerLogSummary {
        guard let result = runner.run("/usr/bin/pmset", ["-g", "log"], timeout: 10), result.status == 0 else { return .empty }
        return parse(result.output)
    }

    public static func parse(_ text: String) -> PowerLogSummary {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        let charge = /Using (?<source>Batt|BATT|AC) ?\(Charge: ?(?<percent>\d+)%?\)/
        var summary = PowerLogSummary.empty
        var run: PowerLogSession?
        var asleep: (date: Date, percent: Int)?
        var drained = 0.0
        var sleptHours = 0.0
        func closeRun() {
            if let r = run, r.startPercent - r.endPercent > 2, r.end.timeIntervalSince(r.start) > 1800 { summary.sessions.append(r) }
            run = nil
        }
        for line in text.split(separator: "\n") {
            guard line.count > 26, let date = formatter.date(from: String(line.prefix(25))) else { continue }
            let rest = line.dropFirst(26)
            guard let tab = rest.firstIndex(of: "\t") else { continue }
            let event = rest[..<tab].trimmingCharacters(in: .whitespaces)
            let message = rest[rest.index(after: tab)...]
            let match = message.firstMatch(of: charge)
            if event == "Sleep", message.contains("Thermal") { summary.thermalSleeps += 1 }
            if event == "Wake" || event == "DarkWake", let due = message.range(of: "due to ") {
                let reason = message[due.upperBound...].components(separatedBy: "Using ")[0]
                summary.wakes[WakeCause.from(reason), default: 0] += 1
            }
            guard let match, let percent = Int(match.percent) else { continue }
            guard match.source != "AC" else {
                closeRun()
                asleep = nil
                continue
            }
            if run == nil { run = PowerLogSession(start: date, end: date, startPercent: percent, endPercent: percent) }
            run?.end = date
            run?.endPercent = percent
            if event == "Sleep", asleep == nil { asleep = (date, percent) }
            if event == "Wake", let s = asleep {
                drained += Double(max(0, s.percent - percent))
                sleptHours += date.timeIntervalSince(s.date) / 3600
                asleep = nil
            }
        }
        closeRun()
        summary.sleepDrainPerHour = sleptHours >= 1 ? drained / sleptHours : nil
        return summary
    }
}
