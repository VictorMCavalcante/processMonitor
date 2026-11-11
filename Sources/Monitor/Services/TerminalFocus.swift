import AppKit
import MonitorCore

/// Brings forward the terminal running a process. Inside Herdr (sessions parented by `herdr server`)
/// it also focuses the pane hosting the Claude session, then raises the app running the Herdr client.
enum TerminalFocus {
    static func focus(_ row: ProcessRow, sessionId: String?, all: [ProcessSnapshot]) {
        let byPid = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var anchors = [row.id]
        if let server = ancestors(row.id, byPid).compactMap({ byPid[$0] }).first(where: isHerdrServer) {
            anchors = all.filter { $0.name == "herdr" && !isHerdrServer($0) }.map(\.id)
            if let sessionId, let herdr = server.executablePath {
                Task.detached(priority: .userInitiated) { focusPane(herdr: herdr, sessionId: sessionId) }
            }
        }
        for pid in anchors {
            let app = ancestors(pid, byPid).lazy.compactMap { NSRunningApplication(processIdentifier: $0) }.first { $0.activationPolicy == .regular }
            if let app { app.activate(); return }
        }
    }

    private static func isHerdrServer(_ p: ProcessSnapshot) -> Bool {
        p.name == "herdr" && p.arguments.dropFirst().first == "server"
    }

    private static func ancestors(_ pid: Int32, _ byPid: [Int32: ProcessSnapshot]) -> [Int32] {
        var chain: [Int32] = []
        var current = byPid[pid]
        while let p = current, p.id > 1, chain.count < 32 {
            chain.append(p.id)
            current = byPid[p.ppid]
        }
        return chain
    }

    private static func focusPane(herdr: String, sessionId: String) {
        guard let data = run(herdr, ["agent", "list"]),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let agents = (json["result"] as? [String: Any])?["agents"] as? [[String: Any]],
              let pane = agents.first(where: { ($0["agent_session"] as? [String: Any])?["value"] as? String == sessionId })?["pane_id"] as? String
        else { return }
        _ = run(herdr, ["agent", "focus", pane])
    }

    private static func run(_ path: String, _ args: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}
