import Foundation

public struct CleanResult: Sendable, Equatable {
    public var trashedBytes: UInt64
    public var dockerBytes: UInt64
    public var failures: [String]

    public init(trashedBytes: UInt64 = 0, dockerBytes: UInt64 = 0, failures: [String] = []) {
        self.trashedBytes = trashedBytes
        self.dockerBytes = dockerBytes
        self.failures = failures
    }
}

public enum DiskCleaner {
    public static func clean(_ items: [DiskItem], runningBundleIDs: Set<String>, busyPaths: [String],
                             exists: (String) -> Bool,
                             trash: (String) throws -> Void,
                             docker: (DockerPrune) -> String?) -> CleanResult {
        var result = CleanResult()
        let isDocker: (DiskItem) -> Bool = { if case .docker = $0.action { return true } else { return false } }
        let ordered = items.filter { !isDocker($0) } + items.filter(isDocker)
        for item in ordered {
            if let prefix = item.ownerBundlePrefix, runningBundleIDs.contains(where: { $0.hasPrefix(prefix) }) {
                result.failures.append("\(item.title): feche o app primeiro")
                continue
            }
            switch item.action {
            case .none:
                continue
            case .docker(let kind):
                if let error = docker(kind) {
                    result.failures.append("\(item.title): \(error)")
                } else {
                    result.dockerBytes += item.bytes
                }
            case .trash(let paths):
                let inUse = paths.contains { path in
                    let project = (path as NSString).deletingLastPathComponent
                    return busyPaths.contains { $0 == project || $0.hasPrefix(project + "/") }
                }
                if inUse {
                    result.failures.append("\(item.title): em uso")
                    continue
                }
                let present = paths.filter(exists)
                if present.isEmpty {
                    result.failures.append("\(item.title): já não existe")
                    continue
                }
                var moved = false
                var failed = false
                for path in present {
                    do { try trash(path); moved = true } catch { failed = true }
                }
                if failed { result.failures.append("\(item.title): não foi possível mover para a Lixeira") }
                if moved { result.trashedBytes += item.bytes }
            }
        }
        return result
    }
}
