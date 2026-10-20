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
