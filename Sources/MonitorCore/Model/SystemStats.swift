public enum PressureLevel: Int, Sendable, Comparable {
    case normal = 1
    case warning = 2
    case critical = 4

    public init(kernelValue: Int32) {
        self = PressureLevel(rawValue: Int(kernelValue)) ?? .normal
    }

    public static func < (a: PressureLevel, b: PressureLevel) -> Bool { a.rawValue < b.rawValue }
}

public struct SystemStats: Sendable, Equatable {
    public var pressurePercent: Int
    public var level: PressureLevel
    public var usedBytes: UInt64
    public var totalBytes: UInt64
    public var swapUsedBytes: UInt64
    public var cpuPercent: Double
    public var gpuPercent: Double?
    public var gpuMemoryBytes: UInt64?

    public init(pressurePercent: Int, level: PressureLevel, usedBytes: UInt64, totalBytes: UInt64, swapUsedBytes: UInt64, cpuPercent: Double, gpuPercent: Double? = nil, gpuMemoryBytes: UInt64? = nil) {
        self.pressurePercent = pressurePercent
        self.level = level
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
        self.swapUsedBytes = swapUsedBytes
        self.cpuPercent = cpuPercent
        self.gpuPercent = gpuPercent
        self.gpuMemoryBytes = gpuMemoryBytes
    }
}
