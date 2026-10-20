import AppKit
import MonitorCore

enum AppRestarter {
    static func restart(bundlePath: String) async -> String? {
        let url = URL(fileURLWithPath: bundlePath)
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.path == bundlePath }
        guard !apps.isEmpty else { return "O app não está aberto." }
        let message = await Task.detached { () -> String? in
            Restarter.run(
                quit: { apps.map { $0.terminate() }.contains(true) },
                isRunning: { apps.contains { !$0.isTerminated } },
                relaunch: {}
            )
        }.value
        guard message == nil else { return message }
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return nil
        } catch {
            return "O app fechou, mas não foi possível reabrir."
        }
    }
}
