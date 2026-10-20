import Foundation

public enum ProcessKind: String, Sendable, Hashable {
    case devServer
    case claudeSession
    case mcpServer
    case appProcess
    case shell
    case database
    case system
    case other
}

public struct Identified: Sendable, Equatable {
    public var kind: ProcessKind
    public var title: String
    public var subtitle: String?
    public var project: String?
    public var appBundlePath: String?

    public init(kind: ProcessKind, title: String, subtitle: String? = nil, project: String? = nil, appBundlePath: String? = nil) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.project = project
        self.appBundlePath = appBundlePath
    }
}

public enum Classifier {
    private static let devServers: [(match: @Sendable (String) -> Bool, title: String)] = [
        ({ $0.contains("next-server") || $0.contains("next dev") || $0.contains("/next/dist/bin/next") }, "Next.js dev"),
        ({ $0.contains("/vite") || $0.hasPrefix("vite") }, "Vite dev"),
        ({ $0.contains("webpack") }, "Webpack dev"),
        ({ $0.contains("nest start") || $0.contains("@nestjs/cli") }, "NestJS dev"),
        ({ $0.contains("tsx watch") || $0.contains("/tsx") && $0.contains("watch") }, "tsx watch"),
        ({ $0.contains("nodemon") }, "nodemon"),
        ({ $0.contains("springframework") || $0.contains("spring-boot") || $0.contains("plexus-classworlds") || $0.contains("maven") }, "Spring Boot dev"),
        ({ $0.contains("rails server") || $0.contains("bin/rails") }, "Rails dev"),
        ({ $0.contains("uvicorn") }, "Uvicorn dev"),
        ({ $0.contains("manage.py runserver") }, "Django dev"),
    ]

    private static let databases: [String: String] = [
        "mysqld": "MySQL", "postgres": "PostgreSQL", "redis-server": "Redis", "mongod": "MongoDB",
    ]

    private static let shells: Set<String> = ["zsh", "bash", "fish", "sh"]

    public static func classify(_ p: ProcessSnapshot, ports: [UInt16]) -> Identified {
        let command = p.arguments.joined(separator: " ")
        let exeName = (p.executablePath.map { ($0 as NSString).lastPathComponent }) ?? ""
        let argv0 = p.arguments.first.map { ($0 as NSString).lastPathComponent } ?? ""
        let project = projectName(from: p.cwd)
        let portText = ports.isEmpty ? nil : ports.map { ":\($0)" }.joined(separator: " ")

        if let app = outerAppBundle(p.executablePath) {
            let title = ((app as NSString).lastPathComponent as NSString).deletingPathExtension
            return Identified(kind: .appProcess, title: title, subtitle: p.name == title ? nil : p.name, project: nil, appBundlePath: app)
        }
        if argv0 == "claude" || p.name == "claude" || exeName == "claude" {
            let subtitle = [project, p.state == .stopped ? "suspensa" : nil].compactMap { $0 }.joined(separator: " · ")
            return Identified(kind: .claudeSession, title: "Claude Code", subtitle: subtitle.isEmpty ? nil : subtitle, project: project)
        }
        if p.arguments.contains(where: { $0.hasSuffix("mcp") || $0.contains("-mcp") || $0 == "mcp" }) {
            return Identified(kind: .mcpServer, title: mcpTitle(p.arguments), subtitle: project, project: project)
        }
        let haystack = ([p.name] + p.arguments).joined(separator: " ")
        if let dev = devServers.first(where: { $0.match(haystack) }) {
            let subtitle = [project, portText].compactMap { $0 }.joined(separator: " · ")
            return Identified(kind: .devServer, title: dev.title, subtitle: subtitle.isEmpty ? nil : subtitle, project: project)
        }
        if let db = databases[exeName] ?? databases[p.name] ?? databases[argv0] {
            return Identified(kind: .database, title: db, subtitle: portText, project: nil)
        }
        let shellName = argv0.hasPrefix("-") ? String(argv0.dropFirst()) : argv0
        if shells.contains(p.name) || shells.contains(shellName) {
            return Identified(kind: .shell, title: "Terminal (\(shells.contains(p.name) ? p.name : shellName))", subtitle: p.ttyName, project: project)
        }
        if p.uid == 0 {
            return Identified(kind: .system, title: p.name, subtitle: command.isEmpty ? nil : command, project: nil)
        }
        return Identified(kind: .other, title: p.name, subtitle: [project, portText].compactMap { $0 }.joined(separator: " · ").nilIfEmpty, project: project)
    }

    private static func mcpTitle(_ args: [String]) -> String {
        let token = args.map { ($0 as NSString).lastPathComponent }.first { $0.hasSuffix("mcp") || $0.contains("-mcp") } ?? "mcp"
        let base = token.replacingOccurrences(of: "-mcp", with: "").replacingOccurrences(of: "mcp", with: "")
        let name = base.split(separator: "@").first.map(String.init) ?? base
        return name.isEmpty ? "Servidor MCP" : name.prefix(1).uppercased() + name.dropFirst() + " MCP"
    }

    static func outerAppBundle(_ path: String?) -> String? {
        guard let path, let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    static func projectName(from cwd: String?) -> String? {
        guard let cwd, cwd != "/" else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fm = FileManager.default
        var url = URL(fileURLWithPath: cwd)
        var nearest: URL?
        while url.path.count > 1, url.path != home {
            if fm.fileExists(atPath: url.appendingPathComponent(".git").path) { return url.lastPathComponent }
            if nearest == nil, ["package.json", "pom.xml", "Cargo.toml"].contains(where: { fm.fileExists(atPath: url.appendingPathComponent($0).path) }) {
                nearest = url
            }
            url.deleteLastPathComponent()
        }
        return nearest?.lastPathComponent ?? (cwd == home ? nil : URL(fileURLWithPath: cwd).lastPathComponent)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
