import Foundation

public enum LeftoverDetector {
    private static let places = ["Application Support", "Caches", "Containers", "Group Containers", "Preferences", "Logs", "Saved Application State", "HTTPStorages", "WebKit"]
    private static let protectedPlaces: Set<String> = ["Containers", "Group Containers"]
    private static let maybePlaces: Set<String> = ["Application Support", "Caches", "Logs"]

    private static let appleNames: Set<String> = Set(["AddressBook", "Animoji", "CallHistoryDB", "CallHistoryTransactions", "CloudDocs", "CrashReporter", "DiskImages", "Dock", "FileProvider", "icdd", "iCloud", "Knowledge", "MobileSync", "networkserviceproxy", "SyncServices", "Accounts", "ControlCenter", "DifferentialPrivacy", "FaceTime", "Quick Look", "SpeechRecognitionCore", "Spotlight", "TrustedPeersHelper", "AppStore", "Mail", "Safari", "Photos", "Siri", "homed", "identityservicesd", "locationaccessstored", "videosubscriptionsd", "GeoServices", "CloudKit", "FamilyCircle", "familycircled", "PassKit", "GameKit", "SiriTTS", "askpermissiond", "tipsd", "contactsd", "homeenergyd", "icloudmailagent", "assistant_service"].map { $0.lowercased() })
    private static let genericNames: Set<String> = ["caches", "logs", "tmp", "temp", "crashpad", "crashreporter"]
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
        case "HTTPStorages":
            id = name.hasSuffix(".binarycookies") ? String(name.dropLast(14)) : name
        default:
            id = name
        }
        guard let id else { return nil }
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        let valid = parts.count >= 3 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } }
        return valid ? id : nil
    }

    private static let evidencePlaces: Set<String> = ["Preferences", "Saved Application State", "Containers"]

    static func isApple(_ id: String) -> Bool {
        let lower = id.lowercased()
        let parts = lower.split(separator: ".")
        return lower.hasPrefix("systemgroup.") || lower.hasPrefix("is.workflow")
            || zip(parts, parts.dropFirst()).contains { $0 == "com" && $1 == "apple" }
    }

    private static func installed(_ id: String, apps: AppIndex) -> Bool {
        let lower = id.lowercased()
        let parts = lower.split(separator: ".")
        let vendor = parts.prefix(2).joined(separator: ".")
        if apps.bundleIDs.contains(where: { $0.hasPrefix(lower) || lower.hasPrefix($0) || $0 == vendor || $0.hasPrefix(vendor + ".") }) { return true }
        for n in stride(from: parts.count, through: 2, by: -1) where apps.appPath(bundleID: parts.prefix(n).joined(separator: ".")) != nil { return true }
        return false
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
                    guard !isApple(id), !installed(id, apps: apps) else { continue }
                    let component = id.split(separator: ".")[2]
                    leftovers[id, default: Group(title: component.prefix(1).uppercased() + component.dropFirst())].add(path, parent: place, bytes: fs.size(path))
                } else if maybePlaces.contains(place), isMaybe(name, path: path, fs: fs, apps: apps) {
                    maybes[AppNameMatch.normalize(name), default: Group(title: name)].add(path, parent: place, bytes: fs.size(path))
                }
            }
        }
        let confident = leftovers.compactMap { id, group -> DiskItem? in
            guard !evidencePlaces.isDisjoint(with: group.parents) else { return nil }
            let title = fs.plistString(home + "/Library/Preferences/" + id + ".plist", key: "CFBundleName") ?? group.title
            let names = id.split(separator: ".").dropFirst().map(String.init) + [title]
            guard !names.contains(where: apps.isKnownTool) else { return nil }
            let children = group.paths.filter { !$0.hasPrefix(home + "/Library/HTTPStorages/") }.flatMap { fs.list($0) ?? [] }
            guard !(names + children).contains(where: isDataLike) else { return nil }
            return item(group, id: "leftover:" + id, title: title, category: .leftover, owner: id)
        }
        let maybe = maybes.compactMap { key, group in item(group, id: "maybe:" + key, title: group.title, category: .maybeLeftover) }
        return confident.sorted { $0.bytes > $1.bytes } + maybe.sorted { $0.bytes > $1.bytes }
    }

    private static func isMaybe(_ name: String, path: String, fs: DiskFS, apps: AppIndex) -> Bool {
        let lower = name.lowercased()
        return fs.list(path) != nil && !name.hasPrefix(".") && !lower.hasPrefix("default.store") && !(name == lower && name.hasSuffix("d"))
            && !lower.contains("apple") && !appleNames.contains(lower) && !genericNames.contains(lower)
            && !isDataLike(name) && apps.appPath(matchingName: name) == nil && !apps.isKnownTool(name)
    }

    private static func isDataLike(_ name: String) -> Bool {
        let lower = name.lowercased()
        return dataLike.contains { lower.contains($0) }
    }

    private static func item(_ group: Group, id: String, title: String, category: DiskCategory, owner: String? = nil) -> DiskItem? {
        guard group.bytes >= DiskRules.minItemBytes else { return nil }
        return DiskItem(id: id, title: title, detail: group.parents.joined(separator: " · "), category: category, bytes: group.bytes,
                        action: .trash(group.paths), checkedByDefault: false, ownerBundlePrefix: owner, revealPath: group.largest?.path)
    }
}
