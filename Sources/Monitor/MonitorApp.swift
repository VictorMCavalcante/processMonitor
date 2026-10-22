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
            WindowRoot(store: store)
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

private struct WindowRoot: View {
    let store: MonitorStore

    var body: some View {
        Group {
            if store.windowVisible { MainWindow(store: store) } else { Theme.bg }
        }
        .onAppear { store.windowVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            guard let window = note.object as? NSWindow, window.identifier?.rawValue.hasPrefix("main") == true else { return }
            store.windowVisible = false
        }
    }
}
