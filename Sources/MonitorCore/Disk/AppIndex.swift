import Foundation
import CoreServices

public protocol AppIndex: AnyObject {
    func appPath(bundleID: String) -> String?
    var bundleIDs: Set<String> { get }
    func appPath(matchingName name: String) -> String?
    func isKnownTool(_ name: String) -> Bool
}

public enum AppNameMatch {
    public static func normalize(_ name: String) -> String {
        String(name.lowercased().unicodeScalars.filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) })
    }

    public static func matches(_ a: String, _ b: String) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        return min(a.count, b.count) >= 4 && (a.contains(b) || b.contains(a))
    }
}

public final class SystemAppIndex: AppIndex {
    private let bundles: [String: String]
    private let names: [String: String]
    private let tools: Set<String>

    public init(home: String) {
        let fm = FileManager.default
        let fs = RealDiskFS()
        var bundles: [String: String] = [:]
        var names: [String: String] = [:]
        func add(_ app: String) {
            let plist = app + "/Contents/Info.plist"
            let id = fs.plistString(plist, key: "CFBundleIdentifier")
            if let id { bundles[id.lowercased()] = app }
            var keys = [((app as NSString).lastPathComponent as NSString).deletingPathExtension]
            if let name = fs.plistString(plist, key: "CFBundleName") { keys.append(name) }
            if let id, id.split(separator: ".").count >= 2 { keys.append(String(id.split(separator: ".")[1])) }
            for key in keys.map(AppNameMatch.normalize) where !key.isEmpty { names[key] = app }
        }
        for root in ["/Applications", home + "/Applications", "/System/Applications"] {
            for entry in (try? fm.contentsOfDirectory(atPath: root)) ?? [] {
                let path = root + "/" + entry
                if entry.hasSuffix(".app") { add(path); continue }
                for sub in (try? fm.contentsOfDirectory(atPath: path)) ?? [] where sub.hasSuffix(".app") { add(path + "/" + sub) }
            }
        }
        let toolDirs = ["/opt/homebrew/Cellar", "/opt/homebrew/Caskroom", "/usr/local/Cellar", "/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", home + "/.cargo/bin"]
        self.tools = Set(toolDirs.flatMap { (try? fm.contentsOfDirectory(atPath: $0)) ?? [] }.map(AppNameMatch.normalize).filter { !$0.isEmpty })
        self.bundles = bundles
        self.names = names
    }

    public func appPath(bundleID: String) -> String? {
        if let path = bundles[bundleID.lowercased()] { return path }
        let urls = LSCopyApplicationURLsForBundleIdentifier(bundleID as CFString, nil)?.takeRetainedValue() as? [URL] ?? []
        return urls.map(\.path).first { !$0.contains("/.Trash/") && FileManager.default.fileExists(atPath: $0) }
    }

    public var bundleIDs: Set<String> { Set(bundles.keys) }

    public func appPath(matchingName name: String) -> String? {
        let query = AppNameMatch.normalize(name)
        return names.first { AppNameMatch.matches(query, $0.key) }?.value
    }

    public func isKnownTool(_ name: String) -> Bool {
        let query = AppNameMatch.normalize(name)
        return tools.contains { AppNameMatch.matches(query, $0) }
    }
}
