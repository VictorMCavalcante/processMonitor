import Foundation

public enum ProcessState: Sendable, Equatable {
    case running
    case stopped
    case zombie
    case other
}

public struct ProcessSnapshot: Sendable, Identifiable, Equatable {
    public var id: Int32
    public var ppid: Int32
    public var uid: UInt32
    public var name: String
    public var executablePath: String?
    public var arguments: [String]
    public var cwd: String?
    public var startTime: Date
    public var state: ProcessState
    public var footprintBytes: UInt64
    public var cpuTimeNs: UInt64
    public var ttyName: String?
    public var energyNj: UInt64
    public var wakeups: UInt64

    public init(id: Int32, ppid: Int32, uid: UInt32, name: String, executablePath: String?, arguments: [String], cwd: String?,
                startTime: Date, state: ProcessState, footprintBytes: UInt64, cpuTimeNs: UInt64, ttyName: String?,
                energyNj: UInt64 = 0, wakeups: UInt64 = 0) {
        self.id = id
        self.ppid = ppid
        self.uid = uid
        self.name = name
        self.executablePath = executablePath
        self.arguments = arguments
        self.cwd = cwd
        self.startTime = startTime
        self.state = state
        self.footprintBytes = footprintBytes
        self.cpuTimeNs = cpuTimeNs
        self.ttyName = ttyName
        self.energyNj = energyNj
        self.wakeups = wakeups
    }
}
