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
