import Foundation
import Testing
@testable import MonitorCore

let sampleLog = """
2026-10-15 02:21:47 -0300 DarkWake            \tDarkWake from Deep Idle [CDNP] : due to smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty/ Using Batt (Charge:99%) 2 secs
2026-10-15 02:21:52 -0300 Sleep               \tEntering Sleep state due to 'Maintenance Sleep':TCPKeepAlive=active Using Batt (Charge:99%) 27 secs
2026-10-15 05:21:52 -0300 Wake                \tWake from Deep Idle [CDNVA] : due to HID Activity Using Batt (Charge:96%) 2 secs
2026-10-15 09:00:00 -0300 Sleep               \tEntering Sleep state due to 'Dark Wake Thermal Emergency':TCPKeepAlive=active Using Batt (Charge:70%)
2026-10-15 09:10:00 -0300 DarkWake            \tDarkWake from Deep Idle [CDNPB] : due to NUB.SPMI0Sw3IRQ nub-spmi0.0x02 rtc/SleepService Using Batt (Charge:70%)
2026-10-15 10:00:00 -0300 Assertions          \tSummary- [System: PrevIdle] Using AC(Charge: 69)
garbage line
"""

@Test func parsesSessionsWakesAndSleepDrain() {
    let s = PowerLog.parse(sampleLog)
    #expect(s.sessions.count == 1 && s.sessions[0].startPercent == 99 && s.sessions[0].endPercent == 70)
    #expect(s.wakes[.network] == 1 && s.wakes[.user] == 1 && s.wakes[.timer] == 1)
    #expect(s.thermalSleeps == 1)
    #expect(s.sleepDrainPerHour == 1)
    #expect(PowerLog.parse("") == .empty)
}

@Test func loadFailsSoftly() {
    struct Dead: CommandRunner { func run(_ p: String, _ a: [String], timeout: TimeInterval) -> (status: Int32, output: String)? { nil } }
    #expect(PowerLog.load(runner: Dead()) == .empty)
}

@Test func parsesRealChargeFormatsAndDarkWakeToFullWake() {
    let log = """
2026-10-15 10:00:00 -0300 Sleep               \tEntering Sleep state due to 'Idle Sleep' Using BATT (Charge:80%)
2026-10-15 10:30:00 -0300 Assertions          \tSummary- [System: PrevIdle] Using Batt(Charge: 79)
2026-10-15 12:00:00 -0300 Wake                \tDarkWake to FullWake from Deep Idle [CDNVA] : due to UserActivity Assertion Using BATT (Charge:76%)
2026-10-15 12:01:00 -0300 Wake Requests       \t[process=dasd request=SleepService deltaSecs=1031]
2026-10-15 12:05:00 -0300 DarkWake            \tDarkWake from Deep Idle [CDNP] : due to USB-C_plug Using AC (Charge:76%)
"""
    let s = PowerLog.parse(log)
    #expect(s.sessions == [PowerLogSession(start: Date(timeIntervalSince1970: 1_792_069_200), end: Date(timeIntervalSince1970: 1_792_076_400), startPercent: 80, endPercent: 76)])
    #expect(s.wakes == [.user: 1, .power: 1])
    #expect(s.sleepDrainPerHour == 2)
}
