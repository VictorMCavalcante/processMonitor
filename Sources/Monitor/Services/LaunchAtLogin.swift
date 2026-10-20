import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {}
    }

    static func setupOnFirstRun() {
        guard Bundle.main.bundleIdentifier != nil, !UserDefaults.standard.bool(forKey: "didSetupLaunchAtLogin") else { return }
        set(true)
        UserDefaults.standard.set(true, forKey: "didSetupLaunchAtLogin")
    }
}
