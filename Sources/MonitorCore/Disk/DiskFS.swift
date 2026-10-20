import Foundation

public protocol DiskFS: AnyObject {
    func list(_ path: String) -> [String]?
    func isDirectory(_ path: String) -> Bool
    func exists(_ path: String) -> Bool
    func modified(_ path: String) -> Date?
    func size(_ path: String) -> UInt64
    func plistString(_ path: String, key: String) -> String?
}

public final class RealDiskFS: DiskFS {
    private let fm = FileManager.default
    private var seen = Set<NSObject>()
    private let lock = NSLock()

    public init() {}

    public func list(_ path: String) -> [String]? {
        try? fm.contentsOfDirectory(atPath: path)
    }

    public func isDirectory(_ path: String) -> Bool {
        guard let type = (try? fm.attributesOfItem(atPath: path))?[.type] as? FileAttributeType else { return false }
        return type == .typeDirectory
    }

    public func exists(_ path: String) -> Bool { fm.fileExists(atPath: path) }

    public func modified(_ path: String) -> Date? {
        (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    public func size(_ path: String) -> UInt64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileResourceIdentifierKey, .isSymbolicLinkKey]
        let root = URL(fileURLWithPath: path)
        var total: UInt64 = 0
        func add(_ url: URL) {
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isSymbolicLink != true else { return }
            if let id = v.fileResourceIdentifier {
                lock.lock()
                let fresh = seen.insert(id as! NSObject).inserted
                lock.unlock()
                if !fresh { return }
            }
            total += UInt64(v.totalFileAllocatedSize ?? 0)
        }
        add(root)
        if let e = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) {
            for case let url as URL in e { add(url) }
        }
        return total
    }

    public func plistString(_ path: String, key: String) -> String? {
        guard let data = fm.contents(atPath: path),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return dict[key] as? String
    }
}
