import Foundation
@testable import MonitorCore

final class FakeDiskFS: DiskFS {
    let files: [String: (bytes: UInt64, modified: Date)]
    let unreadable: Set<String>
    let plists: [String: [String: String]]

    init(files: [String: (bytes: UInt64, modified: Date)], unreadable: Set<String> = [], plists: [String: [String: String]] = [:]) {
        self.files = files
        self.unreadable = unreadable
        self.plists = plists
    }

    private func under(_ path: String) -> [String] {
        let prefix = path.hasSuffix("/") ? path : path + "/"
        return files.keys.filter { $0.hasPrefix(prefix) }
    }

    func list(_ path: String) -> [String]? {
        if unreadable.contains(path) { return nil }
        let prefix = path.hasSuffix("/") ? path : path + "/"
        let names = Set(under(path).map { String($0.dropFirst(prefix.count)).split(separator: "/").first.map(String.init) ?? "" })
        return names.isEmpty ? nil : Array(names)
    }

    func isDirectory(_ path: String) -> Bool { files[path] == nil && !under(path).isEmpty }

    func exists(_ path: String) -> Bool { files[path] != nil || !under(path).isEmpty }

    func modified(_ path: String) -> Date? {
        if let f = files[path] { return f.modified }
        return under(path).compactMap { files[$0]?.modified }.max()
    }

    func size(_ path: String) -> UInt64 {
        if let f = files[path] { return f.bytes }
        return under(path).reduce(0) { $0 + (files[$1]?.bytes ?? 0) }
    }

    func plistString(_ path: String, key: String) -> String? { plists[path]?[key] }
}

final class FakeAppIndex: AppIndex {
    let bundles: [String: String]
    let names: [String: String]
    let tools: Set<String>

    init(bundles: [String: String] = [:], names: [String: String] = [:], tools: Set<String> = []) {
        self.bundles = Dictionary(bundles.map { ($0.key.lowercased(), $0.value) }) { a, _ in a }
        self.names = names
        self.tools = tools
    }

    func appPath(bundleID: String) -> String? { bundles[bundleID.lowercased()] }

    var bundleIDs: Set<String> { Set(bundles.keys) }

    func appPath(matchingName name: String) -> String? {
        let query = AppNameMatch.normalize(name)
        return names.first { AppNameMatch.matches(query, AppNameMatch.normalize($0.key)) }?.value
    }

    func isKnownTool(_ name: String) -> Bool {
        let query = AppNameMatch.normalize(name)
        return tools.contains { AppNameMatch.matches(query, AppNameMatch.normalize($0)) }
    }
}
