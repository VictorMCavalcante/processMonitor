import Foundation

public struct DockerDiskUsage: Sendable, Equatable {
    public var danglingAndBuildCache: UInt64
    public var unusedImages: UInt64
    public var unusedImageNames: [String]

    public init(danglingAndBuildCache: UInt64, unusedImages: UInt64, unusedImageNames: [String]) {
        self.danglingAndBuildCache = danglingAndBuildCache
        self.unusedImages = unusedImages
        self.unusedImageNames = unusedImageNames
    }
}

public struct DiskProgress: Sendable, Equatable {
    public var stage: String
    public var done: Int?
    public var total: Int?

    public init(stage: String, done: Int? = nil, total: Int? = nil) {
        self.stage = stage
        self.done = done
        self.total = total
    }
}

public struct DiskReport: Sendable, Equatable {
    public var total: UInt64
    public var free: UInt64
    public var items: [DiskItem]
    public var protectedSkipped: Bool
    public var dockerMeasured: Bool
    public var scannedAt: Date

    public func bytes(_ c: DiskCategory) -> UInt64 {
        let cats: Set<DiskCategory> = c == .leftover ? [.leftover, .maybeLeftover] : [c]
        return items.filter { cats.contains($0.category) }.reduce(0) { $0 + $1.bytes }
    }

    public var used: UInt64 { total > free ? total - free : 0 }

    public var systemOther: UInt64 {
        let counted = bytes(.safe) + bytes(.leftover) + bytes(.appData)
        return used > counted ? used - counted : 0
    }
}

private final class Unchecked<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

private final class ClaimedFS: DiskFS {
    let base: DiskFS
    var claimed: [String] = []

    init(_ base: DiskFS) { self.base = base }

    func isClaimed(_ path: String) -> Bool { claimed.contains { path == $0 || path.hasPrefix($0 + "/") } }

    func list(_ path: String) -> [String]? { base.list(path) }
    func isDirectory(_ path: String) -> Bool { base.isDirectory(path) }
    func exists(_ path: String) -> Bool { base.exists(path) }
    func modified(_ path: String) -> Date? { base.modified(path) }
    func plistString(_ path: String, key: String) -> String? { base.plistString(path, key: key) }

    func size(_ path: String) -> UInt64 {
        if isClaimed(path) { return 0 }
        guard claimed.contains(where: { $0.hasPrefix(path + "/") }) else { return base.size(path) }
        return (base.list(path) ?? []).reduce(0) { $0 + size(path + "/" + $1) }
    }
}

public enum DiskAnalyzer {
    public static let parallelism = 4

    static func parallelMap<T>(_ count: Int, onDone: (Int) -> Void = { _ in }, _ work: (Int) -> T) -> [T] {
        withoutActuallyEscaping(work) { work in
            withoutActuallyEscaping(onDone) { onDone in
                let run = Unchecked((work: work, onDone: onDone, results: [T?](repeating: nil, count: count), next: 0, done: 0))
                let lock = NSLock()
                DispatchQueue.concurrentPerform(iterations: min(parallelism, count)) { _ in
                    while true {
                        let i = lock.withLock { run.value.next += 1; return run.value.next - 1 }
                        guard i < count else { return }
                        let result = run.value.work(i)
                        lock.withLock {
                            run.value.results[i] = result
                            run.value.done += 1
                            run.value.onDone(run.value.done)
                        }
                    }
                }
                return run.value.results.map { $0! }
            }
        }
    }

    public static func hasFullDiskAccess(fs: DiskFS, home: String) -> Bool {
        fs.list(home + "/Library/Application Support/com.apple.TCC") != nil
    }

    public static func volume(home: String) -> (total: UInt64, free: UInt64) {
        let v = try? URL(fileURLWithPath: home).resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        return (UInt64(max(0, v?.volumeTotalCapacity ?? 0)), UInt64(max(0, v?.volumeAvailableCapacityForImportantUsage ?? 0)))
    }

