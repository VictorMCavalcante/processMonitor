import Foundation
import Testing
@testable import MonitorCore

@Test func parsesPsLine() {
    let line = #"{"ID":"abc123","Names":"immobile-postgres","Image":"postgres:16","State":"running","Labels":"com.docker.compose.project=immobile,com.docker.compose.service=postgres","Ports":"0.0.0.0:5432->5432/tcp, [::]:5432->5432/tcp"}"#
    let c = DockerClient.parsePs(line)
    #expect(c.count == 1)
    #expect(c.first?.name == "immobile-postgres" && c.first?.composeProject == "immobile" && c.first?.publishedPorts == [5432])
}

@Test func parsesMemoryUnits() {
    #expect(DockerClient.parseMemory("512MiB / 7.6GiB") == 536_870_912)
    #expect(DockerClient.parseMemory("1.5GiB / 7.6GiB") == 1_610_612_736)
    #expect(DockerClient.parseMemory("garbage") == 0)
}

@Test func missingOrHangingDockerYieldsEmpty() {
    struct Dead: CommandRunner {
        func run(_ p: String, _ a: [String], timeout: TimeInterval) -> (status: Int32, output: String)? { nil }
    }
    let c = DockerClient(runner: Dead())
    #expect(c.list().isEmpty && c.runningCount() == 0)
}

@Test func listJoinsPsAndStats() {
    struct Fake: CommandRunner {
        func run(_ p: String, _ a: [String], timeout: TimeInterval) -> (status: Int32, output: String)? {
            if a.first == "ps" { return (0, #"{"ID":"abc123","Names":"pg","Image":"postgres:16","State":"running","Labels":"","Ports":""}"#) }
            if a.first == "stats" { return (0, #"{"Container":"abc123","MemUsage":"512MiB / 7.6GiB","CPUPerc":"3.25%"}"#) }
            return nil
        }
    }
    let c = DockerClient(runner: Fake(), paths: ["/usr/bin/true"]).list()
    #expect(c.first?.memoryBytes == 536_870_912 && c.first?.cpuPercent == 3.25)
}

@Test func realRunnerTimesOut() {
    let start = Date()
    #expect(SystemCommandRunner().run("/bin/sleep", ["5"], timeout: 0.5) == nil)
    #expect(Date().timeIntervalSince(start) < 2)
}
