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

public struct ClassifyContext: Sendable, Equatable {
    public var dockerRunning: Bool

    public init(dockerRunning: Bool) {
        self.dockerRunning = dockerRunning
    }

    public static let empty = ClassifyContext(dockerRunning: false)
}

public enum Classifier {
    public static let dockerAppPath = "/Applications/Docker.app"
    private static let virtualMachineMarker = "com.apple.Virtualization.VirtualMachine"

    public static func dockerRunning(in snaps: [ProcessSnapshot]) -> Bool {
        snaps.contains { $0.executablePath?.hasPrefix(dockerAppPath + "/") == true }
    }

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
    private static let systemPrefixes = ["/System/Library/", "/System/Volumes/Preboot/Cryptexes/OS/", "/usr/libexec/", "/usr/sbin/", "/sbin/"]
    private static let friendlySystem: [String: String] = [
        "ControlCenter": "Central de Controle",
        "rapportd": "Continuidade (Handoff e AirDrop)",
        "sharingd": "Compartilhamento (AirDrop)",
        "WindowServer": "Servidor de janelas",
        "mds": "Spotlight (indexação)",
        "mds_stores": "Spotlight (indexação)",
        "mdworker_shared": "Spotlight (indexação)",
        "coreaudiod": "Áudio do sistema",
        "bluetoothd": "Bluetooth",
        "ANEStorageMaintainer": "Neural Engine (manutenção)",
        "aned": "Neural Engine",
        "AMPDeviceDiscoveryAgent": "Descoberta de iPhone/iPad",
        "AirPlayXPCHelper": "AirPlay",
        "AirPlayUIAgent": "AirPlay",
        "AccessibilityUIServer": "Acessibilidade",
        "APFSUserAgent": "Disco (APFS)",
        "AppleSpell": "Corretor ortográfico",
        "AppleIDSettings": "Conta Apple",
        "launchd": "Inicializador do sistema",
        "logd": "Registro de logs",
        "powerd": "Gerenciamento de energia",
        "hidd": "Teclado, mouse e trackpad",
        "cfprefsd": "Preferências",
        "trustd": "Certificados",
        "nsurlsessiond": "Downloads em segundo plano",
        "softwareupdated": "Atualização de software",
        "backupd": "Time Machine",
        "photoanalysisd": "Fotos (análise)",
        "mediaanalysisd": "Análise de mídia",
        "corespotlightd": "Spotlight (indexação)",
        "airportd": "Wi-Fi",
        "locationd": "Localização",
        "configd": "Rede",
        "opendirectoryd": "Contas de usuário",
        "loginwindow": "Sessão de login",
        "UserEventAgent": "Eventos do sistema",
        "distnoted": "Notificações internas",
        "notifyd": "Notificações internas",
        "fseventsd": "Monitor de arquivos",
        "kernelmanagerd": "Extensões do kernel",
        "symptomsd": "Diagnóstico de rede",
        "biomed": "Dados de uso (Siri)",
        "suggestd": "Sugestões (Siri)",
        "remindd": "Lembretes",
        "cloudd": "iCloud",
        "bird": "iCloud Drive",
        "Dock": "Dock",
        "Finder": "Finder",
        "com.apple.WebKit.WebContent": "Página web (WebKit)",
        "com.apple.WebKit.GPU": "Gráficos web (WebKit)",
        "com.apple.WebKit.Networking": "Rede web (WebKit)",
    ]
    private static let interpreters: [String: String] = [
        "python": "Python", "python3": "Python", "node": "node", "bun": "bun", "deno": "deno", "ruby": "Ruby", "perl": "Perl", "php": "PHP",
    ]
    private static let scriptExtensions: Set<String> = ["py", "js", "mjs", "cjs", "ts", "rb", "pl", "php"]

