import Testing
import Foundation
@testable import MonitorCore

private let mb: UInt64 = 1_048_576

@Test func catalogMergesPathsAndSkipsSmall() {
    let fs = FakeDiskFS(files: ["/h/Library/Caches/ms-playwright/a": (60 * mb, .distantPast), "/h/Library/Caches/ms-playwright-mcp/b": (40 * mb, .distantPast), "/h/.npm/_cacache/c": (10 * mb, .distantPast)])
    let items = SafeCatalog.scan(fs: fs, home: "/h", runningBundleIDs: [], busyPaths: [], skipProtectedHomeFolders: false)
    #expect(items.map(\.title) == ["Playwright browsers"] && items[0].bytes == 100 * mb && items[0].checkedByDefault)
    #expect(items[0].action == .trash(["/h/Library/Caches/ms-playwright", "/h/Library/Caches/ms-playwright-mcp"]))
}

@Test func huggingFaceUncheckedAndRunningOwnerWarned() {
    let fs = FakeDiskFS(files: ["/h/.cache/huggingface/hub/m": (3000 * mb, .distantPast), "/h/.cache/huggingface/xet/n": (100 * mb, .distantPast),
                                "/h/.cache/huggingface/token": (1, .distantPast), "/h/Library/Caches/JetBrains/x": (2000 * mb, .distantPast)])
    let items = SafeCatalog.scan(fs: fs, home: "/h", runningBundleIDs: ["com.jetbrains.intellij"], busyPaths: [], skipProtectedHomeFolders: false)
    let hf = items.first { $0.title == "Hugging Face models" }, jb = items.first { $0.title == "JetBrains cache" }
    #expect(hf?.checkedByDefault == false && hf?.warning == "baixar de novo é lento" && hf?.bytes == 3100 * mb)
    #expect(hf?.action == .trash(["/h/.cache/huggingface/hub", "/h/.cache/huggingface/xet"]))
    #expect(jb?.checkedByDefault == false && jb?.warning == "feche o app primeiro" && jb?.ownerBundlePrefix == "com.jetbrains")
}

@Test func nodeModulesGroupedOldestFirstSkippingLibraryAndBusy() {
    let old = Date(timeIntervalSince1970: 1_000), new = Date(timeIntervalSince1970: 2_000)
    let fs = FakeDiskFS(files: [
        "/h/dev/a/package.json": (1, old), "/h/dev/a/node_modules/x": (40 * mb, old),
        "/h/dev/b/package.json": (1, new), "/h/dev/b/node_modules/x": (30 * mb, new),
        "/h/dev/c/node_modules/x": (90 * mb, old),
        "/h/Library/z/package.json": (1, old), "/h/Library/z/node_modules/x": (90 * mb, old),
    ])
    let g = SafeCatalog.scan(fs: fs, home: "/h", runningBundleIDs: [], busyPaths: ["/h/dev/b/src"], skipProtectedHomeFolders: false).first { $0.id == "node_modules" }
    #expect(g?.title == "node_modules · 2 projetos" && g?.bytes == 70 * mb)
    #expect(g?.children.map(\.title) == ["a", "b"] && g?.children[1].checkedByDefault == false && g?.children[1].warning == "em uso")
}

@Test func ownerPrefixSetEvenWhenOwnerNotRunning() {
    let fs = FakeDiskFS(files: ["/h/Library/Caches/JetBrains/x": (2000 * mb, .distantPast)])
    let jb = SafeCatalog.scan(fs: fs, home: "/h", runningBundleIDs: [], busyPaths: [], skipProtectedHomeFolders: false).first { $0.title == "JetBrains cache" }
    #expect(jb?.ownerBundlePrefix == "com.jetbrains" && jb?.checkedByDefault == true && jb?.warning == nil)
    let r = DiskCleaner.clean(jb.map { [$0] } ?? [], runningBundleIDs: ["com.jetbrains.intellij"], exists: { _ in true }, trash: { _ in }, docker: { _ in nil })
    #expect(r.trashedBytes == 0 && r.failures == ["JetBrains cache: feche o app primeiro"])
}

@Test func nodeModulesWalkSkipsProtectedFoldersAndPackages() {
    let fs = FakeDiskFS(files: [
        "/h/Documents/p/package.json": (1, .distantPast), "/h/Documents/p/node_modules/x": (60 * mb, .distantPast),
        "/h/Music/m/package.json": (1, .distantPast), "/h/Music/m/node_modules/x": (60 * mb, .distantPast),
        "/h/dev/Tool.app/Contents/package.json": (1, .distantPast), "/h/dev/Tool.app/Contents/node_modules/x": (60 * mb, .distantPast),
        "/h/dev/Lib.photoslibrary/package.json": (1, .distantPast), "/h/dev/Lib.photoslibrary/node_modules/x": (60 * mb, .distantPast),
        "/h/dev/a/package.json": (1, .distantPast), "/h/dev/a/node_modules/x": (60 * mb, .distantPast),
    ])
    let skipped = SafeCatalog.scan(fs: fs, home: "/h", runningBundleIDs: [], busyPaths: [], skipProtectedHomeFolders: true).first { $0.id == "node_modules" }
    #expect(skipped?.children.map(\.id) == ["/h/dev/a/node_modules"])
    #expect(!fs.listed.contains { $0.hasPrefix("/h/Documents") || $0.hasPrefix("/h/Music") || $0.hasSuffix(".app") || $0.hasSuffix(".photoslibrary") })
    let all = SafeCatalog.scan(fs: fs, home: "/h", runningBundleIDs: [], busyPaths: [], skipProtectedHomeFolders: false).first { $0.id == "node_modules" }
    #expect(all?.children.map(\.id).sorted() == ["/h/Documents/p/node_modules", "/h/Music/m/node_modules", "/h/dev/a/node_modules"])
}

@Test func aerialVideosAreSafeAndChecked() {
    let fs = FakeDiskFS(files: ["/h/Library/Application Support/com.apple.wallpaper/aerials/videos/a.mov": (9_000 * mb, .distantPast)])
    let w = SafeCatalog.scan(fs: fs, home: "/h", runningBundleIDs: [], busyPaths: [], skipProtectedHomeFolders: false).first { $0.title == "Wallpapers e protetores aéreos" }
    #expect(w?.checkedByDefault == true && w?.warning == "o macOS baixa de novo se você usar um fundo animado")
}
