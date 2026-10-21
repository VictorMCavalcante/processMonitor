import Testing
import Foundation
@testable import MonitorCore

private let mb: UInt64 = 1_048_576

@Test func categoriesAreDisjointAndSystemOtherIsRemainder() {
    let fs = FakeDiskFS(files: [
        "/h/Library/Application Support/com.apple.TCC/x": (1, .distantPast),
        "/h/Library/Application Support/Steam/games": (75_000 * mb, .distantPast),
        "/h/Library/Containers/d/Data/v": (21_000 * mb, .distantPast),
        "/h/.npm/_cacache/x": (4_200 * mb, .distantPast),
    ], plists: ["/h/Library/Containers/d/.com.apple.containermanagerd.metadata.plist": ["MCMMetadataIdentifier": "com.docker.docker"]])
    let apps = FakeAppIndex(bundles: ["com.docker.docker": "/Applications/Docker.app"], names: ["steam": "/Applications/Steam.app"])
    let r = DiskAnalyzer.analyze(fs: fs, home: "/h", apps: apps, volume: (460_000 * mb, 73_000 * mb),
                                 docker: DockerDiskUsage(danglingAndBuildCache: 6_000 * mb, unusedImages: 9_000 * mb, unusedImageNames: ["wra-api"]),
                                 runningBundleIDs: [], busyPaths: [], now: .distantPast)
    #expect(r.bytes(.safe) == 4_200 * mb + 15_000 * mb)
    #expect(r.items.first { $0.id == "app:/Applications/Docker.app" }?.bytes == 6_000 * mb)
    #expect(r.items.first { $0.id == "docker:unused" }?.checkedByDefault == false)
    #expect(r.systemOther == r.used - r.bytes(.safe) - r.bytes(.leftover) - r.bytes(.appData) && !r.protectedSkipped)
}

@Test func dockerClosedShowsPlaceholderAndNoAccessSetsFlag() {
    let fs = FakeDiskFS(files: ["/h/Library/Containers/com.docker.docker/Data/x": (21_000 * mb, .distantPast)])
    let r = DiskAnalyzer.analyze(fs: fs, home: "/h", apps: FakeAppIndex(), volume: (100, 10), docker: nil, runningBundleIDs: [], busyPaths: [], now: .distantPast)
    #expect(r.protectedSkipped && r.items.contains { $0.id == "docker:closed" && $0.detail == "abra o Docker para medir" })
}

@Test func safeCacheInsideAppFolderIsNotCountedTwice() {
    let fs = FakeDiskFS(files: ["/h/Library/Caches/JetBrains/x": (2_000 * mb, .distantPast)])
    let r = DiskAnalyzer.analyze(fs: fs, home: "/h", apps: FakeAppIndex(), volume: (10_000 * mb, 1_000 * mb), docker: nil, runningBundleIDs: [], busyPaths: [], now: .distantPast)
    #expect(r.bytes(.safe) == 2_000 * mb && r.bytes(.leftover) == 0 && r.bytes(.appData) == 0)
}

@Test func appDataGroupsByAppAndOrdersReport() {
    let fs = FakeDiskFS(files: [
        "/h/Library/Application Support/com.apple.TCC/x": (1, .distantPast),
        "/h/Library/Application Support/com.apple.wallpaper/w": (3_000 * mb, .distantPast),
        "/h/Library/Application Support/Code/data": (800 * mb, .distantPast),
        "/h/Library/Caches/JetBrains/x": (900 * mb, .distantPast),
        "/h/Library/Group Containers/UBF8T346G9.com.microsoft.vscode.shared/g": (500 * mb, .distantPast),
        "/h/Library/Application Support/Tiny/t": (10 * mb, .distantPast),
    ])
    let apps = FakeAppIndex(bundles: ["com.microsoft.VSCode": "/Applications/Visual Studio Code.app"], names: ["code": "/Applications/Visual Studio Code.app", "tiny": "/Applications/Tiny.app"])
    let r = DiskAnalyzer.analyze(fs: fs, home: "/h", apps: apps, volume: (100_000 * mb, 1_000 * mb), docker: nil, runningBundleIDs: [], busyPaths: [], now: .distantPast)
    let code = r.items.first { $0.id == "app:/Applications/Visual Studio Code.app" }
    #expect(code?.bytes == 1_300 * mb && code?.title == "Visual Studio Code" && code?.action == DiskAction.none)
    #expect(r.items.first { $0.id == "wallpaper" }?.title == "Wallpapers dinâmicos")
    #expect(!r.items.contains { $0.id == "app:/Applications/Tiny.app" })
    #expect(r.items.map(\.id) == ["JetBrains cache", "wallpaper", "app:/Applications/Visual Studio Code.app"])
}

@Test func noAccessNeverListsProtectedContainers() {
    let fs = FakeDiskFS(files: [
        "/h/Library/Containers/com.gone.app/Data/a": (900 * mb, .distantPast),
        "/h/Library/Group Containers/ABCDE12345.com.gone.app/b": (900 * mb, .distantPast),
        "/h/Library/Application Support/x/y": (1, .distantPast),
    ])
    let r = DiskAnalyzer.analyze(fs: fs, home: "/h", apps: FakeAppIndex(), volume: (10_000 * mb, 1_000 * mb), docker: nil, runningBundleIDs: [], busyPaths: [], now: .distantPast)
    #expect(r.protectedSkipped)
    #expect(!fs.listed.contains { $0.hasPrefix("/h/Library/Containers") || $0.hasPrefix("/h/Library/Group Containers") })
}

@Test func appleAppSupportFoldersAreNotAppData() {
    let fs = FakeDiskFS(files: [
        "/h/Library/Application Support/com.apple.TCC/x": (1, .distantPast),
        "/h/Library/Application Support/com.apple.Music/m": (3_000 * mb, .distantPast),
    ])
    let apps = FakeAppIndex(bundles: ["com.apple.Music": "/System/Applications/Music.app"])
    let r = DiskAnalyzer.analyze(fs: fs, home: "/h", apps: apps, volume: (100_000 * mb, 1_000 * mb), docker: nil, runningBundleIDs: [], busyPaths: [], now: .distantPast)
    #expect(!r.items.contains { $0.category == .appData })
}
