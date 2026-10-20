import Foundation
import Testing
@testable import MonitorCore

@Test func sustainedCpuFlagsAfterFiveMinutes() {
    var t = RunawayTracker()
    let ignore = IgnoreList(defaults: .ephemeral())
    let t0 = Date(timeIntervalSince1970: 1000)
    var row = ProcessRow.fixture(pid: 5, kind: .devServer)
    row.cpuPercent = 95
    for s in stride(from: 0, through: 290, by: 10) {
        #expect(t.update([row], at: t0.addingTimeInterval(Double(s)), myUid: 501, ignore: ignore).isEmpty)
    }
    #expect(t.update([row], at: t0.addingTimeInterval(300), myUid: 501, ignore: ignore).first?.reason == .cpu(minutes: 5))
}

@Test func cpuDipResets() {
    var t = RunawayTracker()
    let ignore = IgnoreList(defaults: .ephemeral())
    let t0 = Date(timeIntervalSince1970: 0)
    var row = ProcessRow.fixture(pid: 5, kind: .other)
    for s in stride(from: 0, through: 400, by: 10) {
        row.cpuPercent = s == 200 ? 10 : 95
        _ = t.update([row], at: t0.addingTimeInterval(Double(s)), myUid: 501, ignore: ignore)
    }
    #expect(t.update([row], at: t0.addingTimeInterval(410), myUid: 501, ignore: ignore).isEmpty)
}

@Test func growingMemoryFlags() {
    var t = RunawayTracker()
    let ignore = IgnoreList(defaults: .ephemeral())
    let t0 = Date(timeIntervalSince1970: 0)
    var last: [Runaway] = []
    for m in 0...30 {
        last = t.update([.fixture(pid: 8, kind: .other, bytes: UInt64(1_000_000_000 + m * 40_000_000))], at: t0.addingTimeInterval(Double(m * 60)), myUid: 501, ignore: ignore)
    }
    guard case .memory = last.first?.reason else { Issue.record("expected memory runaway"); return }
}

@Test func reusedPidResetsHistory() {
    var t = RunawayTracker()
    let ignore = IgnoreList(defaults: .ephemeral())
    var a = ProcessRow.fixture(pid: 5, kind: .other, start: Date(timeIntervalSince1970: 1))
    a.cpuPercent = 99
    for s in stride(from: 0, through: 290, by: 10) {
        _ = t.update([a], at: Date(timeIntervalSince1970: Double(1000 + s)), myUid: 501, ignore: ignore)
    }
    var b = ProcessRow.fixture(pid: 5, kind: .other, start: Date(timeIntervalSince1970: 1290))
    b.cpuPercent = 99
    #expect(t.update([b], at: Date(timeIntervalSince1970: 1300), myUid: 501, ignore: ignore).isEmpty)
}

@Test func buildDaemonCpuIsIgnored() {
    var t = RunawayTracker()
    let ignore = IgnoreList(defaults: .ephemeral())
    var row = ProcessRow.fixture(pid: 6, kind: .other)
    row.cpuPercent = 99
    row.snapshot.arguments = ["java", "org.gradle.launcher.daemon.bootstrap.GradleDaemon"]
    var out: [Runaway] = []
    for s in stride(from: 0, through: 600, by: 10) {
        out = t.update([row], at: Date(timeIntervalSince1970: Double(s)), myUid: 501, ignore: ignore)
    }
    #expect(out.isEmpty)
}

@Test func systemAndForeignProcessesAreIgnored() {
    var t = RunawayTracker()
    let ignore = IgnoreList(defaults: .ephemeral())
    var sys = ProcessRow.fixture(pid: 1, kind: .system)
    sys.cpuPercent = 99
    var out: [Runaway] = []
    for s in stride(from: 0, through: 600, by: 10) {
        out = t.update([sys], at: Date(timeIntervalSince1970: Double(s)), myUid: 501, ignore: ignore)
    }
    #expect(out.isEmpty)
}

@Test func runawayNotifiesOnce() {
    var p = NotificationPolicy()
    var row = ProcessRow.fixture(pid: 5, kind: .other)
    row.cpuPercent = 99
    let r = Runaway(row: row, reason: .cpu(minutes: 5))
    #expect(p.evaluate(level: .normal, suspects: [], runaways: [r], now: .now).count == 1)
    #expect(p.evaluate(level: .normal, suspects: [], runaways: [r], now: .now).isEmpty)
}
