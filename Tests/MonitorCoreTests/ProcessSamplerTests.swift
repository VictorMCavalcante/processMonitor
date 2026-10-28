import Foundation
import Testing
@testable import MonitorCore

@Test func seesItselfWithDetails() {
    let me = ProcessSampler().sample().first { $0.id == getpid() }
    #expect(me != nil)
    #expect(me?.cwd == FileManager.default.currentDirectoryPath)
    #expect(me?.arguments.isEmpty == false)
    #expect((me?.footprintBytes ?? 0) > 0)
    #expect((me?.startTime ?? .distantFuture) < Date())
}

@Test func otherUserProcessIsPartialNotFatal() {
    let launchd = ProcessSampler().sample().first { $0.id == 1 }
    #expect(launchd?.uid == 0)
}

@Test func vanishedProcessIsSkipped() throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    try p.run()
    p.waitUntilExit()
    #expect(!ProcessSampler().sample().contains { $0.id == p.processIdentifier && $0.state != .zombie })
}

@Test func stoppedProcessIsReportedStopped() throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sleep")
    p.arguments = ["30"]
    try p.run()
    defer { kill(p.processIdentifier, SIGKILL) }
    kill(p.processIdentifier, SIGSTOP)
    usleep(100_000)
    let snap = ProcessSampler().sample().first { $0.id == p.processIdentifier }
    #expect(snap?.state == .stopped)
    #expect(snap?.arguments == ["/bin/sleep", "30"])
}

@Test func ttyNameIsCachedPerDevice() {
    let dev: UInt32 = (16 << 24) | 0
    let first = ProcessSampler.ttyName(dev)
    #expect(ProcessSampler.ttyName(dev) == first)
    #expect(ProcessSampler.ttyCacheCount >= 1)
    #expect(ProcessSampler.ttyName(0) == nil && ProcessSampler.ttyName(UInt32.max) == nil)
}

@Test func otherUserProcessesGetUsageFromPS() {
    let launchd = ProcessSampler().sample().first { $0.id == 1 }
    #expect((launchd?.footprintBytes ?? 0) > 0)
    #expect((launchd?.cpuTimeNs ?? 0) > 0)
}

@Test func parsesPSUsage() {
    let usage = ProcessSampler.parsePS("    1  22496 323:51.09\n  588 257088 1-02:03:04.50\nbad line\n")
    #expect(usage[1]?.rssBytes == 22496 * 1024)
    #expect(usage[1]?.cpuNs == UInt64(19431.09 * 1e9))
    #expect(usage[588]?.cpuNs == 93_784_500_000_000)
    #expect(usage.count == 2)
}

@Test func truncatedNameUsesPath() {
    let path = "/System/Library/PrivateFrameworks/AppleNeuralEngine.framework/XPCServices/ANEStorageMaintainer.xpc/Contents/MacOS/ANEStorageMaintainer"
    #expect(ProcessSampler.fullName("ANEStorageMainta", path: path) == "ANEStorageMaintainer")
    #expect(ProcessSampler.fullName("zsh", path: "/bin/zsh") == "zsh")
}
