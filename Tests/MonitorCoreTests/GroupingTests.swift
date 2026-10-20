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
