import Foundation

public struct IgnoreKey: Hashable, Codable, Sendable {
    public var raw: String

    public init(raw: String) { self.raw = raw }

    public static func of(_ row: ProcessRow) -> IgnoreKey {
        let id = row.identified
        if let app = id.appBundlePath { return IgnoreKey(raw: "app:\(app)") }
        switch id.kind {
        case .devServer, .claudeSession, .mcpServer:
            return IgnoreKey(raw: "\(id.kind.rawValue):\(id.project ?? row.snapshot.executablePath ?? row.snapshot.name)")
        default:
            return IgnoreKey(raw: "exe:\(row.snapshot.executablePath ?? row.snapshot.name)")
        }
    }
}

public final class IgnoreList: @unchecked Sendable {
    private struct Entry: Codable { var key: IgnoreKey; var label: String }
    private let defaults: UserDefaults
    private let storageKey = "ignoreList"
    private var entries: [Entry]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = (defaults.data(forKey: storageKey)).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }

    public func contains(_ k: IgnoreKey) -> Bool { entries.contains { $0.key == k } }

    public func add(_ k: IgnoreKey, label: String) {
        guard !contains(k) else { return }
        entries.append(Entry(key: k, label: label))
        save()
    }

    public func remove(_ k: IgnoreKey) {
        entries.removeAll { $0.key == k }
        save()
    }

    public var all: [(key: IgnoreKey, label: String)] { entries.map { ($0.key, $0.label) } }

    private func save() {
        defaults.set(try? JSONEncoder().encode(entries), forKey: storageKey)
    }
}
