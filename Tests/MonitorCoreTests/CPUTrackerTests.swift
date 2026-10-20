import Foundation
import Testing
@testable import MonitorCore

@Test func cpuPercentFromDeltas() {
    var t = CPUTracker()
    let t0 = Date(timeIntervalSince1970: 1000)
    let a = ProcessSnapshot.fixture(pid: 10, cpuTimeNs: 1_000_000_000, start: t0)
    let b = ProcessSnapshot.fixture(pid: 10, cpuTimeNs: 1_500_000_000, start: t0)
    #expect(t.update([a], at: Date(timeIntervalSince1970: 2000))[10] == 0)
    #expect(t.update([b], at: Date(timeIntervalSince1970: 2001))[10] == 50)
}

@Test func reusedPidResetsCpu() {
    var t = CPUTracker()
    _ = t.update([.fixture(pid: 10, cpuTimeNs: 9_000_000_000, start: Date(timeIntervalSince1970: 1))], at: Date(timeIntervalSince1970: 100))
    #expect(t.update([.fixture(pid: 10, cpuTimeNs: 100, start: Date(timeIntervalSince1970: 99))], at: Date(timeIntervalSince1970: 101))[10] == 0)
}
