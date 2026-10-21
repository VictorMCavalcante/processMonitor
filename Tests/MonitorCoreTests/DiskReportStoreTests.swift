import Testing
import Foundation
@testable import MonitorCore

@Test func reportRoundTripsAndCorruptFileLoadsNil() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "/r.json")
    let store = DiskReportStore(url: url)
    #expect(store.load() == nil)
    let item = DiskItem(id: "a", title: "npm cache", detail: nil, category: .safe, bytes: 5, action: .trash(["/a"]), checkedByDefault: true,
                        children: [DiskItem(id: "b", title: "b", detail: nil, category: .safe, bytes: 1, action: .docker(.unusedImages))])
    let r = DiskReport(total: 10, free: 2, items: [item], protectedSkipped: true, dockerMeasured: false, scannedAt: Date(timeIntervalSince1970: 1_000))
    store.save(r)
    #expect(store.load() == r)
    try Data("{oops".utf8).write(to: url)
    #expect(store.load() == nil)
}

@Test func staleAfterOneHour() {
    let r = DiskReport(total: 1, free: 1, items: [], protectedSkipped: false, dockerMeasured: false, scannedAt: Date(timeIntervalSince1970: 0))
    #expect(!DiskReportStore.isStale(r, now: Date(timeIntervalSince1970: 3600)))
    #expect(DiskReportStore.isStale(r, now: Date(timeIntervalSince1970: 3601)))
}
