import Darwin
import Foundation
import Testing
@testable import MonitorCore

@Test func staleSnapshotIsNotSignaledWhenPidReused() {
    let clicked = ProcessSnapshot.fixture(pid: 700, name: "claude", ppid: 1, start: Date(timeIntervalSince1970: 1))
    let reused = ProcessSnapshot.fixture(pid: 700, name: "other", ppid: 1, start: Date(timeIntervalSince1970: 500))
    let child = ProcessSnapshot.fixture(pid: 701, name: "child", ppid: 700, start: Date(timeIntervalSince1970: 501))
    let g = ProcessGroup.fixture(kind: .claudeSession, pids: [700], in: [clicked])
    let plan = TerminationPlanner.plan(g, all: [reused, child], mode: .normal, myUid: 501)
    #expect(plan == .notAllowed(reason: "O processo já tinha terminado."))
}

@Test func closingOneDevServerSparesSiblings() {
    let all: [ProcessSnapshot] = [
        .fixture(pid: 10, name: "zsh", ppid: 1),
        .fixture(pid: 20, name: "node", arguments: ["node", "turbo", "run", "dev"], ppid: 10),
        .fixture(pid: 30, name: "npm", arguments: ["npm", "run", "dev"], ppid: 20),
        .fixture(pid: 31, name: "next-server (v16.2.4)", ppid: 30),
        .fixture(pid: 40, name: "npm", arguments: ["npm", "run", "dev"], ppid: 20),
        .fixture(pid: 41, name: "node", arguments: ["node", "vite"], ppid: 40),
    ]
    guard case .signals(let steps) = TerminationPlanner.plan(.fixture(kind: .devServer, pids: [31], in: all), all: all, mode: .normal, myUid: 501) else { Issue.record("expected signals"); return }
    #expect(Set(steps.map(\.pid)) == [31, 30])
}

@Test func confirmationCountsPlanSize() {
    var all: [ProcessSnapshot] = [.fixture(pid: 100, name: "x", ppid: 1)]
    for i in 1...6 { all.append(.fixture(pid: Int32(100 + i), name: "c", ppid: 100)) }
    #expect(TerminationPlanner.needsConfirmation(.fixture(kind: .other, pids: [100], in: all), all: all, myUid: 501))
}

@Test func mainAppProcessRowKeepsNormalQuit() {
    let row = ProcessRow.fixture(pid: 5, app: "/Applications/Pages.app")
    let g = TerminationPlanner.singleRowGroup(row, isRunningApp: true)
    #expect(TerminationPlanner.plan(g, all: [row.snapshot], mode: .normal, myUid: 501) == .quitApp(bundlePath: "/Applications/Pages.app", force: false))
    let helper = TerminationPlanner.singleRowGroup(row, isRunningApp: false)
    guard case .signals = TerminationPlanner.plan(helper, all: [row.snapshot], mode: .normal, myUid: 501) else { Issue.record("helper should signal"); return }
}

@Test func rootAppBundleIsNotAllowed() {
    let snap = ProcessSnapshot.fixture(pid: 80, name: "suhelperd", uid: 0, executablePath: "/Applications/Some.app/Contents/MacOS/suhelperd")
    let row = ProcessRow(snapshot: snap, identified: Classifier.classify(snap, ports: []), cpuPercent: 0, ports: [])
    let g = ProcessGroup(id: "g", title: "Some", subtitle: nil, kind: row.identified.kind, rows: [row])
    guard case .notAllowed = TerminationPlanner.plan(g, all: [snap], mode: .normal, myUid: 501) else { Issue.record("expected notAllowed"); return }
}

@Test func systemProcessesAreBlocked() {
    let snap = ProcessSnapshot.fixture(pid: 90, name: "loginwindow", uid: 501, executablePath: "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow")
    let id = Classifier.classify(snap, ports: [])
    #expect(id.kind == .system)
    let g = ProcessGroup(id: "g", title: id.title, subtitle: nil, kind: id.kind, rows: [ProcessRow(snapshot: snap, identified: id, cpuPercent: 0, ports: [])])
    guard case .notAllowed = TerminationPlanner.plan(g, all: [snap], mode: .force, myUid: 501) else { Issue.record("expected notAllowed"); return }
}

@Test func terminalAppsNeedConfirmation() {
    let snap = ProcessSnapshot.fixture(pid: 91, name: "Terminal", executablePath: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal")
    let id = Classifier.classify(snap, ports: [])
    #expect(id.kind == .appProcess)
    let g = ProcessGroup(id: "g", title: id.title, subtitle: nil, kind: id.kind, rows: [ProcessRow(snapshot: snap, identified: id, cpuPercent: 0, ports: [])])
    #expect(TerminationPlanner.needsConfirmation(g, all: [snap], myUid: 501))
}

@Test func briefSuspendIsNotForgotten() {
    let now = Date(timeIntervalSince1970: 10 * 86_400)
    let r = ProcessRow.fixture(pid: 2, kind: .claudeSession, state: .stopped, start: now.addingTimeInterval(-5 * 86_400))
    let ignore = IgnoreList(defaults: .ephemeral())
    #expect(ForgottenDetector.detect([r], allPids: [2], now: now, ignore: ignore, stoppedSince: [2: now.addingTimeInterval(-15)]).isEmpty)
    let s = ForgottenDetector.detect([r], allPids: [2], now: now, ignore: ignore, stoppedSince: [2: now.addingTimeInterval(-2 * 86_400)])
    #expect(s.first?.hint == "Sessão suspensa (Ctrl+Z) há 2 dias.")
}

@Test func restoredPolicyDoesNotRenotify() {
    let s = Suspect.fixture(pid: 1, kind: .mcpServer, project: "immobile")
    var first = NotificationPolicy()
    _ = first.evaluate(level: .normal, suspects: [s], now: .now)
    var restored = NotificationPolicy(seen: first.seen)
    #expect(restored.evaluate(level: .normal, suspects: [s], now: .now).isEmpty)
}

@Test func criticalBypassesCooldown() {
    var p = NotificationPolicy()
    let t = Date(timeIntervalSince1970: 0)
    _ = p.evaluate(level: .warning, suspects: [], now: t)
    #expect(p.evaluate(level: .critical, suspects: [], now: t.addingTimeInterval(60)) == [.pressureRose(.critical)])
}

@Test func projectLookupIsCached() {
    final class Counter: @unchecked Sendable { var n = 0 }
    let c = Counter()
    let resolver = ProjectResolver { path in c.n += 1; return path.hasSuffix("/proj/.git") }
    #expect(resolver.project(for: "/x/proj/src") == "proj")
    let calls = c.n
    #expect(resolver.project(for: "/x/proj/src") == "proj")
    #expect(c.n == calls)
}
