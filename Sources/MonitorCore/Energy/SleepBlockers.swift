import Foundation
import IOKit.pwr_mgt

public struct SleepBlocker: Sendable, Equatable, Identifiable {
    public var id: String
    public var pid: Int32
    public var kind: String
    public var title: String
    public var since: Date?
    public var ownerPid: Int32

    public init(id: String, pid: Int32, kind: String, title: String, since: Date?, ownerPid: Int32) {
        self.id = id
        self.pid = pid
        self.kind = kind
        self.title = title
        self.since = since
        self.ownerPid = ownerPid
    }
}

public enum SleepBlockers {
    private static let kinds: Set<String> = ["PreventUserIdleSystemSleep", "PreventSystemSleep", "PreventUserIdleDisplaySleep", "NoIdleSleepAssertion"]

    public static func read(now: Date) -> [[String: Any]] {
        var dict: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&dict) == kIOReturnSuccess,
              let byPid = dict?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }
        return byPid.flatMap { pid, list in list.map { $0.merging(["pid": pid]) { $1 } } }
    }

    public static func build(_ raw: [[String: Any]], rows: [ProcessRow], all: [ProcessSnapshot], now: Date) -> [SleepBlocker] {
        let snaps = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let rowsByPid = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func title(_ pid: Int32) -> String {
            rowsByPid[pid]?.identified.title ?? snaps[pid]?.name ?? "PID \(pid)"
        }
        var result: [SleepBlocker] = []
        for a in raw {
            guard let pid = (a["pid"] as? NSNumber)?.int32Value, let kind = a["AssertType"] as? String, kinds.contains(kind) else { continue }
            let name = snaps[pid]?.name
            let assertName = a["AssertName"] as? String ?? ""
            var owner = pid
            let text: String
            if name == "powerd", assertName.localizedCaseInsensitiveContains("display is on") {
                text = "Tela ligada"
            } else if name == "caffeinate", let parent = snaps[pid]?.ppid, parent > 1 {
                owner = parent
                text = rowsByPid[parent]?.identified.kind == .claudeSession
                    ? "Claude Code está impedindo o Mac de dormir"
                    : "\(title(parent)) está impedindo o Mac de dormir"
            } else {
                text = "\(title(pid)) está impedindo o Mac de dormir"
            }
            let since = a["AssertStartWhen"] as? Date
            let id = "\(owner):\(kind)"
            if let i = result.firstIndex(where: { $0.id == id }) {
                if let since, result[i].since.map({ since < $0 }) ?? true { result[i].since = since }
            } else {
                result.append(SleepBlocker(id: id, pid: pid, kind: kind, title: text, since: since, ownerPid: owner))
            }
        }
        return result
    }
}
