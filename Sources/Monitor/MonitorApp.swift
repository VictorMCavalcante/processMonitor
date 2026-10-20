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

        Window("Monitor", id: "main") {
            MainWindow(store: store)
                .onAppear { store.windowVisible = true }
                .onDisappear { store.windowVisible = false }
        }
        .defaultSize(width: 1240, height: 820)
    }

    @MainActor
    private func start() {
        let box = policy
        store.onCycle = { store in
            guard let level = store.stats?.level else { return }
            for alert in box.policy.evaluate(level: level, suspects: store.suspects, now: store.now) {
                Notifier.post(alert)
            }
        }
        store.start()
    }
}

@MainActor
final class PolicyBox {
    var policy = NotificationPolicy()
}
