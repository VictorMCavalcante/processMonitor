import Foundation
import Testing
@testable import MonitorCore

@Test func groupsSortByGPU() {
    var a = ProcessRow.fixture(pid: 1, app: "/Applications/A.app", bytes: 900); a.gpuPercent = 5
    var b = ProcessRow.fixture(pid: 2, app: "/Applications/B.app", bytes: 100); b.gpuPercent = 60
    #expect(Grouping.group([a, b], mode: .byApp, sort: .gpu).map(\.title) == ["B", "A"])
    #expect(Grouping.group([a, b], mode: .byApp).map(\.title) == ["A", "B"])
}

@Test func gpuRunawayAfterFiveMinutes() {
    var t = RunawayTracker()
    var r = ProcessRow.fixture(pid: 7, app: "/Applications/Game.app"); r.gpuPercent = 95
    let t0 = Date(timeIntervalSince1970: 0)
    #expect(t.update([r], at: t0, myUid: 501, ignore: IgnoreList(defaults: .ephemeral())).isEmpty)
    let found = t.update([r], at: t0.addingTimeInterval(300), myUid: 501, ignore: IgnoreList(defaults: .ephemeral()))
    #expect(found.first?.reason == .gpu(minutes: 5))
}

@Test func peaksRecordTopGPUAndOldFilesDecode() throws {
    var rec = PeakRecorder(episodes: [])
    var row = ProcessRow.fixture(pid: 1, app: "/Applications/Game.app", bytes: 100); row.gpuPercent = 70
    _ = rec.update(stats: SystemStats(pressurePercent: 80, level: .warning, usedBytes: 1, totalBytes: 2, swapUsedBytes: 0, cpuPercent: 0),
                   groups: Grouping.group([row], mode: .byApp), at: Date(timeIntervalSince1970: 0))
    #expect(rec.episodes.first?.topGPU == [PeakGPUItem(title: "Game", percent: 70)])
    let old = #"[{"id":"00000000-0000-0000-0000-000000000000","start":0,"maxLevel":2,"maxPressure":80,"top":[]}]"#
    let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970
    #expect(try d.decode([PeakEpisode].self, from: Data(old.utf8)).first?.topGPU == nil)
}
