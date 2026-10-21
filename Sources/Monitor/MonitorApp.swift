import MonitorCore
import SwiftUI

@main
struct MonitorApp: App {
    @State private var store = MonitorStore()
    @State private var policy = PolicyBox()

    init() {
        LaunchAtLogin.setupOnFirstRun()
        Notifier.requestAuthorization()
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
                .task { start() }
        } label: {
            MenuBarLabel(stats: store.stats)
                .task { start() }
        }
        .menuBarExtraStyle(.window)

        Window("Vernio", id: "main") {
            MainWindow(store: store)
                .onAppear { store.windowVisible = true }
                .onDisappear { store.windowVisible = false }
        }
        .defaultSize(width: 1240, height: 820)
        .windowToolbarStyle(.unified)
    }

    @MainActor
    private func start() {
        let box = policy
        store.onCycle = { store in
            guard let level = store.stats?.level else { return }
            for alert in box.policy.evaluate(level: level, suspects: store.suspects, runaways: store.runaways, now: store.now) {
                Notifier.post(alert)
            }
            box.save()
        }
        store.start()
    }
}

@MainActor
final class PolicyBox {
    private static let key = "notifiedSuspects"
    var policy: NotificationPolicy

    init() {
        let saved = (UserDefaults.standard.data(forKey: Self.key)).flatMap { try? JSONDecoder().decode(Set<IgnoreKey>.self, from: $0) } ?? []
        policy = NotificationPolicy(seen: saved)
    }

    func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(policy.seen), forKey: Self.key)
    }
}
