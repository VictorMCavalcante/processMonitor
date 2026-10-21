import Foundation
import Testing
@testable import MonitorCore

@Test func realSizeCountsHardLinkOnceAndSkipsSymlinks() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let a = dir.appendingPathComponent("a.bin")
    try Data(count: 1_000_000).write(to: a)
    try FileManager.default.linkItem(at: a, to: dir.appendingPathComponent("b.bin"))
    try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("loop"), withDestinationURL: dir)
    let fs = RealDiskFS()
    let size = fs.size(dir.path)
    #expect(size >= 1_000_000 && size < 1_200_000)
    #expect(!fs.isDirectory(dir.appendingPathComponent("loop").path))
}

@Test func fakeListsImplicitDirectories() {
    let fs = FakeDiskFS(files: ["/h/a/x": (10, .distantPast), "/h/a/y/z": (5, .distantPast)])
    #expect(fs.list("/h/a")?.sorted() == ["x", "y"])
    #expect(fs.size("/h/a") == 15 && fs.isDirectory("/h/a/y") && fs.list("/nope") == nil)
}

@Test func leavesFallBackToSelf() {
    let item = DiskItem(id: "a", title: "a", detail: nil, category: .safe, bytes: 1)
    #expect(item.leaves == [item])
}

@Test func realSizeOfSymlinkRootIsZero() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let target = dir.appendingPathComponent("target")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try Data(count: 1_000_000).write(to: target.appendingPathComponent("a.bin"))
    let link = dir.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    #expect(RealDiskFS().size(link.path) == 0)
}
