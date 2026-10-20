import Darwin
import Foundation

public enum TerminationMode: Sendable {
    case normal
    case force
}

public struct TerminationStep: Sendable, Equatable {
    public var pid: Int32
    public var startTime: Date
    public var signals: [Int32]

    public init(pid: Int32, startTime: Date, signals: [Int32]) {
        self.pid = pid
        self.startTime = startTime
        self.signals = signals
    }
}

public enum TerminationPlan: Sendable, Equatable {
    case quitApp(bundlePath: String, force: Bool)
    case signals([TerminationStep])
    case notAllowed(reason: String)
}

public protocol Signaler: Sendable {
    func currentStartTime(of pid: Int32) -> Date?
    func send(_ signal: Int32, to pid: Int32) -> Int32
}

public struct SystemSignaler: Signaler {
    public init() {}

    public func currentStartTime(of pid: Int32) -> Date? {
        ProcessSampler().snapshot(pid: pid)?.startTime
    }

    public func send(_ signal: Int32, to pid: Int32) -> Int32 {
        kill(pid, signal) == 0 ? 0 : errno
    }
}

public enum TerminationPlanner {
    private static let launchers: Set<String> = ["npm", "pnpm", "yarn", "node", "sh", "npx", "bun"]

    public static let alreadyGone = "O processo já tinha terminado."
    private static let terminalApps: Set<String> = ["Terminal", "iTerm", "iTerm2", "Ghostty", "Warp", "WezTerm", "Alacritty", "kitty", "Hyper"]

    public static func plan(_ group: ProcessGroup, all: [ProcessSnapshot], mode: TerminationMode, myUid: UInt32) -> TerminationPlan {
        if group.kind == .system {
            return .notAllowed(reason: "Processo do sistema. Fechar pode deixar o Mac instável ou encerrar sua sessão.")
        }
        if let foreign = group.rows.first(where: { $0.snapshot.uid != myUid }) {
            return .notAllowed(reason: "Processo de outro usuário (\(userName(foreign.snapshot.uid))). Feche pelo Terminal com sudo.")
        }
        if group.kind == .appProcess, let app = group.rows.first?.identified.appBundlePath {
            return .quitApp(bundlePath: app, force: mode == .force)
        }
        let byPid = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let valid = group.rows.filter { row in
            byPid[row.id].map { abs($0.startTime.timeIntervalSince(row.snapshot.startTime)) < 0.001 } ?? false
        }
        guard !valid.isEmpty else { return .notAllowed(reason: alreadyGone) }
        var targets = Set(valid.map(\.id))
        var frontier = Array(targets)
        while let pid = frontier.popLast() {
            for child in all where child.ppid == pid && !targets.contains(child.id) {
                targets.insert(child.id)
                frontier.append(child.id)
            }
        }
        if group.kind == .devServer {
            for row in valid {
                var parent = byPid[row.snapshot.ppid]
                while let p = parent, p.id > 1, isLauncher(p), !targets.contains(p.id) {
                    let outsiders = all.contains { $0.ppid == p.id && !targets.contains($0.id) }
                    if outsiders { break }
                    targets.insert(p.id)
                    parent = byPid[p.ppid]
                }
            }
        }
        let resolved = targets.compactMap { byPid[$0] }
        if let foreign = resolved.first(where: { $0.uid != myUid }) {
            return .notAllowed(reason: "Processo de outro usuário (\(userName(foreign.uid))). Feche pelo Terminal com sudo.")
        }
        let ordered = resolved.sorted { depth($0, byPid) > depth($1, byPid) }
        return .signals(ordered.map { snap in
            TerminationStep(pid: snap.id, startTime: snap.startTime,
                            signals: (snap.state == .stopped ? [SIGCONT] : []) + [mode == .force ? SIGKILL : SIGTERM])
        })
    }

    public static func singleRowGroup(_ row: ProcessRow, isRunningApp: Bool) -> ProcessGroup {
        var r = row
        if r.identified.kind == .appProcess && !isRunningApp {
            r.identified.kind = .other
            r.identified.appBundlePath = nil
        }
        return ProcessGroup(id: "pid:\(row.id)", title: isRunningApp ? row.identified.title : row.snapshot.name, subtitle: nil, kind: r.identified.kind, rows: [r])
    }

    public static func needsConfirmation(_ group: ProcessGroup, all: [ProcessSnapshot], myUid: UInt32) -> Bool {
        switch group.kind {
        case .claudeSession where group.rows.contains(where: { $0.snapshot.state != .stopped }): return true
        case .shell: return true
        case .appProcess:
            let path = group.rows.first?.identified.appBundlePath ?? ""
            return path.hasPrefix("/System/") || terminalApps.contains(group.rows.first?.identified.title ?? "")
        default: break
        }
        if case .signals(let steps) = plan(group, all: all, mode: .normal, myUid: myUid) { return steps.count > 5 }
        return false
    }

    private static func isLauncher(_ p: ProcessSnapshot) -> Bool {
        let argv0 = p.arguments.first.map { ($0 as NSString).lastPathComponent } ?? ""
        return launchers.contains(p.name) || launchers.contains(argv0)
    }

    private static func depth(_ p: ProcessSnapshot, _ byPid: [Int32: ProcessSnapshot]) -> Int {
        var d = 0
        var current = byPid[p.ppid]
        var seen: Set<Int32> = [p.id]
        while let c = current, !seen.contains(c.id), d < 64 {
            seen.insert(c.id)
            d += 1
            current = byPid[c.ppid]
        }
        return d
    }

    private static func userName(_ uid: UInt32) -> String {
        guard let pw = getpwuid(uid) else { return "uid \(uid)" }
        return String(cString: pw.pointee.pw_name)
    }
}

public enum TerminationExecutor {
    public static func run(_ steps: [TerminationStep], signaler: Signaler) -> [Int32: String] {
        var failures: [Int32: String] = [:]
        for step in steps {
            guard let current = signaler.currentStartTime(of: step.pid), abs(current.timeIntervalSince(step.startTime)) < 0.001 else {
                failures[step.pid] = TerminationPlanner.alreadyGone
                continue
            }
            for signal in step.signals {
                let err = signaler.send(signal, to: step.pid)
                if err == ESRCH { break }
                if err == EPERM { failures[step.pid] = "Sem permissão para fechar este processo."; break }
                if err != 0 { failures[step.pid] = "Não foi possível fechar (erro \(err))."; break }
            }
        }
        return failures
    }
}
