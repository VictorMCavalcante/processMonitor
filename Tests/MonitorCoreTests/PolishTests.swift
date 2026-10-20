import Foundation
import Testing
@testable import MonitorCore

@Test func cpuShareUsesWholeMachineScale() {
    #expect(Format.cpu(32.6, cores: 12) == "2,7%")
    #expect(Format.cpu(0, cores: 12) == "0,0%")
    #expect(Format.cpu(1200, cores: 12) == "100,0%")
}

@Test func projectRequiresMarker() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("noproj-\(UUID().uuidString)/MacOS")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp.deletingLastPathComponent()) }
    #expect(ProjectResolver().project(for: tmp.path) == nil)
}

@Test func friendlySystemServiceNames() {
    let cc = Classifier.classify(.fixture(name: "ControlCenter", executablePath: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter"), ports: [5000, 7000])
    #expect(cc.kind == .system && cc.title == "Central de Controle" && cc.subtitle == "Receptor AirPlay")
    let rp = Classifier.classify(.fixture(name: "rapportd", executablePath: "/usr/libexec/rapportd"), ports: [51562])
    #expect(rp.title == "Continuidade (Handoff e AirDrop)")
}

@Test func steamAppBundleGetsAppName() {
    let p = ProcessSnapshot.fixture(name: "steam_osx", executablePath: "/Users/v/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/steam_osx")
    let id = Classifier.classify(p, ports: [27036])
    #expect(id.title == "Steam" && id.project == nil)
}

@Test func scriptNameReplacesInterpreter() {
    let py = Classifier.classify(.fixture(name: "Python", arguments: ["/usr/bin/python3", "-I", "/tmp/x/mock_postmark.py", "emails.jsonl"]), ports: [9999])
    #expect(py.title == "mock_postmark.py" && py.subtitle?.hasPrefix("Python") == true)
    let bun = Classifier.classify(.fixture(name: "bun", arguments: ["/Users/v/.bun/bin/bun", "/Users/v/.claude/plugins/claude-mem/scripts/worker-service.cjs", "--daemon"]), ports: [37777])
    #expect(bun.title == "worker-service.cjs" && bun.subtitle?.hasPrefix("bun") == true)
}

@Test func frameworkPythonAppShowsScript() {
    let path = "/Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python"
    let id = Classifier.classify(.fixture(name: "Python", arguments: [path, "-I", "/tmp/s/mock_postmark.py"], executablePath: path), ports: [9999])
    #expect(id.title == "mock_postmark.py" && id.kind == .other)
}
