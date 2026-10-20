import Foundation

public enum Restarter {
    public static func run(
        quit: () -> Bool,
        isRunning: () -> Bool,
        relaunch: () -> Void,
        timeout: TimeInterval = 20,
        poll: TimeInterval = 0.25,
        sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) -> String? {
        guard quit() else { return "O app não aceitou fechar." }
        var waited: TimeInterval = 0
        while isRunning() {
            if waited >= timeout {
                return "O app não fechou em \(Int(timeout)) s (talvez esteja pedindo para salvar). Não foi reaberto."
            }
            sleep(poll)
            waited += poll
        }
        relaunch()
        return nil
    }
}
