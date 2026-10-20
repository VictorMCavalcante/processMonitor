import Foundation
import Testing
@testable import MonitorCore

private let vmPath = "/System/Library/Frameworks/Virtualization.framework/Versions/A/XPCServices/com.apple.Virtualization.VirtualMachine.xpc/Contents/MacOS/com.apple.Virtualization.VirtualMachine"

@Test func vmBelongsToDockerWhenDockerRuns() {
    let id = Classifier.classify(.fixture(name: "com.apple.Virtualization.VirtualMachine", executablePath: vmPath), ports: [], context: ClassifyContext(dockerRunning: true))
    #expect(id == Identified(kind: .appProcess, title: "Docker Desktop", subtitle: "máquina virtual", appBundlePath: "/Applications/Docker.app"))
}

@Test func vmWithoutDockerIsBlockedSystem() {
    let id = Classifier.classify(.fixture(name: "x", executablePath: vmPath), ports: [])
    #expect(id.kind == .system && id.title == "Máquina virtual")
}

@Test func detectsDockerRunning() {
    #expect(Classifier.dockerRunning(in: [.fixture(executablePath: "/Applications/Docker.app/Contents/MacOS/com.docker.backend")]))
    #expect(!Classifier.dockerRunning(in: [.fixture(executablePath: "/bin/zsh")]))
}

@Test func quittingDockerNeedsConfirmation() {
    let g = ProcessGroup.fixture(kind: .appProcess, app: "/Applications/Docker.app")
    #expect(TerminationPlanner.needsConfirmation(g, all: [], myUid: 501))
}
