import Foundation

/// Claude Code writes `<configDir>/sessions/<pid>.json` (sessionId + cwd) and the transcript
/// `<configDir>/projects/<cwd with non-alnum as ->/<sessionId>.jsonl`, which carries `ai-title`
/// and, when the user renamed it, `custom-title` lines.
public enum ClaudeSessionTitle {
    public static func lookup(pid: Int32, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        let fm = FileManager.default
        let configDirs = ((try? fm.contentsOfDirectory(atPath: home.path)) ?? []).filter { $0.hasPrefix(".claude") }
        for dir in configDirs {
            let base = home.appendingPathComponent(dir)
            guard let data = try? Data(contentsOf: base.appendingPathComponent("sessions/\(pid).json")),
                  let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = info["sessionId"] as? String, let cwd = info["cwd"] as? String else { continue }
            let folder = String(cwd.map { $0.isLetter || $0.isNumber ? $0 : "-" })
            let transcript = base.appendingPathComponent("projects/\(folder)/\(id).jsonl")
            guard let text = try? String(contentsOf: transcript, encoding: .utf8) else { return nil }
            return title(inTranscript: text)
        }
        return nil
    }

    static func title(inTranscript text: String) -> String? {
        var ai: String?
        var custom: String?
        for line in text.split(separator: "\n") where line.contains("-title\"") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            switch obj["type"] as? String {
            case "custom-title": custom = obj["customTitle"] as? String ?? custom
            case "ai-title": ai = obj["aiTitle"] as? String ?? ai
            default: break
            }
        }
        return (custom ?? ai).flatMap { $0.isEmpty ? nil : $0 }
    }
}
