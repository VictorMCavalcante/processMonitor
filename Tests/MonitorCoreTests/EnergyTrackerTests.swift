import Testing
import Foundation
@testable import MonitorCore

@Test func energyRateUsesTenMinuteWindowAndResetsSafely() {
    var t = EnergyTracker(window: 600)
    let s = Date(timeIntervalSince1970: 0), t0 = Date(timeIntervalSince1970: 1000)
    func snap(_ nj: UInt64, _ w: UInt64, start: Date = s) -> ProcessSnapshot { var p = ProcessSnapshot.fixture(pid: 1, start: start); p.energyNj = nj; p.wakeups = w; return p }
    #expect(t.update([snap(0, 0)], at: t0)[1] == EnergyRate(milliwatts: 0, wakeupsPerSecond: 0))
    #expect(t.update([snap(10_000_000_000, 500)], at: t0.addingTimeInterval(10))[1] == EnergyRate(milliwatts: 1000, wakeupsPerSecond: 50))
    let r = t.update([snap(10_000_000_000 + 600_000_000_000, 500)], at: t0.addingTimeInterval(610))[1]
    #expect(r?.milliwatts == 1000 && r?.wakeupsPerSecond == 0)
    #expect(t.update([snap(5, 0)], at: t0.addingTimeInterval(620))[1]?.milliwatts == 0)
    #expect(t.update([snap(9_000_000_000, 0, start: Date(timeIntervalSince1970: 5))], at: t0.addingTimeInterval(630))[1]?.milliwatts == 0)
}

@Test func groupsSumEnergyAndSortByIt() {
    var a = ProcessRow.fixture(pid: 1, app: "/Applications/A.app"); a.milliwatts = 300
    var b = ProcessRow.fixture(pid: 2, app: "/Applications/B.app"); b.milliwatts = 900
    var c = ProcessRow.fixture(pid: 3, app: "/Applications/B.app"); c.milliwatts = 100
    let g = Grouping.group([a, b, c], mode: .byApp, sort: .energy)
    #expect(g.map(\.title) == ["B", "A"] && g[0].milliwatts == 1000)
}
