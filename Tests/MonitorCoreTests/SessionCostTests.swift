import Foundation
import Testing
@testable import MonitorCore

@Test func sumsMcpSubtreesOnly() {
    func r(_ pid: Int32, _ ppid: Int32, _ kind: ProcessKind, _ title: String, _ bytes: UInt64) -> ProcessRow {
        ProcessRow(snapshot: .fixture(pid: pid, name: title, ppid: ppid, bytes: bytes), identified: Identified(kind: kind, title: title), cpuPercent: 0, ports: [])
    }
    let rows = [
        r(100, 1, .claudeSession, "Claude Code", 400), r(101, 100, .other, "npm", 50), r(102, 101, .mcpServer, "Playwright MCP", 100),
        r(103, 102, .appProcess, "Chrome", 600), r(110, 100, .shell, "Terminal (zsh)", 5), r(111, 110, .devServer, "Next.js dev", 2000),
    ]
    let c = SessionCost.compute(session: rows[0].snapshot, rows: rows)
    #expect(c.totalBytes == 1150)
    #expect(c.parts == [PeakItem(title: "Claude Code", bytes: 400), PeakItem(title: "Playwright MCP", bytes: 750)])
}
