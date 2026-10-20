import Foundation

public enum PortOwner: Sendable, Equatable {
    case process(ProcessRow)
    case container(DockerContainer)
}

public struct PortEntry: Sendable, Identifiable, Equatable {
    public var id: String
    public var port: UInt16
    public var exposure: Exposure
    public var owner: PortOwner
    public var title: String
    public var project: String?
    public var startTime: Date?
}

public enum PortRelease: Sendable, Equatable {
    case free
    case stopContainer(id: String, name: String)
    case close(ProcessGroup)
    case blocked(String)
}

extension PortRelease {
    public func requiresConfirmation(all: [ProcessSnapshot], myUid: UInt32) -> Bool {
        switch self {
        case .close(let g): g.kind == .appProcess || TerminationPlanner.needsConfirmation(g, all: all, myUid: myUid)
        case .stopContainer: true
        case .free, .blocked: false
        }
    }
}

public enum PortTable {
    public static func build(sockets: [ListeningSocket], rows: [ProcessRow], containers: [DockerContainer]) -> [PortEntry] {
        let byPid = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen: Set<String> = []
        var entries: [PortEntry] = []
        for socket in sockets {
            guard let row = byPid[socket.pid] else { continue }
            if row.identified.appBundlePath == Classifier.dockerAppPath,
               let container = containers.first(where: { $0.publishedPorts.contains(socket.port) }) {
                let id = "\(socket.port)-\(container.id)"
                guard seen.insert(id).inserted else { continue }
                entries.append(PortEntry(id: id, port: socket.port, exposure: socket.exposure, owner: .container(container),
                                         title: container.name, project: container.composeProject, startTime: nil))
            } else {
                let id = "\(socket.port)-\(socket.pid)"
                guard seen.insert(id).inserted else { continue }
                entries.append(PortEntry(id: id, port: socket.port, exposure: socket.exposure, owner: .process(row),
                                         title: row.identified.title, project: row.identified.project, startTime: row.snapshot.startTime))
            }
        }
        return entries.sorted { $0.port != $1.port ? $0.port < $1.port : $0.id < $1.id }
    }

    public static func release(port: UInt16, entries: [PortEntry], all: [ProcessSnapshot], myUid: UInt32) -> PortRelease {
        guard let entry = entries.first(where: { $0.port == port }) else { return .free }
        switch entry.owner {
        case .container(let c):
            return .stopContainer(id: c.id, name: c.name)
        case .process(let row):
            if row.identified.appBundlePath == Classifier.dockerAppPath {
                return .blocked("Porta do Docker sem container identificado. Pare o container na aba Docker.")
            }
            guard all.contains(where: { $0.id == row.id && abs($0.startTime.timeIntervalSince(row.snapshot.startTime)) < 0.001 }) else {
                return .blocked(TerminationPlanner.alreadyGone)
            }
            let group = ProcessGroup(id: "port:\(port)", title: row.identified.title, subtitle: nil, kind: row.identified.kind, rows: [row])
            if case .notAllowed(let reason) = TerminationPlanner.plan(group, all: all, mode: .normal, myUid: myUid) {
                return .blocked(reason)
            }
            return .close(group)
        }
    }
}
