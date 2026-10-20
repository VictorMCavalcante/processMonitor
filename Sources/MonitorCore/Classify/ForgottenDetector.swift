import Foundation

public enum SuspectReason: Sendable, Equatable {
    case idleDevServer(days: Int)
    case suspendedSession(days: Int)
    case orphanMcp
}

public struct Suspect: Sendable, Identifiable, Equatable {
    public var id: Int32 { row.id }
    public var row: ProcessRow
    public var reason: SuspectReason

    public init(row: ProcessRow, reason: SuspectReason) {
        self.row = row
        self.reason = reason
    }

    public var hint: String {
        switch reason {
        case .idleDevServer(let days): "Aberto há \(Self.days(days)) e quase sem uso de CPU. Provavelmente esquecido."
        case .suspendedSession(let days): "Sessão suspensa (Ctrl+Z) há \(Self.days(days))."
        case .orphanMcp: "Servidor MCP sem a sessão que o abriu."
        }
    }

    private static func days(_ n: Int) -> String { n == 1 ? "1 dia" : "\(n) dias" }
}

public enum ForgottenDetector {
    public static let idleAge: TimeInterval = 24 * 3600
    public static let idleCpuFraction = 0.005
    public static let suspendedMinimum: TimeInterval = 30 * 60

    public static func detect(_ rows: [ProcessRow], allPids: Set<Int32>, now: Date, ignore: IgnoreList, stoppedSince: [Int32: Date] = [:]) -> [Suspect] {
        rows.compactMap { row -> Suspect? in
            guard !ignore.contains(.of(row)) else { return nil }
            let age = now.timeIntervalSince(row.snapshot.startTime)
            let days = max(1, Int(age / 86_400))
            switch row.identified.kind {
            case .devServer:
                guard age >= idleAge else { return nil }
                let lifetimeCpu = Double(row.snapshot.cpuTimeNs) / 1e9 / age
                return lifetimeCpu < idleCpuFraction ? Suspect(row: row, reason: .idleDevServer(days: days)) : nil
            case .claudeSession:
                guard row.snapshot.state == .stopped, let since = stoppedSince[row.id], now.timeIntervalSince(since) >= suspendedMinimum else { return nil }
                return Suspect(row: row, reason: .suspendedSession(days: max(1, Int(now.timeIntervalSince(since) / 86_400))))
            case .mcpServer:
                let ppid = row.snapshot.ppid
                return ppid == 1 || !allPids.contains(ppid) ? Suspect(row: row, reason: .orphanMcp) : nil
            default:
                return nil
            }
        }
        .sorted { $0.row.snapshot.footprintBytes > $1.row.snapshot.footprintBytes }
    }
}
