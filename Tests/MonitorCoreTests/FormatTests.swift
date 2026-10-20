import Foundation
import Testing
@testable import MonitorCore

@Test func bytesInPortuguese() {
    #expect(Format.bytes(2_684_354_560) == "2,5 GB")
    #expect(Format.bytes(640_680_000) == "611 MB")
    #expect(Format.bytes(0) == "0 MB")
}

@Test func ageLabels() {
    let now = Date(timeIntervalSince1970: 100 * 86_400)
    #expect(Format.age(since: now.addingTimeInterval(-20 * 3600), now: now) == "20 h")
    #expect(Format.age(since: now.addingTimeInterval(-4 * 86_400), now: now) == "4 dias")
    #expect(Format.age(since: now.addingTimeInterval(-86_400 - 60), now: now) == "1 dia")
    #expect(Format.age(since: now.addingTimeInterval(-300), now: now) == "5 min")
}
