import Foundation
import Testing
@testable import MonitorCore

@Test(arguments: [
    ("next-server (v16.2.4)", ["next-server"], "/Users/v/m4all/contratos/eleva-contracts-ui", ProcessKind.devServer, "Next.js dev"),
    ("node", ["node", "/x/node_modules/.bin/vite", "dev", "--port", "5199"], "/Users/v/wra/systemwra", .devServer, "Vite dev"),
    ("java", ["/opt/java", "-cp", "/Users/v/m4all/eleva-contracts-api/target/classes", "org.springframework.boot.loader"], "/Users/v/m4all/eleva-contracts-api", .devServer, "Spring Boot dev"),
    ("claude", ["claude", "--dangerously-skip-permissions"], "/Users/v/immobile", .claudeSession, "Claude Code"),
    ("node", ["node", "/Users/v/.npm/_npx/x/node_modules/.bin/playwright-mcp"], "/Users/v/immobile", .mcpServer, "Playwright MCP"),
    ("mysqld", ["/usr/local/mysql/bin/mysqld"], nil, .database, "MySQL"),
    ("zsh", ["-zsh"], "/Users/v", .shell, "Terminal (zsh)"),
] as [(String, [String], String?, ProcessKind, String)])
func classifiesKnownCases(name: String, args: [String], cwd: String?, kind: ProcessKind, title: String) {
    let id = Classifier.classify(.fixture(name: name, arguments: args, cwd: cwd), ports: [])
    #expect(id.kind == kind)
    #expect(id.title == title)
}

@Test func helperGroupsUnderOuterApp() {
    let p = ProcessSnapshot.fixture(
        name: "Microsoft Teams WebView Helper (Renderer)",
        executablePath: "/Applications/Microsoft Teams.app/Contents/Helpers/Microsoft Teams WebView.app/Contents/Frameworks/x/Helpers/MSTeams WebView Helper (Renderer).app/Contents/MacOS/h")
    let id = Classifier.classify(p, ports: [])
    #expect(id.kind == .appProcess)
    #expect(id.appBundlePath == "/Applications/Microsoft Teams.app")
    #expect(id.title == "Microsoft Teams")
}

@Test func stoppedClaudeIsFlagged() {
    let id = Classifier.classify(.fixture(name: "claude", arguments: ["claude"], state: .stopped), ports: [])
    #expect(id.subtitle?.contains("suspensa") == true)
}

@Test func claudeVersionNamedProcessIsClaude() {
    let id = Classifier.classify(.fixture(name: "2.1.296", arguments: ["claude", "--dangerously-skip-permissions"]), ports: [])
    #expect(id.kind == .claudeSession)
}

@Test func devServerShowsPorts() {
    let id = Classifier.classify(.fixture(name: "next-server (v16.2.4)", arguments: ["next-server"]), ports: [3000])
    #expect(id.subtitle?.contains(":3000") == true)
}

@Test func unknownKeepsName() {
    #expect(Classifier.classify(.fixture(name: "weird", arguments: ["weird"]), ports: []).title == "weird")
}

@Test func rootWithoutRuleIsSystem() {
    #expect(Classifier.classify(.fixture(name: "mds", arguments: [], uid: 0), ports: []).kind == .system)
}

@Test func projectIsNearestRootWithMarker() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("proj-\(UUID().uuidString)")
    let sub = root.appendingPathComponent("apps/web")
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: root.appendingPathComponent("package.json"))
    defer { try? FileManager.default.removeItem(at: root) }
    let id = Classifier.classify(.fixture(name: "next-server (v16.2.4)", arguments: ["next-server"], cwd: sub.path), ports: [])
    #expect(id.project == root.lastPathComponent)
}

@Test func systemSubtitleIsBundleNameNotPath() {
    let fp = ProcessSnapshot.fixture(name: "fileproviderd", arguments: [], uid: 0, executablePath: "/System/Library/PrivateFrameworks/FileProvider.framework/Support/fileproviderd")
    #expect(Classifier.classify(fp, ports: []).subtitle == "FileProvider")
    let spot = ProcessSnapshot.fixture(name: "Spotlight", arguments: [], uid: 501, executablePath: "/System/Library/CoreServices/Spotlight.app/Contents/MacOS/Spotlight")
    #expect(Classifier.classify(spot, ports: []).subtitle == nil)
    let logd = ProcessSnapshot.fixture(name: "logd", arguments: [], uid: 0, executablePath: "/usr/libexec/logd")
    #expect(Classifier.classify(logd, ports: []).subtitle == "logd")
}

@Test func webKitHelperJoinsHostApp() {
    var web = ProcessSnapshot.fixture(name: "com.apple.WebKit.WebContent", executablePath: "/System/Library/Frameworks/WebKit.framework/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent")
    web.hostAppPath = "/Applications/Safari.app"
    let id = Classifier.classify(web, ports: [])
    #expect(id.appBundlePath == "/Applications/Safari.app")
    #expect(id.title == "Safari")
    #expect(id.subtitle == "Página web (WebKit)")
}

@Test func cryptexAppIsNotSystem() {
    let safari = ProcessSnapshot.fixture(name: "Safari", executablePath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app/Contents/MacOS/Safari")
    #expect(Classifier.classify(safari, ports: []).kind == .appProcess)
}
