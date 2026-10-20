import Testing
import Foundation
@testable import MonitorCore

private let mb: UInt64 = 1_048_576

@Test func catalogMergesPathsAndSkipsSmall() {
    let fs = FakeDiskFS(files: ["/h/Library/Caches/ms-playwright/a": (60 * mb, .distantPast), "/h/Library/Caches/ms-playwright-mcp/b": (40 * mb, .distantPast), "/h/.npm/_cacache/c": (10 * mb, .distantPast)])
    let items = SafeCatalog.scan(fs: fs, home: "/h", runningBundleIDs: [], busyPaths: [])
    #expect(items.map(\.title) == ["Playwright browsers"] && items[0].bytes == 100 * mb && items[0].checkedByDefault)
    #expect(items[0].action == .trash(["/h/Library/Caches/ms-playwright", "/h/Library/Caches/ms-playwright-mcp"]))
}

@Test func huggingFaceUncheckedAndRunningOwnerWarned() {
    let fs = FakeDiskFS(files: ["/h/.cache/huggingface/m": (3000 * mb, .distantPast), "/h/Library/Caches/JetBrains/x": (2000 * mb, .distantPast)])
    let items = SafeCatalog.scan(fs: fs, home: "/h", runningBundleIDs: ["com.jetbrains.intellij"], busyPaths: [])
    let hf = items.first { $0.title == "Hugging Face models" }, jb = items.first { $0.title == "JetBrains cache" }
    #expect(hf?.checkedByDefault == false && hf?.warning == "baixar de novo é lento")
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
    let g = SafeCatalog.scan(fs: fs, home: "/h", runningBundleIDs: [], busyPaths: ["/h/dev/b/src"]).first { $0.id == "node_modules" }
    #expect(g?.title == "node_modules · 2 projetos" && g?.bytes == 70 * mb)
    #expect(g?.children.map(\.title) == ["a", "b"] && g?.children[1].checkedByDefault == false && g?.children[1].warning == "em uso")
}
