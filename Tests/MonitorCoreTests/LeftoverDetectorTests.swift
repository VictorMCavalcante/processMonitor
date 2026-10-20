import Testing
import Foundation
@testable import MonitorCore

private let mb: UInt64 = 1_048_576

@Test func ownerFromContainerMetadataAndGroupPrefix() {
    let fs = FakeDiskFS(files: ["/h/Library/Containers/x/Data/a": (1, .distantPast)], plists: ["/h/Library/Containers/x/.com.apple.containermanagerd.metadata.plist": ["MCMMetadataIdentifier": "net.whatsapp.WhatsApp"]])
    #expect(LeftoverDetector.ownerBundleID(folder: "x", in: "/h/Library/Containers", fs: fs) == "net.whatsapp.WhatsApp")
    #expect(LeftoverDetector.ownerBundleID(folder: "6N38VWS5BX.ru.keepcoder.Telegram", in: "/h/Library/Group Containers", fs: fs) == "ru.keepcoder.Telegram")
    #expect(LeftoverDetector.ownerBundleID(folder: "22MMUN2RN5.lv", in: "/h/Library/Group Containers", fs: fs) == nil)
    #expect(LeftoverDetector.ownerBundleID(folder: "com.openai.atlas.plist", in: "/h/Library/Preferences", fs: fs) == "com.openai.atlas")
}

@Test func confidentLeftoverGroupsAcrossFolders() {
    let fs = FakeDiskFS(files: [
        "/h/Library/Application Support/com.openai.atlas/d": (800 * mb, .distantPast),
        "/h/Library/Caches/com.openai.atlas/c": (57 * mb, .distantPast),
        "/h/Library/Application Support/com.apple.wallpaper/w": (900 * mb, .distantPast),
        "/h/Library/Application Support/com.tinyspeck.slackmacgap/s": (900 * mb, .distantPast),
    ])
    let items = LeftoverDetector.detect(fs: fs, home: "/h", apps: FakeAppIndex(bundles: ["com.tinyspeck.slackmacgap": "/Applications/Slack.app"]), includeProtected: false)
    #expect(items.map(\.id) == ["leftover:com.openai.atlas"])
    #expect(items[0].bytes == 857 * mb && items[0].detail == "Application Support · Caches" && items[0].checkedByDefault == false)
}

@Test func maybeLeftoverExcludesDataInstalledToolsAndUnreadable() {
    let fs = FakeDiskFS(files: [
        "/h/Library/Application Support/Farming Simulator 2025/a": (199 * mb, .distantPast),
        "/h/Library/Application Support/MySQL/db": (490 * mb, .distantPast),
        "/h/Library/Application Support/Steam/g": (900 * mb, .distantPast),
        "/h/Library/Application Support/GitKrakenCLI/x": (177 * mb, .distantPast),
        "/h/Library/Application Support/Locked/x": (300 * mb, .distantPast),
        "/h/Library/Application Support/MobileSync/Backup/x": (900 * mb, .distantPast),
    ], unreadable: ["/h/Library/Application Support/Locked"])
    let apps = FakeAppIndex(names: ["steam": "/Applications/Steam.app"], tools: ["gitkrakencli"])
    let items = LeftoverDetector.detect(fs: fs, home: "/h", apps: apps, includeProtected: false)
    #expect(items.map(\.title) == ["Farming Simulator 2025"] && items[0].category == .maybeLeftover)
}

@Test func protectedFoldersSkippedWithoutAccess() {
    let fs = FakeDiskFS(files: ["/h/Library/Containers/x/Data/a": (900 * mb, .distantPast)], plists: ["/h/Library/Containers/x/.com.apple.containermanagerd.metadata.plist": ["MCMMetadataIdentifier": "com.gone.app"]])
    #expect(LeftoverDetector.detect(fs: fs, home: "/h", apps: FakeAppIndex(), includeProtected: false).isEmpty)
    #expect(LeftoverDetector.detect(fs: fs, home: "/h", apps: FakeAppIndex(), includeProtected: true).count == 1)
}

@Test func systemIndexIgnoresTrashedApps() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let app = home.appendingPathComponent(".Trash/Gone.app/Contents")
    try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    try (["CFBundleIdentifier": "com.example.gone.test", "CFBundleName": "Gone"] as NSDictionary).write(to: app.appendingPathComponent("Info.plist"))
    #expect(SystemAppIndex(home: home.path).appPath(bundleID: "com.example.gone.test") == nil)
}

@Test func leftoverTitleFromPreferencesAndSavedState() {
    let fs = FakeDiskFS(files: [
        "/h/Library/Saved Application State/com.gone.thing.savedState/s": (40 * mb, .distantPast),
        "/h/Library/Preferences/com.gone.thing.plist": (20 * mb, .distantPast),
    ], plists: ["/h/Library/Preferences/com.gone.thing.plist": ["CFBundleName": "Gone Thing"]])
    let items = LeftoverDetector.detect(fs: fs, home: "/h", apps: FakeAppIndex(), includeProtected: false)
    #expect(items.map(\.title) == ["Gone Thing"] && items[0].detail == "Preferences · Saved Application State")
    #expect(items[0].revealPath == "/h/Library/Saved Application State/com.gone.thing.savedState")
}

@Test func relatedInstalledBundlesAreNotLeftovers() {
    let fs = FakeDiskFS(files: [
        "/h/Library/Caches/com.microsoft.VSCode.ShipIt/a": (300 * mb, .distantPast),
        "/h/Library/Group Containers/group.com.docker/b": (300 * mb, .distantPast),
    ])
    let apps = FakeAppIndex(bundles: ["com.microsoft.VSCode": "/Applications/VSCode.app", "com.docker.docker": "/Applications/Docker.app"])
    #expect(LeftoverDetector.detect(fs: fs, home: "/h", apps: apps, includeProtected: true).isEmpty)
}
