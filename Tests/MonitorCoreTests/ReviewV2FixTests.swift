import Foundation
import Testing
@testable import MonitorCore

@Test func dockerPortWithoutContainerIsBlocked() {
    let docker = ProcessRow.fixture(pid: 50, app: "/Applications/Docker.app")
    let e = PortTable.build(sockets: [ListeningSocket(pid: 50, port: 6000, exposure: .network)], rows: [docker], containers: [])
    guard case .blocked(let reason) = PortTable.release(port: 6000, entries: e, all: [docker.snapshot], myUid: 501) else { Issue.record("expected blocked"); return }
    #expect(reason.contains("aba Docker"))
}

@Test func parsesPortRanges() {
    let line = #"{"ID":"x","Names":"web","Image":"nginx","State":"running","Labels":"","Ports":"0.0.0.0:8000-8002->8000-8002/tcp"}"#
    #expect(DockerClient.parsePs(line).first?.publishedPorts == [8000, 8001, 8002])
}

@Test func helperPortQuitAlwaysNeedsConfirmation() {
    let row = ProcessRow.fixture(pid: 70, app: "/Applications/Cursor.app")
    let e = PortTable.build(sockets: [ListeningSocket(pid: 70, port: 9000, exposure: .local)], rows: [row], containers: [])
    let release = PortTable.release(port: 9000, entries: e, all: [row.snapshot], myUid: 501)
    #expect(release.requiresConfirmation(all: [row.snapshot], myUid: 501))
}

@Test func vanishedAppPortOwnerIsGone() {
    let row = ProcessRow.fixture(pid: 71, app: "/Applications/Cursor.app")
    let e = PortTable.build(sockets: [ListeningSocket(pid: 71, port: 9001, exposure: .local)], rows: [row], containers: [])
    #expect(PortTable.release(port: 9001, entries: e, all: [], myUid: 501) == .blocked(TerminationPlanner.alreadyGone))
}

@Test func restartingDockerNeedsConfirmation() {
    #expect(TerminationPlanner.restartNeedsConfirmation(.fixture(kind: .appProcess, app: "/Applications/Docker.app")))
    #expect(!TerminationPlanner.restartNeedsConfirmation(.fixture(kind: .appProcess, app: "/Applications/Arc.app")))
}

@Test func virtualMachineNeverRunaway() {
    var t = RunawayTracker()
    let ignore = IgnoreList(defaults: .ephemeral())
    var row = ProcessRow.fixture(pid: 9, app: "/Applications/Docker.app")
    row.snapshot.executablePath = "/System/Library/Frameworks/Virtualization.framework/Versions/A/XPCServices/com.apple.Virtualization.VirtualMachine.xpc/Contents/MacOS/com.apple.Virtualization.VirtualMachine"
    row.cpuPercent = 99
    var out: [Runaway] = []
    for s in stride(from: 0, through: 600, by: 10) { out = t.update([row], at: Date(timeIntervalSince1970: Double(s)), myUid: 501, ignore: ignore) }
    #expect(out.isEmpty)
}

@Test func flappingRunawayNotifiesOncePerHour() {
    var p = NotificationPolicy()
    var row = ProcessRow.fixture(pid: 5, kind: .other)
    row.cpuPercent = 99
    let r = Runaway(row: row, reason: .cpu(minutes: 5))
    let t0 = Date(timeIntervalSince1970: 0)
    #expect(p.evaluate(level: .normal, suspects: [], runaways: [r], now: t0).count == 1)
    _ = p.evaluate(level: .normal, suspects: [], runaways: [], now: t0.addingTimeInterval(60))
    #expect(p.evaluate(level: .normal, suspects: [], runaways: [r], now: t0.addingTimeInterval(420)).isEmpty)
    #expect(p.evaluate(level: .normal, suspects: [], runaways: [r], now: t0.addingTimeInterval(3700)).count == 1)
}

@Test func restoredPolicySuppressesRunawayRenotify() {
    var row = ProcessRow.fixture(pid: 5, kind: .other)
    row.cpuPercent = 99
    let r = Runaway(row: row, reason: .cpu(minutes: 5))
    var first = NotificationPolicy()
    _ = first.evaluate(level: .normal, suspects: [], runaways: [r], now: .now)
    var restored = NotificationPolicy(seen: first.seen)
    #expect(restored.evaluate(level: .normal, suspects: [], runaways: [r], now: .now).isEmpty)
}

@Test func dockerListIsBoundedToFiveSecondsTotal() {
    final class Recorder: CommandRunner, @unchecked Sendable {
        var timeouts: [TimeInterval] = []
        func run(_ p: String, _ a: [String], timeout: TimeInterval) -> (status: Int32, output: String)? {
            timeouts.append(timeout)
            if a.first == "ps" {
                Thread.sleep(forTimeInterval: 1)
                return (0, #"{"ID":"abc","Names":"pg","Image":"x","State":"running","Labels":"","Ports":""}"#)
            }
            return nil
        }
    }
    let rec = Recorder()
    _ = DockerClient(runner: rec, paths: ["/usr/bin/true"]).list()
    #expect(rec.timeouts.count == 2)
    #expect(rec.timeouts[1] <= 4.1)
}
