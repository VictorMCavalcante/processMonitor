import Foundation
import Testing
@testable import MonitorCore

private func stats(_ p: Int, _ l: PressureLevel) -> SystemStats {
    SystemStats(pressurePercent: p, level: l, usedBytes: 1, totalBytes: 2, swapUsedBytes: 0, cpuPercent: 0)
}

@Test func episodeLifecycleCapturesTopAtPeak() {
    var r = PeakRecorder()
    let t0 = Date(timeIntervalSince1970: 0)
    let teams = ProcessGroup.fixture(kind: .appProcess, app: "/Applications/Microsoft Teams.app")
    _ = r.update(stats: stats(40, .normal), groups: [teams], at: t0)
    #expect(r.episodes.isEmpty)
    _ = r.update(stats: stats(70, .warning), groups: [teams], at: t0.addingTimeInterval(60))
    _ = r.update(stats: stats(90, .critical), groups: [teams], at: t0.addingTimeInterval(120))
    _ = r.update(stats: stats(50, .normal), groups: [], at: t0.addingTimeInterval(600))
    #expect(r.episodes.count == 1)
    #expect(r.episodes[0].maxPressure == 90 && r.episodes[0].maxLevel == 4 && r.episodes[0].end == t0.addingTimeInterval(600))
    #expect(r.episodes[0].top.first?.title == "Microsoft Teams")
}

@Test func prunesOlderThanSevenDays() {
    let old = PeakEpisode(id: UUID(), start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 60), maxLevel: 2, maxPressure: 70, top: [])
    var r = PeakRecorder(episodes: [old])
    r.prune(now: Date(timeIntervalSince1970: 8 * 86_400))
    #expect(r.episodes.isEmpty)
}

@Test func storeRoundTripAndCorruptFile() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("peaks-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let store = PeakStore(url: url)
    #expect(store.load().isEmpty)
    let e = PeakEpisode(id: UUID(), start: Date(timeIntervalSince1970: 5), end: nil, maxLevel: 2, maxPressure: 70, top: [PeakItem(title: "Arc", bytes: 10)])
    store.save([e])
    #expect(store.load() == [e])
    try Data("not json".utf8).write(to: url)
    #expect(store.load().isEmpty)
}
