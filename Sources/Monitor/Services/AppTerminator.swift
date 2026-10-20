import AppKit

enum AppTerminator {
    static func quit(bundlePath: String, force: Bool) -> String? {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.path == bundlePath }
        guard !apps.isEmpty else { return "O app não está mais aberto." }
        let ok = apps.map { force ? $0.forceTerminate() : $0.terminate() }.contains(true)
        return ok ? nil : "O app não aceitou fechar. Tente Forçar."
    }
}