    public static func analyze(fs: DiskFS, home: String, apps: AppIndex, volume: (total: UInt64, free: UInt64), docker: DockerDiskUsage?,
                               runningBundleIDs: Set<String>, busyPaths: [String], now: Date,
                               progress: @Sendable (DiskProgress) -> Void = { _ in }, partial: @Sendable (DiskReport) -> Void = { _ in }) -> DiskReport {
        let access = hasFullDiskAccess(fs: fs, home: home)
        let claimedFS = ClaimedFS(fs)
        func report(_ items: [DiskItem]) -> DiskReport {
            DiskReport(total: volume.total, free: volume.free, items: items, protectedSkipped: !access, dockerMeasured: docker != nil, scannedAt: now)
        }

        progress(DiskProgress(stage: "Medindo caches"))
        var safe = SafeCatalog.scan(fs: fs, home: home, runningBundleIDs: runningBundleIDs, busyPaths: busyPaths, skipProtectedHomeFolders: !access,
                                    progress: { progress(DiskProgress(stage: "Medindo node_modules", done: $0, total: $1)) })
        claimedFS.claimed = safe.flatMap(\.leaves).flatMap(paths)
        if let docker {
            safe += [
                DiskItem(id: "docker:dangling", title: "Docker · imagens órfãs e build cache", detail: nil, category: .safe,
                         bytes: docker.danglingAndBuildCache, action: .docker(.danglingAndBuildCache), checkedByDefault: true),
                DiskItem(id: "docker:unused", title: "Docker · imagens sem nenhum container", detail: docker.unusedImageNames.joined(separator: ", "),
                         category: .safe, bytes: docker.unusedImages, action: .docker(.unusedImages), checkedByDefault: false,
                         warning: "o Docker baixa de novo quando você subir o projeto"),
            ].filter { $0.bytes >= DiskRules.minItemBytes }
        }
        safe.sort { $0.bytes > $1.bytes }
        let dockerBytes = safe.filter { $0.id.hasPrefix("docker:") }.reduce(UInt64(0)) { $0 + $1.bytes }
        if docker == nil, fs.exists(home + "/Library/Containers/com.docker.docker") {
            safe.append(DiskItem(id: "docker:closed", title: "Docker", detail: "abra o Docker para medir", category: .safe, bytes: 0))
        }
        partial(report(safe))

        progress(DiskProgress(stage: "Procurando sobras"))

        let leftovers = LeftoverDetector.detect(fs: claimedFS, home: home, apps: apps, includeProtected: access).compactMap { item -> DiskItem? in
            var item = item
            let kept = paths(item).filter { !claimedFS.isClaimed($0) }
            guard !kept.isEmpty else { return nil }
            item.action = .trash(kept)
            if let reveal = item.revealPath, !kept.contains(reveal) { item.revealPath = kept.first }
            return item
        }
        claimedFS.claimed += leftovers.flatMap(paths)
        partial(report(safe + leftovers))

        var appData = appData(fs: claimedFS, home: home, apps: apps, includeProtected: access) { progress(DiskProgress(stage: "Medindo dados de apps", done: $0, total: $1)) }
        if let docker = apps.appPath(bundleID: "com.docker.docker"), let i = appData.firstIndex(where: { $0.appPath == docker }) {
            appData[i].bytes = appData[i].bytes > dockerBytes ? appData[i].bytes - dockerBytes : 0
        }
        appData = appData.filter { $0.bytes >= DiskRules.minAppDataBytes }.sorted { $0.bytes > $1.bytes }

        return report(safe + leftovers + appData)
    }

    private static func paths(_ item: DiskItem) -> [String] {
        if case .trash(let p) = item.action { return p }
        return []
    }

    private static func appData(fs: DiskFS, home: String, apps: AppIndex, includeProtected: Bool, progress: @Sendable (Int, Int) -> Void) -> [DiskItem] {
        var candidates: [(path: String, app: String?)] = []
        let places = includeProtected ? ["Application Support", "Containers", "Group Containers"] : ["Application Support"]
        for place in places {
            let parent = home + "/Library/" + place
            for name in (fs.list(parent) ?? []).sorted() {
                let path = parent + "/" + name
                if place == "Application Support", name == "com.apple.wallpaper" {
                    candidates.append((path, nil))
                    continue
                }
                if place == "Application Support", LeftoverDetector.isApple(name) { continue }
                guard let app = owner(name, parent: parent, place: place, fs: fs, apps: apps) else { continue }
                candidates.append((path, app))
            }
        }
        progress(0, candidates.count)
        let sizes = parallelMap(candidates.count, onDone: { progress($0, candidates.count) }) { fs.size(candidates[$0].path) }
        var totals: [String: UInt64] = [:]
        var items: [DiskItem] = []
        for (candidate, bytes) in zip(candidates, sizes) {
            guard let app = candidate.app else {
                items.append(DiskItem(id: "wallpaper", title: "Wallpapers dinâmicos", detail: "remova em Ajustes › Papel de Parede",
                                      category: .appData, bytes: bytes, revealPath: candidate.path))
                continue
            }
            totals[app, default: 0] += bytes
        }
        return items + totals.map { app, bytes in
            DiskItem(id: "app:" + app, title: ((app as NSString).lastPathComponent as NSString).deletingPathExtension,
                     detail: nil, category: .appData, bytes: bytes, appPath: app)
        }
    }

    private static func owner(_ name: String, parent: String, place: String, fs: DiskFS, apps: AppIndex) -> String? {
        if let id = LeftoverDetector.ownerBundleID(folder: name, in: parent, fs: fs) {
            if let app = apps.appPath(bundleID: id) { return app }
            if place == "Group Containers" {
                let lower = id.lowercased()
                if let match = apps.bundleIDs.sorted().first(where: { lower.hasPrefix($0) || $0.hasPrefix(lower) }) { return apps.appPath(bundleID: match) }
            }
        }
        return place == "Application Support" ? apps.appPath(matchingName: name) : nil
    }
}
