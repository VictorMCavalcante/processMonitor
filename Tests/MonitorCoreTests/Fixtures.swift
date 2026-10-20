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
