import Foundation
import Testing
@testable import MonitorCore

@Test func pressureNotifiesOnRiseWithCooldown() {
    var p = NotificationPolicy()
    let t = Date(timeIntervalSince1970: 0)
    #expect(p.evaluate(level: .warning, suspects: [], now: t) == [.pressureRose(.warning)])
    #expect(p.evaluate(level: .warning, suspects: [], now: t.addingTimeInterval(60)).isEmpty)
    #expect(p.evaluate(level: .normal, suspects: [], now: t.addingTimeInterval(120)).isEmpty)
    #expect(p.evaluate(level: .warning, suspects: [], now: t.addingTimeInterval(180)).isEmpty)
    #expect(p.evaluate(level: .warning, suspects: [], now: t.addingTimeInterval(601)) == [.pressureRose(.warning)])
}

@Test func backToNormalResetsLevel() {
    var p = NotificationPolicy()
    let t = Date(timeIntervalSince1970: 0)
    _ = p.evaluate(level: .warning, suspects: [], now: t)
    _ = p.evaluate(level: .normal, suspects: [], now: t.addingTimeInterval(700))
    #expect(p.evaluate(level: .warning, suspects: [], now: t.addingTimeInterval(1400)) == [.pressureRose(.warning)])
}

@Test func suspectNotifiesOnceUntilGoneForAnHour() {
    var p = NotificationPolicy()
    let s = Suspect.fixture(pid: 1, kind: .mcpServer, project: "immobile")
    let t = Date(timeIntervalSince1970: 0)
    #expect(p.evaluate(level: .normal, suspects: [s], now: t).count == 1)
    #expect(p.evaluate(level: .normal, suspects: [s], now: t.addingTimeInterval(3)).isEmpty)
    _ = p.evaluate(level: .normal, suspects: [], now: t.addingTimeInterval(6))
    #expect(p.evaluate(level: .normal, suspects: [s], now: t.addingTimeInterval(9)).isEmpty)
    _ = p.evaluate(level: .normal, suspects: [], now: t.addingTimeInterval(12))
    #expect(p.evaluate(level: .normal, suspects: [s], now: t.addingTimeInterval(9 + 3600)).count == 1)
}

@Test func criticalFlappingRespectsCooldown() {
    var p = NotificationPolicy()
    let t = Date(timeIntervalSince1970: 0)
    #expect(p.evaluate(level: .warning, suspects: [], now: t) == [.pressureRose(.warning)])
    #expect(p.evaluate(level: .critical, suspects: [], now: t.addingTimeInterval(3)) == [.pressureRose(.critical)])
    for i in 1...20 {
        _ = p.evaluate(level: .normal, suspects: [], now: t.addingTimeInterval(Double(i) * 6))
        #expect(p.evaluate(level: .critical, suspects: [], now: t.addingTimeInterval(Double(i) * 6 + 3)).isEmpty)
    }
    _ = p.evaluate(level: .normal, suspects: [], now: t.addingTimeInterval(700))
    #expect(p.evaluate(level: .critical, suspects: [], now: t.addingTimeInterval(703)) == [.pressureRose(.critical)])
}
