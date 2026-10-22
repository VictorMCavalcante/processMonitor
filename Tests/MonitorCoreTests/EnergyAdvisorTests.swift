import Foundation
import Testing
@testable import MonitorCore

@Test func reasonPicksStrongestFactor() {
    var g = ProcessGroup.fixture(kind: .appProcess, app: "/Applications/A.app")
    g.cpuPercent = 60; g.gpuPercent = 80
    #expect(EnergyAdvisor.reason(g, blockers: []) == "GPU (80%)")
    g.gpuPercent = 0; g.cpuPercent = 10; g.wakeupsPerSecond = 333
    #expect(EnergyAdvisor.reason(g, blockers: []) == "acorda a CPU 333×/s")
    g.wakeupsPerSecond = 1
    #expect(EnergyAdvisor.reason(g, blockers: []) == "uso leve")
}

@Test func suggestionsRespectRulesAndLimit() {
    let now = Date(timeIntervalSince1970: 100_000)
    let blocker = SleepBlocker(id: "60:x", pid: 60, kind: "PreventUserIdleSystemSleep", title: "Claude Code está impedindo o Mac de dormir", since: now.addingTimeInterval(-3600), ownerPid: 50)
    var log = PowerLogSummary.empty; log.wakes = [.network: 268]
    let s = EnergyAdvisor.suggestions(groups: [], runaways: [], blockers: [blocker], log: log, onBattery: true, userIdleSeconds: 2000, now: now)
    #expect(s.map(\.action) == [.closeOwner(pid: 50), .copy("sudo pmset -b tcpkeepalive 0")])
    #expect(EnergyAdvisor.suggestions(groups: [], runaways: [], blockers: [blocker], log: .empty, onBattery: true, userIdleSeconds: 10, now: now).isEmpty)
}

@Test func reasonFallsBackToSleepBlocker() {
    let g = ProcessGroup.fixture(kind: .appProcess, app: "/Applications/A.app")
    let b = SleepBlocker(id: "1:x", pid: 1, kind: "k", title: "t", since: nil, ownerPid: 1)
    #expect(EnergyAdvisor.reason(g, blockers: [b]) == "impede o Mac de dormir")
}

@Test func energyRunawayOnlyOnBattery() {
    var t = RunawayTracker(); let ig = IgnoreList(defaults: .ephemeral())
    var r = ProcessRow.fixture(pid: 7, app: "/Applications/Game.app"); r.milliwatts = 2500
    let t0 = Date(timeIntervalSince1970: 0)
    _ = t.update([r], at: t0, myUid: 501, ignore: ig, onBattery: true)
    #expect(t.update([r], at: t0.addingTimeInterval(600), myUid: 501, ignore: ig, onBattery: true).first?.reason == .energy(milliwatts: 2500, minutes: 10))
    var t2 = RunawayTracker()
    _ = t2.update([r], at: t0, myUid: 501, ignore: ig, onBattery: false)
    #expect(t2.update([r], at: t0.addingTimeInterval(600), myUid: 501, ignore: ig, onBattery: false).isEmpty)
}
