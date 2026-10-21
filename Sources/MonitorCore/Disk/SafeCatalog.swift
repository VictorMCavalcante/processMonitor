import Foundation

public enum SafeCatalog {
    private struct Entry {
        let title: String
        let paths: [String]
        var owner: String? = nil
        var warning: String? = nil
        var checked = true
    }

    private static let entries: [Entry] = [
        Entry(title: "npm cache", paths: [".npm/_cacache"]),
        Entry(title: "pnpm", paths: ["Library/Caches/pnpm", "Library/pnpm/store"]),
        Entry(title: "Yarn cache", paths: ["Library/Caches/Yarn"]),
        Entry(title: "uv cache", paths: [".cache/uv"]),
        Entry(title: "Playwright browsers", paths: ["Library/Caches/ms-playwright", "Library/Caches/ms-playwright-mcp"]),
        Entry(title: "Homebrew cache", paths: ["Library/Caches/Homebrew"]),
        Entry(title: "Xcode DerivedData", paths: ["Library/Developer/Xcode/DerivedData"], owner: "com.apple.dt.Xcode"),
        Entry(title: "JetBrains cache", paths: ["Library/Caches/JetBrains"], owner: "com.jetbrains"),
        Entry(title: "Gradle cache", paths: [".gradle/caches"]),
        Entry(title: "Hugging Face models", paths: [".cache/huggingface/hub", ".cache/huggingface/xet"], warning: "baixar de novo é lento", checked: false),
        Entry(title: "Wallpapers e protetores aéreos", paths: ["Library/Application Support/com.apple.wallpaper/aerials/videos"], warning: "o macOS baixa de novo se você usar um fundo animado"),
    ]

    private static let maxDepth = 6
    private static let protectedHomeFolders: Set<String> = ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music"]
    private static let packageSuffixes = [".photoslibrary", ".musiclibrary", ".app", ".bundle", ".framework"]

    public static func scan(fs: DiskFS, home: String, runningBundleIDs: Set<String>, busyPaths: [String], skipProtectedHomeFolders: Bool) -> [DiskItem] {
        var items: [DiskItem] = []
        for entry in entries {
            let paths = entry.paths.map { home + "/" + $0 }.filter { fs.exists($0) }
            let bytes = paths.reduce(UInt64(0)) { $0 + fs.size($1) }
            guard let first = paths.first, bytes >= DiskRules.minItemBytes else { continue }
            let running = entry.owner.map { owner in runningBundleIDs.contains { $0.hasPrefix(owner) } } ?? false
            items.append(DiskItem(
                id: entry.title, title: entry.title, detail: nil, category: .safe, bytes: bytes,
                action: .trash(paths),
                checkedByDefault: entry.checked && !running,
                warning: running ? "feche o app primeiro" : entry.warning,
                ownerBundlePrefix: entry.owner,
                revealPath: first))
        }
        if let group = nodeModules(fs: fs, home: home, busyPaths: busyPaths, skipProtected: skipProtectedHomeFolders) { items.append(group) }
        return items
    }

    private static func nodeModules(fs: DiskFS, home: String, busyPaths: [String], skipProtected: Bool) -> DiskItem? {
        var found: [String] = []
        func walk(_ dir: String, _ depth: Int) {
            guard depth <= maxDepth, let names = fs.list(dir) else { return }
            for name in names.sorted() where !name.hasPrefix(".") && name != "Library" && !packageSuffixes.contains(where: name.hasSuffix)
                && !(skipProtected && dir == home && protectedHomeFolders.contains(name)) {
                let path = dir + "/" + name
                if name == "node_modules" {
                    if fs.exists(dir + "/package.json") { found.append(path) }
                } else if fs.isDirectory(path) {
                    walk(path, depth + 1)
                }
            }
        }
        walk(home, 1)

        let children = found.map { path -> DiskItem in
            let project = (path as NSString).deletingLastPathComponent
            let busy = busyPaths.contains { $0 == project || $0.hasPrefix(project + "/") }
            let modified = [fs.modified(project + "/package.json"), fs.modified(project)].compactMap { $0 }.max()
            return DiskItem(
                id: path, title: (project as NSString).lastPathComponent,
                detail: String(project.dropFirst(home.count + 1)), category: .safe, bytes: fs.size(path),
                action: .trash([path]), checkedByDefault: !busy, warning: busy ? "em uso" : nil,
                revealPath: path, modified: modified)
        }.sorted { ($0.modified ?? .distantPast) < ($1.modified ?? .distantPast) }

        let total = children.reduce(UInt64(0)) { $0 + $1.bytes }
        guard let first = children.first, total >= DiskRules.minItemBytes else { return nil }
        return DiskItem(
            id: "node_modules", title: "node_modules · \(children.count) projetos", detail: nil,
            category: .safe, bytes: total, checkedByDefault: true,
            revealPath: first.revealPath, children: children)
    }
}
