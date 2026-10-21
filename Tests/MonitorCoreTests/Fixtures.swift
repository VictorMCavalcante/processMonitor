import Foundation
@testable import MonitorCore

extension ProcessSnapshot {
    static func fixture(
        pid: Int32 = 100,
        name: String = "proc",
        arguments: [String] = [],
        cwd: String? = nil,
        ppid: Int32 = 1,
        uid: UInt32 = 501,
        state: ProcessState = .running,
        executablePath: String? = nil,
        cpuTimeNs: UInt64 = 0,
        start: Date = Date(timeIntervalSince1970: 0),
        bytes: UInt64 = 0
    ) -> ProcessSnapshot {
        ProcessSnapshot(id: pid, ppid: ppid, uid: uid, name: name, executablePath: executablePath, arguments: arguments,
                        cwd: cwd, startTime: start, state: state, footprintBytes: bytes, cpuTimeNs: cpuTimeNs, ttyName: nil)
    }
}

extension ProcessRow {
    static func fixture(
        pid: Int32,
        kind: ProcessKind = .other,
        app: String? = nil,
        state: ProcessState = .running,
        ppid: Int32 = 1,
        project: String? = nil,
        start: Date = Date(timeIntervalSince1970: 0),
        cpuTimeNs: UInt64 = 0,
        bytes: UInt64 = 0
    ) -> ProcessRow {
        let resolvedKind: ProcessKind = app != nil ? .appProcess : kind
        let title = app.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension } ?? "p\(pid)"
        let snap = ProcessSnapshot.fixture(pid: pid, name: title, ppid: ppid, state: state, cpuTimeNs: cpuTimeNs, start: start, bytes: bytes)
        return ProcessRow(snapshot: snap, identified: Identified(kind: resolvedKind, title: title, project: project, appBundlePath: app), cpuPercent: 0, ports: [])
    }
}

private final class EphemeralSuites: @unchecked Sendable {
    static let shared = EphemeralSuites()
    private let lock = NSLock()
    private var names: [String] = []

    private init() {
        atexit {
            for name in EphemeralSuites.shared.drain() {
                UserDefaults.standard.removePersistentDomain(forName: name)
                CFPreferencesAppSynchronize(name as CFString)
                try? FileManager.default.removeItem(atPath: NSHomeDirectory() + "/Library/Preferences/\(name).plist")
            }
        }
    }

    func add(_ name: String) { lock.withLock { names.append(name) } }
    func drain() -> [String] { lock.withLock { defer { names = [] }; return names } }
}

extension UserDefaults {
    static func ephemeral() -> UserDefaults {
        let name = "monitor-test-\(UUID().uuidString)"
        EphemeralSuites.shared.add(name)
        return UserDefaults(suiteName: name)!
    }
}

extension ProcessGroup {
    static func fixture(kind: ProcessKind, pids: [Int32] = [], in all: [ProcessSnapshot] = [], app: String? = nil) -> ProcessGroup {
        if let app {
            let row = ProcessRow.fixture(pid: 1, app: app)
            return ProcessGroup(id: "app:\(app)", title: row.identified.title, subtitle: nil, kind: .appProcess, rows: [row])
        }
        let rows = pids.map { pid -> ProcessRow in
            let snap = all.first { $0.id == pid } ?? ProcessSnapshot.fixture(pid: pid)
            return ProcessRow(snapshot: snap, identified: Identified(kind: kind, title: snap.name), cpuPercent: 0, ports: [])
        }
        return ProcessGroup(id: "g", title: rows.first?.identified.title ?? "g", subtitle: nil, kind: kind, rows: rows)
    }
}

extension Suspect {
    static func fixture(pid: Int32, kind: ProcessKind, project: String?) -> Suspect {
        Suspect(row: .fixture(pid: pid, kind: kind, ppid: 1, project: project), reason: .orphanMcp)
    }
}
