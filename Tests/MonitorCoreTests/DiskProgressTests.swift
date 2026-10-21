import Testing
import Foundation
@testable import MonitorCore

private let mb: UInt64 = 1_048_576

@Test func progressReportsNodeModulesCountsAndStages() {
    let fs = FakeDiskFS(files: [
        "/h/d/a/package.json": (1, .distantPast), "/h/d/a/node_modules/x": (60 * mb, .distantPast),
        "/h/d/b/package.json": (1, .distantPast), "/h/d/b/node_modules/x": (60 * mb, .distantPast),
    ])
    let log = Locked<[DiskProgress]>([])
    _ = DiskAnalyzer.analyze(fs: fs, home: "/h", apps: FakeAppIndex(), volume: (1_000 * mb, 100 * mb), docker: nil, runningBundleIDs: [], busyPaths: [], now: .distantPast,
                             progress: { p in log.mutate { $0.append(p) } })
    let stages = log.value.map(\.stage)
    #expect(stages.contains("Medindo caches") && stages.contains("Procurando sobras") && stages.contains("Medindo dados de apps"))
    #expect(log.value.contains(DiskProgress(stage: "Medindo node_modules", done: 2, total: 2)))
}

@Test func partialReportsArriveInOrderBeforeFinal() {
    let fs = FakeDiskFS(files: ["/h/.npm/_cacache/x": (100 * mb, .distantPast),
                                "/h/Library/Application Support/com.gone.app/x": (100 * mb, .distantPast),
                                "/h/Library/Preferences/com.gone.app.plist": (1, .distantPast)])
    let parts = Locked<[DiskReport]>([])
    let final = DiskAnalyzer.analyze(fs: fs, home: "/h", apps: FakeAppIndex(), volume: (1_000 * mb, 100 * mb), docker: nil, runningBundleIDs: [], busyPaths: [], now: .distantPast,
                                     partial: { r in parts.mutate { $0.append(r) } })
    #expect(parts.value.count == 2)
    #expect(parts.value[0].items.allSatisfy { $0.category == .safe } && parts.value[1].bytes(.leftover) > 0)
    #expect(final.bytes(.safe) == parts.value[0].bytes(.safe))
}

@Test func parallelSizingMatchesSequentialWithHardLinks() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let a = dir.appendingPathComponent(".npm/_cacache"), b = dir.appendingPathComponent(".cache/uv")
    try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try Data(count: 60_000_000).write(to: a.appendingPathComponent("f"))
    try FileManager.default.linkItem(at: a.appendingPathComponent("f"), to: b.appendingPathComponent("f"))
    let items = SafeCatalog.scan(fs: RealDiskFS(), home: dir.path, runningBundleIDs: [], busyPaths: [], skipProtectedHomeFolders: false)
    #expect(items.reduce(0) { $0 + $1.bytes } < 70_000_000)
}
