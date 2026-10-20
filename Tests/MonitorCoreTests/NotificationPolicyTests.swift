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

@Test func suspectNotifiesOnceUntilGone() {
    var p = NotificationPolicy()
    let s = Suspect.fixture(pid: 1, kind: .mcpServer, project: "immobile")
    #expect(p.evaluate(level: .normal, suspects: [s], now: .now).count == 1)
    #expect(p.evaluate(level: .normal, suspects: [s], now: .now).isEmpty)
    _ = p.evaluate(level: .normal, suspects: [], now: .now)
    #expect(p.evaluate(level: .normal, suspects: [s], now: .now).count == 1)
}
