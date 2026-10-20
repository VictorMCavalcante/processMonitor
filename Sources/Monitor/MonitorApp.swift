import SwiftUI

@main
struct MonitorApp: App {
    @State private var store = MonitorStore()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
                .task { store.start() }
        } label: {
            MenuBarLabel(stats: store.stats)
                .task { store.start() }
        }
        .menuBarExtraStyle(.window)

        Window("Monitor", id: "main") {
            MainWindow(store: store)
                .onAppear { store.windowVisible = true }
                .onDisappear { store.windowVisible = false }
        }
        .defaultSize(width: 1240, height: 820)
    }
}
