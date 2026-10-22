import Foundation
import Testing
@testable import MonitorCore

@Test func parsesAppleSiliconBattery() {
    let p: [String: Any] = ["CurrentCapacity": 64, "MaxCapacity": 100, "ExternalConnected": false, "IsCharging": false, "FullyCharged": false,
                            "AppleRawMaxCapacity": 5513, "DesignCapacity": 6249, "CycleCount": 113, "Temperature": 3113,
                            "PowerTelemetryData": ["SystemLoad": 23246]]
    #expect(BatterySampler.parse(p) == BatteryReading(percent: 64, onBattery: true, charging: false, fullyCharged: false, systemMilliwatts: 23246, healthPercent: 88, cycles: 113, temperatureC: 31.13))
    #expect(BatterySampler.parse([:]) == nil)
}

@Test func forecastNeedsThreeMinutesAndOnePercent() {
    var f = BatteryForecast(); let t0 = Date(timeIntervalSince1970: 0)
    f.add(percent: 80, onBattery: true, at: t0)
    f.add(percent: 80, onBattery: true, at: t0.addingTimeInterval(200))
    #expect(f.minutesLeft(now: t0.addingTimeInterval(200)) == nil)
    f.add(percent: 78, onBattery: true, at: t0.addingTimeInterval(240))
    #expect(f.minutesLeft(now: t0.addingTimeInterval(240)) == 156)
    f.add(percent: 78, onBattery: false, at: t0.addingTimeInterval(250))
    #expect(f.minutesLeft(now: t0.addingTimeInterval(250)) == nil)
}

@Test func realBatteryReadDoesNotCrash() { _ = BatterySampler.read() }
