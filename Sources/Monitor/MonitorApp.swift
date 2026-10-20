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
            Text("Janela detalhada")
                .frame(minWidth: 900, minHeight: 600)
                .onAppear { store.windowVisible = true }
                .onDisappear { store.windowVisible = false }
        }
    }
}
