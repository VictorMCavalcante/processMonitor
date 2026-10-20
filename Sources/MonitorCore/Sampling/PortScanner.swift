import Foundation

public enum Exposure: Sendable, Equatable {
    case local
    case network
}

public struct ListeningSocket: Sendable, Equatable {
    public var pid: Int32
    public var port: UInt16
    public var exposure: Exposure

    public init(pid: Int32, port: UInt16, exposure: Exposure) {
        self.pid = pid
        self.port = port
        self.exposure = exposure
    }
}

public enum PortScanner {
    public static func parseSockets(lsofOutput: String) -> [ListeningSocket] {
        var found: [String: ListeningSocket] = [:]
        var current: Int32?
        for line in lsofOutput.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = line.dropFirst()
            if tag == "p" {
                current = Int32(value)
            } else if tag == "n", let pid = current, let colon = value.lastIndex(of: ":"),
                      let port = UInt16(value[value.index(after: colon)...]) {
                let exposure = exposure(of: String(value[..<colon]))
                let key = "\(pid):\(port)"
                if let existing = found[key], existing.exposure == .network { continue }
                found[key] = ListeningSocket(pid: pid, port: port, exposure: exposure)
            }
        }
        return found.values.sorted { $0.port != $1.port ? $0.port < $1.port : $0.pid < $1.pid }
    }

    public static func byPid(_ sockets: [ListeningSocket]) -> [Int32: [UInt16]] {
        Dictionary(grouping: sockets, by: \.pid).mapValues { Array(Set($0.map(\.port))).sorted() }
    }

    public static func parse(lsofOutput: String) -> [Int32: [UInt16]] {
        byPid(parseSockets(lsofOutput: lsofOutput))
    }

    public static func scanSockets(runner: CommandRunner = SystemCommandRunner()) -> [ListeningSocket] {
        guard let result = runner.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpn"], timeout: 3) else { return [] }
        return parseSockets(lsofOutput: result.output)
    }

    public static func scan() -> [Int32: [UInt16]] {
        byPid(scanSockets())
    }

    private static func exposure(of address: String) -> Exposure {
        let host = address.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host.hasPrefix("127.") || host == "::1" || host == "localhost" { return .local }
        return .network
    }
}
