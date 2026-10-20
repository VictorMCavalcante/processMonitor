import Foundation

public struct DockerContainer: Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var image: String
    public var state: String
    public var composeProject: String?
    public var memoryBytes: UInt64
    public var cpuPercent: Double
    public var publishedPorts: [UInt16]

    public init(id: String, name: String, image: String, state: String, composeProject: String?, memoryBytes: UInt64, cpuPercent: Double, publishedPorts: [UInt16]) {
        self.id = id
        self.name = name
        self.image = image
        self.state = state
        self.composeProject = composeProject
        self.memoryBytes = memoryBytes
        self.cpuPercent = cpuPercent
        self.publishedPorts = publishedPorts
    }
}

public struct DockerClient: Sendable {
    public static let defaultPaths = ["/usr/local/bin/docker", "/Applications/Docker.app/Contents/Resources/bin/docker"]
    private let runner: CommandRunner
    private let paths: [String]
    private let timeout: TimeInterval = 5

    public init(runner: CommandRunner = SystemCommandRunner(), paths: [String] = DockerClient.defaultPaths) {
        self.runner = runner
        self.paths = paths
    }

    public func list() -> [DockerContainer] {
        let deadline = Date().addingTimeInterval(timeout)
        guard let ps = command(["ps", "--format", "{{json .}}"]) else { return [] }
        var containers = Self.parsePs(ps)
        let remaining = deadline.timeIntervalSinceNow
        guard !containers.isEmpty, remaining > 0.2, let stats = command(["stats", "--no-stream", "--format", "{{json .}}"], timeout: remaining) else { return containers }
        let usage = Self.parseStats(stats)
        for i in containers.indices {
            if let u = usage.first(where: { containers[i].id.hasPrefix($0.key) || $0.key.hasPrefix(containers[i].id) })?.value {
                containers[i].memoryBytes = u.memory
                containers[i].cpuPercent = u.cpu
            }
        }
        return containers
    }

    public func runningCount() -> Int {
        guard let out = command(["ps", "-q"]) else { return 0 }
        return out.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    public func stop(_ id: String) -> String? {
        guard let path = executable else { return "Docker não encontrado." }
        guard let result = runner.run(path, ["stop", id], timeout: 30) else { return "O Docker não respondeu a tempo." }
        return result.status == 0 ? nil : "Não foi possível parar o container."
    }

    private var executable: String? {
        paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func command(_ args: [String], timeout: TimeInterval? = nil) -> String? {
        guard let path = executable, let result = runner.run(path, args, timeout: timeout ?? self.timeout), result.status == 0 else { return nil }
        return result.output
    }

    public static func parsePs(_ out: String) -> [DockerContainer] {
        out.split(separator: "\n").compactMap { line -> DockerContainer? in
            guard let obj = json(line), let id = obj["ID"], let name = obj["Names"] else { return nil }
            let project = (obj["Labels"] ?? "").split(separator: ",")
                .first { $0.hasPrefix("com.docker.compose.project=") }
                .map { String($0.dropFirst("com.docker.compose.project=".count)) }
            return DockerContainer(id: id, name: name, image: obj["Image"] ?? "", state: obj["State"] ?? "",
                                   composeProject: project, memoryBytes: 0, cpuPercent: 0, publishedPorts: publishedPorts(obj["Ports"] ?? ""))
        }
    }

    static func parseStats(_ out: String) -> [String: (memory: UInt64, cpu: Double)] {
        var result: [String: (memory: UInt64, cpu: Double)] = [:]
        for line in out.split(separator: "\n") {
            guard let obj = json(line), let id = obj["Container"] ?? obj["ID"] else { continue }
            let cpu = Double((obj["CPUPerc"] ?? "").replacingOccurrences(of: "%", with: "")) ?? 0
            result[id] = (parseMemory(obj["MemUsage"] ?? ""), cpu)
        }
        return result
    }

    public static func parseMemory(_ s: String) -> UInt64 {
        let left = s.split(separator: "/").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let units: [(String, Double)] = [("GiB", 1_073_741_824), ("MiB", 1_048_576), ("KiB", 1024), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("B", 1)]
        for (suffix, factor) in units where left.hasSuffix(suffix) {
            guard let value = Double(left.dropLast(suffix.count)) else { return 0 }
            return UInt64(value * factor)
        }
        return 0
    }

    static func publishedPorts(_ s: String) -> [UInt16] {
        let ports = s.split(separator: ",").flatMap { part -> [UInt16] in
            guard let arrow = part.range(of: "->") else { return [] }
            let host = part[..<arrow.lowerBound]
            guard let colon = host.lastIndex(of: ":") else { return [] }
            let spec = host[host.index(after: colon)...]
            let bounds = spec.split(separator: "-").compactMap { UInt16($0) }
            guard let low = bounds.first else { return [] }
            let high = bounds.count > 1 ? bounds[1] : low
            guard high >= low, high - low <= 256 else { return [low] }
            return Array(low...high)
        }
        return Array(Set(ports)).sorted()
    }

    private static func json(_ line: Substring) -> [String: String]? {
        guard let data = line.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj.compactMapValues { $0 as? String }
    }
}
