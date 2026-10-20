import Foundation

public struct SessionCost: Sendable, Equatable {
    public var totalBytes: UInt64
    public var parts: [PeakItem]

    public init(totalBytes: UInt64, parts: [PeakItem]) {
        self.totalBytes = totalBytes
        self.parts = parts
    }

    public static func compute(session: ProcessSnapshot, rows: [ProcessRow]) -> SessionCost {
        let children = Dictionary(grouping: rows, by: \.snapshot.ppid)
        func subtree(_ pid: Int32) -> [ProcessRow] {
            var result: [ProcessRow] = []
            var stack = children[pid] ?? []
            var seen: Set<Int32> = [session.id]
            while let row = stack.popLast() {
                guard seen.insert(row.id).inserted else { continue }
                result.append(row)
                stack.append(contentsOf: children[row.id] ?? [])
            }
            return result
        }
        var parts = [PeakItem(title: "Claude Code", bytes: session.footprintBytes)]
        var total = session.footprintBytes
        for child in (children[session.id] ?? []).sorted(by: { $0.id < $1.id }) {
            let tree = [child] + subtree(child.id)
            guard let mcp = tree.first(where: { $0.identified.kind == .mcpServer }) else { continue }
            let bytes = tree.reduce(UInt64(0)) { $0 + $1.snapshot.footprintBytes }
            parts.append(PeakItem(title: mcp.identified.title, bytes: bytes))
            total += bytes
        }
        return SessionCost(totalBytes: total, parts: parts)
    }
}
