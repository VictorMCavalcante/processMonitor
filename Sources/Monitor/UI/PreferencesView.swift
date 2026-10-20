import MonitorCore
import SwiftUI

struct PreferencesView: View {
    let store: MonitorStore
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var notifications = Notifier.enabled
    @State private var ignored: [(key: IgnoreKey, label: String)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Abrir ao iniciar o Mac", isOn: $launchAtLogin).onChange(of: launchAtLogin) { _, on in LaunchAtLogin.set(on) }
            Toggle("Notificações", isOn: $notifications).onChange(of: notifications) { _, on in Notifier.enabled = on }
            Divider()
            Text("Ignorados").font(.system(size: 12, weight: .semibold))
            if ignored.isEmpty {
                Text("Nenhum processo ignorado.").foregroundStyle(Theme.muted).font(.system(size: 11.5))
            }
            ForEach(ignored, id: \.key) { item in
                HStack {
                    Text(item.label).lineLimit(1)
                    Spacer()
                    Button("Remover") {
                        store.ignore.remove(item.key)
                        ignored = store.ignore.all
                        Task { await store.refresh() }
                    }
                    .buttonStyle(PillButton())
                }
                .font(.system(size: 12))
            }
        }
        .toggleStyle(.switch)
        .padding(16)
        .frame(width: 320)
        .onAppear { ignored = store.ignore.all }
    }
}