    public static func classify(_ p: ProcessSnapshot, ports: [UInt16], context: ClassifyContext = .empty) -> Identified {
        let command = p.arguments.joined(separator: " ")
        let exeName = (p.executablePath.map { ($0 as NSString).lastPathComponent }) ?? ""
        let argv0 = p.arguments.first.map { ($0 as NSString).lastPathComponent } ?? ""
        let project = projectName(from: p.cwd)
        let portText = ports.isEmpty ? nil : ports.map { ":\($0)" }.joined(separator: " ")

        if let app = p.hostAppPath {
            let title = ((app as NSString).lastPathComponent as NSString).deletingPathExtension
            return Identified(kind: .appProcess, title: title, subtitle: friendlySystem[p.name] ?? p.name, project: nil, appBundlePath: app)
        }
        if let path = p.executablePath, path.contains(virtualMachineMarker) {
            return context.dockerRunning
                ? Identified(kind: .appProcess, title: "Docker Desktop", subtitle: "máquina virtual", appBundlePath: dockerAppPath)
                : Identified(kind: .system, title: "Máquina virtual")
        }
        if let path = p.executablePath, systemPrefixes.contains(where: { path.hasPrefix($0) }) {
            let raw = outerAppBundle(path).map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension } ?? p.name
            if let friendly = friendlySystem[raw] ?? friendlySystem[(path as NSString).lastPathComponent] {
                let airplay = raw == "ControlCenter" && (ports.contains(5000) || ports.contains(7000))
                return Identified(kind: .system, title: friendly, subtitle: airplay ? "Receptor AirPlay" : raw, project: nil)
            }
            let bundle = systemBundle(path)
            return Identified(kind: .system, title: raw, subtitle: bundle == raw ? nil : bundle, project: nil)
        }
        if let path = p.executablePath, let range = path.range(of: ".AppBundle/") {
            let name = ((path[..<range.lowerBound]) as Substring).split(separator: "/").last.map(String.init) ?? p.name
            return Identified(kind: .other, title: name, subtitle: [p.name, portText].compactMap { $0 }.joined(separator: " · "), project: nil)
        }
        if let app = outerAppBundle(p.executablePath), !app.hasSuffix("/Python.app") {
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
        if let interpreter = interpreters[argv0.lowercased()] ?? interpreters[p.name.lowercased()],
           let script = p.arguments.dropFirst().first(where: { !$0.hasPrefix("-") && scriptExtensions.contains(($0 as NSString).pathExtension.lowercased()) }) {
            let subtitle = [interpreter, project, portText].compactMap { $0 }.joined(separator: " · ")
            return Identified(kind: .other, title: (script as NSString).lastPathComponent, subtitle: subtitle, project: project)
        }
        return Identified(kind: .other, title: p.name, subtitle: [project, portText].compactMap { $0 }.joined(separator: " · ").nilIfEmpty, project: project)
    }

    private static func mcpTitle(_ args: [String]) -> String {
        let token = args.map { ($0 as NSString).lastPathComponent }.first { $0.hasSuffix("mcp") || $0.contains("-mcp") } ?? "mcp"
        let base = token.replacingOccurrences(of: "-mcp", with: "").replacingOccurrences(of: "mcp", with: "")
        let name = base.split(separator: "@").first.map(String.init) ?? base
        return name.isEmpty ? "Servidor MCP" : name.prefix(1).uppercased() + name.dropFirst() + " MCP"
    }

    /// Innermost bundle name ("FileProvider" for .../FileProvider.framework/Support/fileproviderd), nil for bare tools.
    static func systemBundle(_ path: String) -> String? {
        let exts: Set<String> = ["app", "framework", "xpc", "appex", "bundle", "service", "plugin"]
        return path.split(separator: "/").dropLast().last { exts.contains((String($0) as NSString).pathExtension) }
            .map { (String($0) as NSString).deletingPathExtension }
    }

    static func outerAppBundle(_ path: String?) -> String? {
        guard let path, let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    static func projectName(from cwd: String?) -> String? {
        ProjectResolver.shared.project(for: cwd)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

public final class ProjectResolver: @unchecked Sendable {
    public static let shared = ProjectResolver()
    private let exists: (String) -> Bool
    private let home: String
    private var cache: [String: String?] = [:]
    private let lock = NSLock()

    public init(exists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
                home: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.exists = exists
        self.home = home
    }

    public func project(for cwd: String?) -> String? {
        guard let cwd, cwd != "/" else { return nil }
        lock.lock()
        if let hit = cache[cwd] { lock.unlock(); return hit }
        lock.unlock()
        let value = resolve(cwd)
        lock.lock()
        cache[cwd] = value
        lock.unlock()
        return value
    }

    private func resolve(_ cwd: String) -> String? {
        var url = URL(fileURLWithPath: cwd)
        var nearest: URL?
        while url.path.count > 1, url.path != home {
            if exists(url.appendingPathComponent(".git").path) { return url.lastPathComponent }
            if nearest == nil, ["package.json", "pom.xml", "Cargo.toml"].contains(where: { exists(url.appendingPathComponent($0).path) }) {
                nearest = url
            }
            url.deleteLastPathComponent()
        }
        return nearest?.lastPathComponent
    }
}
