import Testing
@testable import MonitorCore

@Test func teamsHelpersBecomeOneGroup() {
    let rows = (1...9).map { ProcessRow.fixture(pid: Int32($0), app: "/Applications/Microsoft Teams.app", bytes: 100) }
    let g = Grouping.group(rows, mode: .byApp)
    #expect(g.count == 1)
    #expect(g[0].rows.count == 9)
    #expect(g[0].footprintBytes == 900)
    #expect(g[0].title == "Microsoft Teams")
}

@Test func claudeSessionsGroupTogether() {
    let rows = [ProcessRow.fixture(pid: 1, kind: .claudeSession, project: "immobile"), .fixture(pid: 2, kind: .claudeSession, project: "m4all")]
    let byApp = Grouping.group(rows, mode: .byApp)
    #expect(byApp.count == 1)
    #expect(byApp[0].subtitle == "2 sessões")
    #expect(Grouping.group(rows, mode: .byProject).count == 2)
}

@Test func sortedByMemoryDesc() {
    let rows = [ProcessRow.fixture(pid: 1, bytes: 10), .fixture(pid: 2, bytes: 30)]
    #expect(Grouping.group(rows, mode: .flat).map(\.footprintBytes) == [30, 10])
}

@Test func pluginProcessesGroupUnderThePluginThatLaunchedThem() {
    let worker = ProcessSnapshot.fixture(pid: 10, name: "bun", arguments: ["bun", "/u/.claude/plugins/cache/org/claude-mem/1.0/worker.cjs"])
    let uv = ProcessSnapshot.fixture(pid: 11, name: "uv", arguments: ["uv", "chroma-mcp"], ppid: 10)
    let session = ProcessSnapshot.fixture(pid: 12, name: "claude", arguments: ["claude", "--output-format", "stream-json"], ppid: 10)
    let other = ProcessSnapshot.fixture(pid: 13, name: "node", arguments: ["node", "x.js"])
    let snaps = [worker, uv, session, other]
    let context = ClassifyContext(dockerRunning: false, plugins: Classifier.plugins(in: snaps))
    #expect(context.plugins == [10: "claude-mem", 11: "claude-mem", 12: "claude-mem"])
    let rows = snaps.map { ProcessRow(snapshot: $0, identified: Classifier.classify($0, ports: [], context: context), cpuPercent: 0, ports: []) }
    let group = Grouping.group(rows, mode: .byApp).first { $0.id == "plugin:claude-mem" }
    #expect(group?.rows.count == 3)
    #expect(group?.title == "claude-mem")
}

@Test func fleetProcessesGroupTogetherAndCannotBeClosed() {
    let snaps = [
        ProcessSnapshot.fixture(pid: 20, name: "orbit", uid: 0, executablePath: "/opt/orbit/bin/orbit/orbit"),
        ProcessSnapshot.fixture(pid: 21, name: "osqueryd", ppid: 20, uid: 0, executablePath: "/opt/orbit/bin/osqueryd/macos-app/stable/osquery.app/Contents/MacOS/osqueryd"),
        ProcessSnapshot.fixture(pid: 22, name: "fleet-desktop", executablePath: "/opt/orbit/bin/desktop/macos/stable/Fleet Desktop.app/Contents/MacOS/fleet-desktop"),
    ]
    let rows = snaps.map { ProcessRow(snapshot: $0, identified: Classifier.classify($0, ports: []), cpuPercent: 0, ports: []) }
    let groups = Grouping.group(rows, mode: .byApp)
    #expect(groups.count == 1)
    #expect(groups.first?.title == "Fleet")
    guard let g = groups.first, case .notAllowed = TerminationPlanner.plan(g, all: snaps, mode: .normal, myUid: 501) else { Issue.record("expected notAllowed"); return }
}
