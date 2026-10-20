import MonitorCore
import UserNotifications

enum Notifier {
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "notificationsEnabled") }
    }

    static func requestAuthorization() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(_ alert: AlertKind) {
        guard enabled, Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        switch alert {
        case .pressureRose(let level):
            content.title = level == .critical ? "Pressão de memória crítica" : "Pressão de memória moderada"
            content.body = "Abra o Monitor para ver o que está consumindo memória."
        case .newSuspect(_, let title):
            content.title = "Processo esquecido: \(title)"
            content.body = "Parece aberto e sem uso. Você decide se fecha."
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
