import Foundation
import Testing
@testable import MonitorCore

@Test func relaunchesAfterQuit() {
    var running = true
    var relaunched = false
    var polls = 0
    let r = Restarter.run(quit: { true }, isRunning: { polls += 1; if polls > 2 { running = false }; return running }, relaunch: { relaunched = true }, sleep: { _ in })
    #expect(r == nil && relaunched)
}

@Test func timeoutDoesNotRelaunch() {
    var relaunched = false
    let r = Restarter.run(quit: { true }, isRunning: { true }, relaunch: { relaunched = true }, timeout: 1, poll: 0.25, sleep: { _ in })
    #expect(r?.contains("Não foi reaberto") == true && !relaunched)
}

@Test func refusedQuit() {
    #expect(Restarter.run(quit: { false }, isRunning: { true }, relaunch: {}, sleep: { _ in }) == "O app não aceitou fechar.")
}
