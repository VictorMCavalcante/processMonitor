import Foundation

public enum LeftoverDetector {
    private static let places = ["Application Support", "Caches", "Containers", "Group Containers", "Preferences", "Logs", "Saved Application State", "HTTPStorages", "WebKit"]
    private static let protectedPlaces: Set<String> = ["Containers", "Group Containers"]
    private static let maybePlaces: Set<String> = ["Application Support", "Caches", "Logs"]

    private static let appleNames: Set<String> = Set(["AddressBook", "Animoji", "CallHistoryDB", "CallHistoryTransactions", "CloudDocs", "CrashReporter", "DiskImages", "Dock", "FileProvider", "icdd", "iCloud", "Knowledge", "MobileSync", "networkserviceproxy", "SyncServices", "Accounts", "ControlCenter", "DifferentialPrivacy", "FaceTime", "Quick Look", "SpeechRecognitionCore", "Spotlight", "TrustedPeersHelper", "AppStore", "Mail", "Safari", "Photos", "Siri", "homed", "identityservicesd", "locationaccessstored", "videosubscriptionsd"].map { $0.lowercased() })
    private static let dataLike = ["mysql", "postgres", "mongo", "redis", "sqlite", "database", "backup", "save", "mobilesync", "keychain"]

    public static func ownerBundleID(folder name: String, in parent: String, fs: DiskFS) -> String? {
        var id: String?
        switch (parent as NSString).lastPathComponent {
        case "Containers":
            id = fs.plistString(parent + "/" + name + "/.com.apple.containermanagerd.metadata.plist", key: "MCMMetadataIdentifier")
        case "Group Containers":
            var rest = Substring(name)
            if rest.hasPrefix("group.") {
                rest = rest.dropFirst(6)
            } else if let dot = rest.firstIndex(of: "."), rest.distance(from: rest.startIndex, to: dot) == 10,
                      rest[..<dot].allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) {
                rest = rest[rest.index(after: dot)...]
                if rest.hasPrefix("groups.") { rest = rest.dropFirst(7) } else if rest.hasPrefix("group.") { rest = rest.dropFirst(6) }
            }
            id = String(rest)
        case "Preferences":
            id = name.hasSuffix(".plist") ? String(name.dropLast(6)) : nil
        case "Saved Application State":
            id = name.hasSuffix(".savedState") ? String(name.dropLast(11)) : nil
        default:
            id = name
        }
        guard let id else { return nil }
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        let valid = parts.count >= 3 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } }
        return valid ? id : nil
    }

    private static func installed(_ id: String, apps: AppIndex) -> Bool {
        let parts = id.split(separator: ".")
        for n in stride(from: parts.count, through: 2, by: -1) where apps.appPath(bundleID: parts.prefix(n).joined(separator: ".")) != nil { return true }
        return apps.appPath(bundleIDPrefix: id + ".") != nil
    }

    private struct Group {
        var title: String
        var parents: [String] = []
        var paths: [String] = []
        var bytes: UInt64 = 0
        var largest: (path: String, bytes: UInt64)?

        mutating func add(_ path: String, parent: String, bytes size: UInt64) {
            if !parents.contains(parent) { parents.append(parent) }
            paths.append(path)
            bytes += size
            if size >= (largest?.bytes ?? 0) { largest = (path, size) }
        }
    }

    public static func detect(fs: DiskFS, home: String, apps: AppIndex, includeProtected: Bool) -> [DiskItem] {
        var leftovers: [String: Group] = [:]
        var maybes: [String: Group] = [:]
        for place in places where includeProtected || !protectedPlaces.contains(place) {
            let parent = home + "/Library/" + place
            for name in (fs.list(parent) ?? []).sorted() {
                let path = parent + "/" + name
                if let id = ownerBundleID(folder: name, in: parent, fs: fs) {
                    guard !id.lowercased().hasPrefix("com.apple."), !installed(id, apps: apps) else { continue }
                    leftovers[id, default: Group(title: String(id.split(separator: ".")[2]))].add(path, parent: place, bytes: fs.size(path))
                } else if maybePlaces.contains(place), isMaybe(name, path: path, fs: fs, apps: apps) {
                    maybes[AppNameMatch.normalize(name), default: Group(title: name)].add(path, parent: place, bytes: fs.size(path))
                }
            }
        }
        let confident = leftovers.compactMap { id, group -> DiskItem? in
            let title = fs.plistString(home + "/Library/Preferences/" + id + ".plist", key: "CFBundleName") ?? group.title
            return item(group, id: "leftover:" + id, title: title, category: .leftover)
        }
        let maybe = maybes.compactMap { key, group in item(group, id: "maybe:" + key, title: group.title, category: .maybeLeftover) }
        return confident.sorted { $0.bytes > $1.bytes } + maybe.sorted { $0.bytes > $1.bytes }
    }

    private static func isMaybe(_ name: String, path: String, fs: DiskFS, apps: AppIndex) -> Bool {
        let lower = name.lowercased()
        return fs.list(path) != nil && !name.hasPrefix(".") && !lower.contains("apple") && !appleNames.contains(lower)
            && !dataLike.contains { lower.contains($0) } && apps.appPath(matchingName: name) == nil && !apps.isKnownTool(name)
    }

    private static func item(_ group: Group, id: String, title: String, category: DiskCategory) -> DiskItem? {
        guard group.bytes >= DiskRules.minItemBytes else { return nil }
        return DiskItem(id: id, title: title, detail: group.parents.joined(separator: " · "), category: category, bytes: group.bytes,
                        action: .trash(group.paths), checkedByDefault: false, revealPath: group.largest?.path)
    }
}
