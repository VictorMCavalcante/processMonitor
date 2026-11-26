import Foundation
import ServiceManagement

enum LaunchAtLogin {
    private static let wantedKey = "launchAtLoginWanted"
    private static let pathKey = "launchAtLoginPath"

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns a message for the user when the change didn't take, nil on success.
    @discardableResult
    static func set(_ on: Bool) -> String? {
        let service = SMAppService.mainApp
        do {
            if on { try service.register() } else { try service.unregister() }
        } catch {
            if on, service.status == .requiresApproval {
                UserDefaults.standard.set(true, forKey: wantedKey)
                SMAppService.openSystemSettingsLoginItems()
                return "Permita o Vernio em Ajustes do Sistema › Itens de Início."
            }
            return "Não foi possível \(on ? "ativar" : "desativar"): \(error.localizedDescription)"
        }
        UserDefaults.standard.set(on, forKey: wantedKey)
        if on, service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return "Permita o Vernio em Ajustes do Sistema › Itens de Início."
        }
        return nil
    }

    /// Off by default: the user turns it on in Preferences. After that, keep the wish in sync with
    /// System Settings, and follow the app when it moves to another Applications folder.
    static func syncOnLaunch() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let path = Bundle.main.bundlePath
        // Dev builds (.build, DerivedData, Downloads) never touch the login item.
        guard path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/") else { return }
        let defaults = UserDefaults.standard
        let status = SMAppService.mainApp.status
        if defaults.string(forKey: pathKey) == path {
            // Same copy: what System Settings says wins (the user may have switched it off there).
            if status != .requiresApproval { defaults.set(status == .enabled, forKey: wantedKey) }
        } else if defaults.bool(forKey: wantedKey), status != .enabled {
            set(true)
        }
        defaults.set(path, forKey: pathKey)
    }
}
