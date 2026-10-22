import Foundation
import Testing
@testable import MonitorCore

@Test func caffeinateUnderClaudeIsNamedAndMerged() {
    let claude = ProcessRow.fixture(pid: 50, kind: .claudeSession)
    let all = [ProcessSnapshot.fixture(pid: 50, name: "claude"), ProcessSnapshot.fixture(pid: 60, name: "caffeinate", ppid: 50), ProcessSnapshot.fixture(pid: 61, name: "caffeinate", ppid: 50),
               ProcessSnapshot.fixture(pid: 529, name: "powerd"), ProcessSnapshot.fixture(pid: 588, name: "WindowServer")]
    let raw: [[String: Any]] = [
        ["pid": 60, "AssertType": "PreventUserIdleSystemSleep", "AssertName": "caffeinate command-line tool", "AssertStartWhen": Date(timeIntervalSince1970: 100)],
        ["pid": 61, "AssertType": "PreventUserIdleSystemSleep", "AssertName": "caffeinate command-line tool", "AssertStartWhen": Date(timeIntervalSince1970: 50)],
        ["pid": 529, "AssertType": "PreventUserIdleSystemSleep", "AssertName": "Powerd - Prevent sleep while display is on"],
        ["pid": 588, "AssertType": "UserIsActive", "AssertName": "x"],
    ]
    let b = SleepBlockers.build(raw, rows: [claude], all: all, now: Date(timeIntervalSince1970: 200))
    #expect(b.map(\.title).sorted() == ["Claude Code está impedindo o Mac de dormir", "Tela ligada"])
    let c = b.first { $0.ownerPid == 50 }
    #expect(c?.since == Date(timeIntervalSince1970: 50))
}

@Test func realAssertionsReadDoesNotCrash() { _ = SleepBlockers.read(now: Date()) }
