import Foundation
import Testing
@testable import MonitorCore

@Test func recorderOpensAccumulatesAndCloses() {
    var r = SessionRecorder(sessions: [])
    var g = ProcessGroup.fixture(kind: .appProcess, app: "/Applications/Chrome.app"); g.milliwatts = 3600
    let bat = BatteryReading(percent: 90, onBattery: true, charging: false, fullyCharged: false, systemMilliwatts: nil, healthPercent: nil, cycles: nil, temperatureC: nil)
    let t0 = Date(timeIntervalSince1970: 0)
    let opened = r.update(battery: bat, groups: [g], at: t0, interval: 0)
    #expect(opened)
    _ = r.update(battery: bat, groups: [g], at: t0.addingTimeInterval(3600), interval: 3600)
    var ac = bat; ac.onBattery = false; ac.percent = 70
    let closed = r.update(battery: ac, groups: [g], at: t0.addingTimeInterval(3601), interval: 1)
    #expect(closed)
    let s = r.sessions[0]
    #expect(s.end != nil && s.startPercent == 90 && s.endPercent == 70 && s.top.first == EnergyItem(title: "Chrome", milliwattHours: 3600))
    #expect(s.drainPerHour == 20)
}

@Test func insightNamesDifferences() {
    func s(_ drain: Int, _ top: [EnergyItem]) -> BatterySession {
        BatterySession(id: UUID(), start: .distantPast, end: .distantPast, startPercent: 100, endPercent: 100 - drain, awakeSeconds: 3600, top: top, reconstructed: false)
    }
    let history = [s(10, [EnergyItem(title: "Arc", milliwattHours: 2000)]), s(10, [EnergyItem(title: "Arc", milliwattHours: 2000)])]
    let now = s(25, [EnergyItem(title: "supabase", milliwattHours: 9000), EnergyItem(title: "Arc", milliwattHours: 2000)])
    #expect(SessionInsight.compare(now, history: history) == "Esta sessão gastou 2,5× mais que a sua média; principais diferenças: supabase")
    #expect(SessionInsight.compare(s(12, []), history: history) == nil)
}

@Test func corruptSessionFileLoadsEmpty() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    try Data("{x".utf8).write(to: url)
    #expect(BatterySessionStore(url: url).load().isEmpty)
}

@Test func recorderSavesPeriodicallyMergesAndCaps() {
    let bat = BatteryReading(percent: 90, onBattery: true, charging: false, fullyCharged: false, systemMilliwatts: nil, healthPercent: nil, cycles: nil, temperatureC: nil)
    var r = SessionRecorder(sessions: [])
    let opened = r.update(battery: bat, groups: [], at: Date(timeIntervalSince1970: 10_000), interval: 0)
    #expect(opened)
    let early = r.update(battery: bat, groups: [], at: Date(timeIntervalSince1970: 10_100), interval: 100)
    #expect(!early)
    let periodic = r.update(battery: bat, groups: [], at: Date(timeIntervalSince1970: 10_300), interval: 200)
    #expect(periodic)
    r.merge([PowerLogSession(start: Date(timeIntervalSince1970: 9_000), end: Date(timeIntervalSince1970: 10_050), startPercent: 100, endPercent: 95),
             PowerLogSession(start: Date(timeIntervalSince1970: 1_000), end: Date(timeIntervalSince1970: 5_000), startPercent: 100, endPercent: 90)])
    #expect(r.sessions.count == 2 && r.sessions[0].reconstructed && r.sessions[0].startPercent == 100)
    let many = (0..<70).map { PowerLogSession(start: Date(timeIntervalSince1970: Double($0) * 10), end: Date(timeIntervalSince1970: Double($0) * 10 + 5), startPercent: 50, endPercent: 40) }
    r.merge(many)
    #expect(r.sessions.count == 60 && r.sessions.last?.end == nil)
}

@Test func relaunchOnACAfterGapClosesWithLastBatteryValues() {
    let bat = BatteryReading(percent: 80, onBattery: true, charging: false, fullyCharged: false, systemMilliwatts: nil, healthPercent: nil, cycles: nil, temperatureC: nil)
    var r = SessionRecorder(sessions: [])
    _ = r.update(battery: bat, groups: [], at: Date(timeIntervalSince1970: 0), interval: 0)
    _ = r.update(battery: bat, groups: [], at: Date(timeIntervalSince1970: 3600), interval: 3600)
    var relaunched = SessionRecorder(sessions: r.sessions)
    var ac = bat; ac.onBattery = false; ac.percent = 100
    _ = relaunched.update(battery: ac, groups: [], at: Date(timeIntervalSince1970: 9000), interval: 1)
    #expect(relaunched.sessions[0].end == Date(timeIntervalSince1970: 3600) && relaunched.sessions[0].endPercent == 80)
}

@Test func insightComparesRatesAndIgnoresNegativeDrain() {
    func s(_ drain: Int, hours: Double = 1, start: Int = 100, _ top: [EnergyItem]) -> BatterySession {
        BatterySession(id: UUID(), start: .distantPast, end: .distantPast, startPercent: start, endPercent: start - drain, awakeSeconds: hours * 3600, top: top, reconstructed: false)
    }
    let history = [s(10, [EnergyItem(title: "Arc", milliwattHours: 2000)]), s(10, [EnergyItem(title: "Arc", milliwattHours: 2000)]), s(-40, start: 50, [])]
    let long = s(50, hours: 2, [EnergyItem(title: "supabase", milliwattHours: 9000), EnergyItem(title: "Arc", milliwattHours: 4000)])
    #expect(SessionInsight.compare(long, history: history) == "Esta sessão gastou 2,5× mais que a sua média; principais diferenças: supabase")
    #expect(SessionInsight.compare(s(-5, start: 50, []), history: history) == nil)
}
