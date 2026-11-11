import Foundation

public struct ClaudeSessionInfo: Sendable, Equatable {
    public var title: String?
    public var lastPrompt: String?

    public init(title: String? = nil, lastPrompt: String? = nil) {
        self.title = title
        self.lastPrompt = lastPrompt
    }
}

/// Claude Code writes `<configDir>/sessions/<pid>.json` (sessionId + cwd) and the transcript
/// `<configDir>/projects/<cwd with non-alnum as ->/<sessionId>.jsonl`, which carries `ai-title`,
/// `custom-title` (when the user renamed it) and `last-prompt` lines, re-appended as the session goes.
public enum ClaudeSessionTitle {
    public static func lookup(pid: Int32, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> ClaudeSessionInfo? {
        let fm = FileManager.default
        let configDirs = ((try? fm.contentsOfDirectory(atPath: home.path)) ?? []).filter { $0.hasPrefix(".claude") }
        for dir in configDirs {
            let base = home.appendingPathComponent(dir)
            guard let data = try? Data(contentsOf: base.appendingPathComponent("sessions/\(pid).json")),
                  let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = info["sessionId"] as? String, let cwd = info["cwd"] as? String else { continue }
            let folder = String(cwd.map { $0.isLetter || $0.isNumber ? $0 : "-" })
            let transcript = base.appendingPathComponent("projects/\(folder)/\(id).jsonl")
            guard let handle = try? FileHandle(forReadingFrom: transcript) else { return nil }
            defer { try? handle.close() }
            // Transcripts reach tens of MB; titles/prompts are re-appended often, so the tail usually has them.
            let size = (try? handle.seekToEnd()) ?? 0
            try? handle.seek(toOffset: size > tailBytes ? size - tailBytes : 0)
            var result = parse(String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self))
            if result.title == nil, size > tailBytes {
                try? handle.seek(toOffset: 0)
                result.title = parse(String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)).title
            }
            return result
        }
        return nil
    }

    /// Plugin that launched an SDK session, from `…/plugins/cache/<org>/<plugin>/…` in its own or its parent's argv.
    public static func plugin(in arguments: [String]) -> String? {
        for arg in arguments {
            guard let range = arg.range(of: "/plugins/cache/") else { continue }
            let parts = arg[range.upperBound...].split(separator: "/")
            if parts.count >= 2 { return String(parts[1]) }
        }
        return nil
    }

    static let tailBytes: UInt64 = 512 * 1024

    static func parse(_ text: String) -> ClaudeSessionInfo {
        var ai: String?
        var custom: String?
        var prompt: String?
        for line in text.split(separator: "\n") where line.contains("-title\"") || line.contains("\"last-prompt\"") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            switch obj["type"] as? String {
            case "custom-title": custom = obj["customTitle"] as? String ?? custom
            case "ai-title": ai = obj["aiTitle"] as? String ?? ai
            case "last-prompt": prompt = obj["lastPrompt"] as? String ?? prompt
            default: break
            }
        }
        let clean = { (s: String?) in s.map { $0.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 } }
        return ClaudeSessionInfo(title: clean(custom) ?? clean(ai), lastPrompt: clean(prompt))
    }
}
