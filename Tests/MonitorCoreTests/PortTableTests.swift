import Foundation
import Testing
@testable import MonitorCore

@Test func dockerPortMapsToContainer() {
    let docker = ProcessRow.fixture(pid: 50, app: "/Applications/Docker.app")
    let c = DockerContainer(id: "abc", name: "immobile-postgres", image: "postgres:16", state: "running", composeProject: "immobile", memoryBytes: 1, cpuPercent: 0, publishedPorts: [5432])
    let e = PortTable.build(sockets: [ListeningSocket(pid: 50, port: 5432, exposure: .network)], rows: [docker], containers: [c])
    #expect(e.first?.owner == .container(c) && e.first?.title == "immobile-postgres" && e.first?.project == "immobile")
    #expect(PortTable.release(port: 5432, entries: e, all: [docker.snapshot], myUid: 501) == .stopContainer(id: "abc", name: "immobile-postgres"))
}

@Test func freePortSaysFree() {
    #expect(PortTable.release(port: 9999, entries: [], all: [], myUid: 501) == .free)
}

@Test func devServerPortClosesChain() {
    let row = ProcessRow.fixture(pid: 71066, kind: .devServer, project: "eleva")
    let e = PortTable.build(sockets: [ListeningSocket(pid: 71066, port: 3000, exposure: .local)], rows: [row], containers: [])
    guard case .close(let g) = PortTable.release(port: 3000, entries: e, all: [row.snapshot], myUid: 501) else { Issue.record("expected close"); return }
    #expect(g.kind == .devServer && g.rows.map(\.id) == [71066])
}

@Test func vanishedOwnerIsBlockedWithGoneMessage() {
    let row = ProcessRow.fixture(pid: 7, kind: .other)
    let e = PortTable.build(sockets: [ListeningSocket(pid: 7, port: 8000, exposure: .local)], rows: [row], containers: [])
    #expect(PortTable.release(port: 8000, entries: e, all: [], myUid: 501) == .blocked(TerminationPlanner.alreadyGone))
}

@Test func otherUserPortIsBlocked() {
    let snap = ProcessSnapshot.fixture(pid: 9, name: "mysqld", uid: 74)
    let row = ProcessRow(snapshot: snap, identified: Identified(kind: .database, title: "MySQL"), cpuPercent: 0, ports: [3306])
    let e = PortTable.build(sockets: [ListeningSocket(pid: 9, port: 3306, exposure: .local)], rows: [row], containers: [])
    guard case .blocked = PortTable.release(port: 3306, entries: e, all: [snap], myUid: 501) else { Issue.record("expected blocked"); return }
}
