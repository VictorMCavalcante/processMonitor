import Foundation
import Testing
@testable import MonitorCore

@Test func flagsTodaysCases() {
    let now = Date(timeIntervalSince1970: 10 * 86_400)
    let rows = [
        ProcessRow.fixture(pid: 1, kind: .devServer, start: now.addingTimeInterval(-4 * 86_400), cpuTimeNs: 1_000_000_000),
        ProcessRow.fixture(pid: 2, kind: .claudeSession, state: .stopped, start: now.addingTimeInterval(-19 * 86_400)),
        ProcessRow.fixture(pid: 3, kind: .mcpServer, ppid: 1),
        ProcessRow.fixture(pid: 4, kind: .devServer, start: now.addingTimeInterval(-3600)),
    ]
    let s = ForgottenDetector.detect(rows, allPids: [1, 2, 3, 4], now: now, ignore: IgnoreList(defaults: .ephemeral()), stoppedSince: [2: now.addingTimeInterval(-19 * 86_400)])
    #expect(Set(s.map(\.id)) == [1, 2, 3])
    #expect(s.first { $0.id == 2 }?.hint == "Sessão suspensa (Ctrl+Z) há 19 dias.")
    #expect(s.first { $0.id == 1 }?.hint == "Aberto há 4 dias e quase sem uso de CPU. Provavelmente esquecido.")
}

@Test func busyDevServerIsNotForgotten() {
    let now = Date(timeIntervalSince1970: 10 * 86_400)
    let r = ProcessRow.fixture(pid: 1, kind: .devServer, start: now.addingTimeInterval(-2 * 86_400), cpuTimeNs: 172_800 * 1_000_000_000 / 10)
    #expect(ForgottenDetector.detect([r], allPids: [1], now: now, ignore: IgnoreList(defaults: .ephemeral())).isEmpty)
}

@Test func mcpWithLiveParentIsNotOrphan() {
    let r = ProcessRow.fixture(pid: 3, kind: .mcpServer, ppid: 2)
    #expect(ForgottenDetector.detect([r], allPids: [2, 3], now: Date(), ignore: IgnoreList(defaults: .ephemeral())).isEmpty)
}

@Test func ignoredNeverFlaggedAndPersists() {
    let d = UserDefaults.ephemeral()
    let r = ProcessRow.fixture(pid: 3, kind: .mcpServer, ppid: 1, project: "immobile")
    IgnoreList(defaults: d).add(.of(r), label: "Playwright MCP")
    #expect(ForgottenDetector.detect([r], allPids: [3], now: Date(), ignore: IgnoreList(defaults: d)).isEmpty)
    #expect(IgnoreList(defaults: d).all.map(\.label) == ["Playwright MCP"])
}

@Test func removingFromIgnoreListRestores() {
    let d = UserDefaults.ephemeral()
    let r = ProcessRow.fixture(pid: 3, kind: .mcpServer, ppid: 1, project: "immobile")
    let list = IgnoreList(defaults: d)
    list.add(.of(r), label: "x")
    list.remove(.of(r))
    #expect(!IgnoreList(defaults: d).contains(.of(r)))
}

@Test func ignoreKeySurvivesRestart() {
    #expect(IgnoreKey.of(.fixture(pid: 10, kind: .devServer, project: "systemwra")) == IgnoreKey.of(.fixture(pid: 99, kind: .devServer, project: "systemwra")))
}
