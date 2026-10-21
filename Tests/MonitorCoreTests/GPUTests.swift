import Foundation
import Testing
@testable import MonitorCore

@Test func parsesCreatorAndStats() {
    #expect(GPUSampler.parseCreator("pid 588, WindowServer") == 588 && GPUSampler.parseCreator("x") == nil)
    let s = GPUSampler.parseStats(["Device Utilization %": 79, "In use system memory": 1_975_123_968])
    #expect(s.utilization == 79 && s.memoryInUse == 1_975_123_968)
    #expect(GPUSampler.parseStats([:]).utilization == nil)
}

@Test func accumulateSumsClientsPerPid() {
    let r = GPUSampler.accumulate([
        ("pid 10, A", [["accumulatedGPUTime": 100], ["accumulatedGPUTime": 50]]),
        ("pid 10, A", [["accumulatedGPUTime": 25]]),
        ("pid 11, B", []),
    ])
    #expect(r == [10: 175, 11: 0])
}

@Test func trackerComputesPercentWithCapReuseAndNegative() {
    var t = GPUTracker()
    let s = Date(timeIntervalSince1970: 0), t0 = Date(timeIntervalSince1970: 100)
    #expect(t.update([1: 1_000_000_000], starts: [1: s], at: t0) == [1: 0])
    #expect(t.update([1: 1_500_000_000], starts: [1: s], at: t0.addingTimeInterval(1)) == [1: 50])
    #expect(t.update([1: 9_000_000_000], starts: [1: s], at: t0.addingTimeInterval(2)) == [1: 100])
    #expect(t.update([1: 1_000], starts: [1: s], at: t0.addingTimeInterval(3)) == [1: 0])
    #expect(t.update([1: 5_000_000_000], starts: [1: Date(timeIntervalSince1970: 50)], at: t0.addingTimeInterval(4)) == [1: 0])
}

@Test func realReadDoesNotCrash() {
    _ = GPUSampler.read()
}
