import Foundation
import Testing
@testable import MonitorCore

@Test func pressureFromFree() {
    #expect(SystemSampler.pressurePercent(freePercent: 28) == 72)
    #expect(SystemSampler.pressurePercent(freePercent: 120) == 0)
    #expect(SystemSampler.pressurePercent(freePercent: -5) == 100)
}

@Test func levelMapping() {
    #expect(PressureLevel(kernelValue: 1) == .normal)
    #expect(PressureLevel(kernelValue: 2) == .warning)
    #expect(PressureLevel(kernelValue: 4) == .critical)
    #expect(PressureLevel(kernelValue: 9) == .normal)
}

@Test func liveSampleIsSane() {
    var s = SystemSampler()
    let a = s.sample()
    #expect(a.totalBytes == ProcessInfo.processInfo.physicalMemory)
    #expect(a.usedBytes > 0 && a.usedBytes <= a.totalBytes)
    #expect((0...100).contains(a.pressurePercent))
}
