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

@Test func parsesDecimalSizes() {
    #expect(DockerClient.parseDecimalSize("2.1GB (100%)") == 2_100_000_000)
    #expect(DockerClient.parseDecimalSize("512MB") == 512_000_000 && DockerClient.parseDecimalSize("x") == 0)
}

@Test func diskUsageSplitsDanglingAndUnused() {
    struct Fake: CommandRunner {
        func run(_ p: String, _ a: [String], timeout: TimeInterval) -> (status: Int32, output: String)? {
            switch a.prefix(3).joined(separator: " ") {
            case let s where s.hasPrefix("system df"): (0, #"{"Type":"Build Cache","Reclaimable":"1GB (100%)"}"#)
            case let s where s.hasPrefix("images -f dangling=true"): (0, #"{"ID":"d1","Repository":"<none>","Tag":"<none>","Size":"500MB"}"#)
            case let s where s.hasPrefix("images --format"): (0, #"{"ID":"d1","Repository":"<none>","Tag":"<none>","Size":"500MB"}"# + "\n" + #"{"ID":"i1","Repository":"postgres","Tag":"16","Size":"400MB"}"# + "\n" + #"{"ID":"i2","Repository":"wra-api","Tag":"latest","Size":"2GB"}"#)
            case let s where s.hasPrefix("ps -a"): (0, "sha256:i1aaaa postgres:16\n")
            default: nil
            }
        }
    }
    let u = DockerClient(runner: Fake(), paths: ["/usr/bin/true"]).diskUsage()
    #expect(u == DockerDiskUsage(danglingAndBuildCache: 1_500_000_000, unusedImages: 2_000_000_000, unusedImageNames: ["wra-api:latest"]))
}

@Test func pruneReportsHangAndMissingDocker() {
    struct Dead: CommandRunner { func run(_ p: String, _ a: [String], timeout: TimeInterval) -> (status: Int32, output: String)? { nil } }
    #expect(DockerClient(runner: Dead(), paths: ["/usr/bin/true"]).prune(.unusedImages) == "O Docker não respondeu a tempo.")
    #expect(DockerClient(runner: Dead(), paths: ["/nope"]).prune(.unusedImages) == "Docker não encontrado.")
    #expect(DockerClient(runner: Dead(), paths: ["/usr/bin/true"]).diskUsage() == nil)
}

@Test func diskUsageMatchesUntaggedContainersAndSharedIDs() {
    struct Fake: CommandRunner {
        func run(_ p: String, _ a: [String], timeout: TimeInterval) -> (status: Int32, output: String)? {
            switch a.prefix(3).joined(separator: " ") {
            case let s where s.hasPrefix("system df"): (0, "")
            case let s where s.hasPrefix("images -f dangling=true"): (0, "")
            case let s where s.hasPrefix("images --format"): (0, [
                #"{"ID":"i1","Repository":"postgres","Tag":"latest","Size":"400MB"}"#,
                #"{"ID":"u1","Repository":"app","Tag":"v1","Size":"1GB"}"#,
                #"{"ID":"u1","Repository":"app","Tag":"latest","Size":"1GB"}"#,
                #"{"ID":"s1","Repository":"web","Tag":"a","Size":"2GB"}"#,
                #"{"ID":"s1","Repository":"web","Tag":"b","Size":"2GB"}"#].joined(separator: "\n"))
            case let s where s.hasPrefix("ps -a"): (0, "sha256:zzz postgres\nsha256:s1ff web:b\n")
            default: nil
            }
        }
    }
    let u = DockerClient(runner: Fake(), paths: ["/usr/bin/true"]).diskUsage()
    #expect(u == DockerDiskUsage(danglingAndBuildCache: 0, unusedImages: 1_000_000_000, unusedImageNames: ["app:v1", "app:latest"]))
}

@Test func pruneRunsBuilderAllAndReportsFailure() {
    final class Log: @unchecked Sendable { var calls: [String] = [] }
    struct Failing: CommandRunner {
        let log: Log
        func run(_ p: String, _ a: [String], timeout: TimeInterval) -> (status: Int32, output: String)? {
            log.calls.append(a.joined(separator: " "))
            return (a.first == "builder" ? 1 : 0, "")
        }
    }
    let log = Log()
    #expect(DockerClient(runner: Failing(log: log), paths: ["/usr/bin/true"]).prune(.danglingAndBuildCache) == "Não foi possível limpar o Docker.")
    #expect(log.calls == ["image prune -f", "builder prune -a -f"])
    #expect(DockerClient.parseDecimalSize("1.5TB") == 1_500_000_000_000)
}
