import Testing
@testable import MonitorCore

@Test func parsesLsofFieldOutput() {
    let out = "p71066\nf23\nn*:3000\nf24\nn[::1]:3000\np27322\nf30\nn127.0.0.1:5199\n"
    #expect(PortScanner.parse(lsofOutput: out) == [71066: [3000], 27322: [5199]])
}

@Test func garbageYieldsEmpty() {
    #expect(PortScanner.parse(lsofOutput: "xyz\n").isEmpty)
}

@Test func socketsCarryExposureAndMergeFamilies() {
    let out = "p100\nf3\nn127.0.0.1:5199\np200\nf4\nn[::1]:3000\nf5\nn*:3000\np300\nf6\nn[::1]:8080\n"
    #expect(PortScanner.parseSockets(lsofOutput: out) == [
        ListeningSocket(pid: 200, port: 3000, exposure: .network),
        ListeningSocket(pid: 100, port: 5199, exposure: .local),
        ListeningSocket(pid: 300, port: 8080, exposure: .local),
    ])
}

@Test func byPidGroupsPorts() {
    let s = [ListeningSocket(pid: 1, port: 80, exposure: .network), ListeningSocket(pid: 1, port: 443, exposure: .network)]
    #expect(PortScanner.byPid(s) == [1: [80, 443]])
}
