import Foundation
import Testing
@testable import MonitorCore

@Test func parsesAppleSiliconBattery() {
    let p: [String: Any] = ["CurrentCapacity": 64, "MaxCapacity": 100, "ExternalConnected": false, "IsCharging": false, "FullyCharged": false,
                            "AppleRawCurrentCapacity": 3528, "AppleRawMaxCapacity": 5513, "DesignCapacity": 6249, "CycleCount": 113, "Temperature": 3113,
                            "PowerTelemetryData": ["SystemLoad": 23246]]
    #expect(BatterySampler.parse(p) == BatteryReading(percent: 64, onBattery: true, charging: false, fullyCharged: false, systemMilliwatts: 23246, healthPercent: 88, cycles: 113, temperatureC: 31.13, currentMah: 3528, fullMah: 5513, designMah: 6249))
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

@Test func forecastUsesMahWhenAvailable() {
    var f = BatteryForecast(); let t0 = Date(timeIntervalSince1970: 0)
    f.add(percent: 80, currentMah: 4000, fullMah: 5000, onBattery: true, at: t0)
    f.add(percent: 79, currentMah: 3960, fullMah: 5000, onBattery: true, at: t0.addingTimeInterval(240))
    #expect(f.minutesLeft(now: t0.addingTimeInterval(240)) == nil)
    f.add(percent: 79, currentMah: 3940, fullMah: 5000, onBattery: true, at: t0.addingTimeInterval(240))
    #expect(f.minutesLeft(now: t0.addingTimeInterval(240)) == 263)
}

@Test func parsesAppleMaximumCapacity() {
    #expect(BatteryHealth.parseSystemProfiler("      Health Information:\n          Cycle Count: 113\n          Condition: Normal\n          Maximum Capacity: 93%\n") == 93)
    #expect(BatteryHealth.parseSystemProfiler("Power:\n    AC Charger Information:\n") == nil)
}

@Test func powerAverageUsesLastTenMinutes() {
    var a = PowerAverage(); let t0 = Date(timeIntervalSince1970: 0)
    #expect(a.milliwatts(now: t0) == nil)
    a.add(30000, at: t0)
    a.add(10000, at: t0.addingTimeInterval(300))
    a.add(20000, at: t0.addingTimeInterval(600))
    #expect(a.milliwatts(now: t0.addingTimeInterval(600)) == 20000)
    a.add(20000, at: t0.addingTimeInterval(700))
    #expect(a.milliwatts(now: t0.addingTimeInterval(700)) == 50000.0 / 3)
    #expect(a.milliwatts(now: t0.addingTimeInterval(1400)) == nil)
}

@Test func realBatteryReadDoesNotCrash() { _ = BatterySampler.read() }
