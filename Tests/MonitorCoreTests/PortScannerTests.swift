import Testing
@testable import MonitorCore

@Test func parsesLsofFieldOutput() {
    let out = "p71066\nf23\nn*:3000\nf24\nn[::1]:3000\np27322\nf30\nn127.0.0.1:5199\n"
    #expect(PortScanner.parse(lsofOutput: out) == [71066: [3000], 27322: [5199]])
}

@Test func garbageYieldsEmpty() {
    #expect(PortScanner.parse(lsofOutput: "xyz\n").isEmpty)
}
