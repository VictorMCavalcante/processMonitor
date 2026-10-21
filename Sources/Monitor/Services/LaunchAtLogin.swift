import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {}
        UserDefaults.standard.set(on, forKey: "launchAtLoginWanted")
    }

    static func setupOnFirstRun() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let defaults = UserDefaults.standard
        let path = Bundle.main.bundlePath
        if !defaults.bool(forKey: "didSetupLaunchAtLogin") {
            set(true)
            defaults.set(true, forKey: "didSetupLaunchAtLogin")
        } else if defaults.string(forKey: "launchAtLoginPath") != path, defaults.object(forKey: "launchAtLoginWanted") as? Bool ?? true {
            set(true)
        }
        defaults.set(path, forKey: "launchAtLoginPath")
    }
}
