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

@Test func mergingKeepsUnfinishedCategories() {
    func item(_ id: String, _ c: DiskCategory) -> DiskItem {
        DiskItem(id: id, title: id, detail: nil, category: c, bytes: 1, action: .none)
    }
    let old = DiskReport(total: 10, free: 2, items: [item("s0", .safe), item("l0", .leftover), item("m0", .maybeLeftover), item("d0", .appData)],
                         protectedSkipped: false, dockerMeasured: false, scannedAt: Date(timeIntervalSince1970: 0))
    let p1 = DiskReport(total: 20, free: 5, items: [item("s1", .safe)], protectedSkipped: true, dockerMeasured: true, scannedAt: Date(timeIntervalSince1970: 9))
    let m1 = old.merging(partial: p1, finished: [.safe])
    #expect(Set(m1.items.map(\.id)) == ["s1", "l0", "m0", "d0"])
    #expect(m1.total == 20 && m1.free == 5)
    let p2 = DiskReport(total: 20, free: 4, items: [item("s1", .safe)], protectedSkipped: true, dockerMeasured: true, scannedAt: Date(timeIntervalSince1970: 9))
    let m2 = m1.merging(partial: p2, finished: [.safe, .leftover, .maybeLeftover])
    #expect(Set(m2.items.map(\.id)) == ["s1", "d0"])
    #expect(m2.free == 4)
}

@Test func clearRemovesSavedReport() {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "/r.json")
    let store = DiskReportStore(url: url)
    store.clear()
    store.save(DiskReport(total: 1, free: 1, items: [], protectedSkipped: false, dockerMeasured: false, scannedAt: Date(timeIntervalSince1970: 0)))
    #expect(store.load() != nil)
    store.clear()
    #expect(store.load() == nil)
}
