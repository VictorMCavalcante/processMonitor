import Darwin
import Foundation
import Testing
@testable import MonitorCore

@Test func devServerKillsWholeChainChildrenFirst() {
    let all: [ProcessSnapshot] = [
        .fixture(pid: 50, name: "zsh", ppid: 1),
        .fixture(pid: 60, name: "npm", arguments: ["npm", "run", "dev"], ppid: 50),
        .fixture(pid: 71066, name: "next-server (v16.2.4)", ppid: 60),
        .fixture(pid: 71070, name: "node", ppid: 71066),
    ]
    let g = ProcessGroup.fixture(kind: .devServer, pids: [71066], in: all)
    guard case .signals(let steps) = TerminationPlanner.plan(g, all: all, mode: .normal, myUid: 501) else { Issue.record("expected signals"); return }
    #expect(steps.map(\.pid) == [71070, 71066, 60])
    #expect(steps.allSatisfy { $0.signals == [SIGTERM] })
}

@Test func stoppedGetsContFirst() {
    let all: [ProcessSnapshot] = [.fixture(pid: 16567, name: "claude", ppid: 1, state: .stopped)]
    guard case .signals(let steps) = TerminationPlanner.plan(.fixture(kind: .claudeSession, pids: [16567], in: all), all: all, mode: .normal, myUid: 501) else { Issue.record("expected signals"); return }
    #expect(steps[0].signals == [SIGCONT, SIGTERM])
}

@Test func forceUsesKill() {
    let all: [ProcessSnapshot] = [.fixture(pid: 9, name: "x", ppid: 1)]
    guard case .signals(let steps) = TerminationPlanner.plan(.fixture(kind: .other, pids: [9], in: all), all: all, mode: .force, myUid: 501) else { Issue.record("expected signals"); return }
    #expect(steps[0].signals == [SIGKILL])
}

@Test func appUsesNormalQuit() {
    let g = ProcessGroup.fixture(kind: .appProcess, app: "/Applications/Microsoft Teams.app")
    #expect(TerminationPlanner.plan(g, all: [], mode: .normal, myUid: 501) == .quitApp(bundlePath: "/Applications/Microsoft Teams.app", force: false))
}

@Test func otherUserNotAllowed() {
    let all: [ProcessSnapshot] = [.fixture(pid: 96676, name: "mysqld", uid: 74)]
    guard case .notAllowed(let reason) = TerminationPlanner.plan(.fixture(kind: .database, pids: [96676], in: all), all: all, mode: .normal, myUid: 501) else { Issue.record("expected notAllowed"); return }
    #expect(reason.contains("outro usuário"))
}

@Test func reusedPidIsNotSignaled() {
    final class Fake: Signaler, @unchecked Sendable {
        var sent: [Int32] = []
        func currentStartTime(of pid: Int32) -> Date? { Date(timeIntervalSince1970: 999) }
        func send(_ s: Int32, to pid: Int32) -> Int32 { sent.append(pid); return 0 }
    }
    let f = Fake()
    let r = TerminationExecutor.run([.init(pid: 5, startTime: Date(timeIntervalSince1970: 1), signals: [SIGTERM])], signaler: f)
    #expect(f.sent.isEmpty)
    #expect(r[5] == "O processo já tinha terminado.")
}

@Test func realStoppedProcessDies() throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sleep")
    p.arguments = ["30"]
    try p.run()
    kill(p.processIdentifier, SIGSTOP)
    usleep(100_000)
    let snap = try #require(ProcessSampler().snapshot(pid: p.processIdentifier))
    let g = ProcessGroup.fixture(kind: .other, pids: [snap.id], in: [snap])
    guard case .signals(let steps) = TerminationPlanner.plan(g, all: [snap], mode: .normal, myUid: getuid()) else { Issue.record("expected signals"); return }
    #expect(TerminationExecutor.run(steps, signaler: SystemSignaler()).isEmpty)
    p.waitUntilExit()
    #expect(!p.isRunning)
}

@Test func activeClaudeNeedsConfirmation() {
    let active: [ProcessSnapshot] = [.fixture(pid: 1, name: "claude")]
    let stopped: [ProcessSnapshot] = [.fixture(pid: 1, name: "claude", state: .stopped)]
    #expect(TerminationPlanner.needsConfirmation(.fixture(kind: .claudeSession, pids: [1], in: active), all: active, myUid: 501))
    #expect(!TerminationPlanner.needsConfirmation(.fixture(kind: .claudeSession, pids: [1], in: stopped), all: stopped, myUid: 501))
}

@Test func resumedStoppedProcessThatStaysAliveIsKilled() {
    final class Fake: Signaler, @unchecked Sendable {
        var sent: [Int32] = []
        func currentStartTime(of pid: Int32) -> Date? { Date(timeIntervalSince1970: 1) }
        func send(_ s: Int32, to pid: Int32) -> Int32 { sent.append(s); return 0 }
    }
    let f = Fake()
    _ = TerminationExecutor.run([.init(pid: 5, startTime: Date(timeIntervalSince1970: 1), signals: [SIGCONT, SIGTERM])], signaler: f, grace: 0.1)
    #expect(f.sent == [SIGCONT, SIGTERM, SIGKILL])
}

@Test func claudeTitlePrefersCustomOverAi() {
    let text = """
    {"type":"user","message":{"content":"oi"}}
    {"type":"ai-title","aiTitle":"Planejamento de navegador"}
    {"type":"custom-title","customTitle":"Navegador"}
    """
    #expect(ClaudeSessionTitle.title(inTranscript: text) == "Navegador")
    #expect(ClaudeSessionTitle.title(inTranscript: #"{"type":"ai-title","aiTitle":"X"}"#) == "X")
    #expect(ClaudeSessionTitle.title(inTranscript: "{}") == nil)
}
