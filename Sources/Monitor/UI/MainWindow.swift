import MonitorCore
import SwiftUI

struct MainWindow: View {
    @Bindable var store: MonitorStore
    @State private var selection: Selection?
    @State private var expanded: Set<String> = []
    @State private var pending: (group: ProcessGroup, mode: TerminationMode)?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HStack(spacing: 0) {
                VStack(spacing: 12) {
                    MetricCards(store: store)
                    if !store.suspects.isEmpty { ForgottenBanner(store: store) }
                    ProcessListView(store: store, selection: $selection, expanded: $expanded) { request($0, .normal) }
                    if let message = store.lastMessage {
                        Text(message).font(.system(size: 11)).foregroundStyle(Theme.warn).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(14)
                DetailPanel(store: store, group: selectedGroup, row: selectedRow) { request($0, $1) }
            }
        }
        .background(Theme.bg)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .frame(minWidth: 1100, idealWidth: 1240, minHeight: 720, idealHeight: 820)
        .confirmationDialog(pending.map { "Fechar \($0.group.title)?" } ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button(pending?.mode == .force ? "Forçar" : "Fechar", role: .destructive) {
                if let p = pending { Task { _ = await store.close(p.group, mode: p.mode) } }
                pending = nil
            }
            Button("Cancelar", role: .cancel) { pending = nil }
        } message: {
            Text(pending.map(confirmationText) ?? "")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Buscar processo, projeto, porta…", text: $store.search).textFieldStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(hex: 0x14151A)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.line))
            Picker("", selection: $store.mode) {
                Text("Por app").tag(GroupingMode.byApp)
                Text("Por projeto").tag(GroupingMode.byProject)
                Text("Lista").tag(GroupingMode.flat)
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(LinearGradient(colors: [Color(hex: 0x202127), Color(hex: 0x1B1C21)], startPoint: .top, endPoint: .bottom))
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
    }

    private var selectedGroup: ProcessGroup? {
        guard case .group(let id) = selection else { return nil }
        return store.groups.first { $0.id == id }
    }

    private var selectedRow: ProcessRow? {
        guard case .process(let pid) = selection else { return nil }
        return store.rows.first { $0.id == pid }
    }

    private func request(_ group: ProcessGroup, _ mode: TerminationMode) {
        if TerminationPlanner.needsConfirmation(group) || mode == .force {
            pending = (group, mode)
        } else {
            Task { _ = await store.close(group, mode: mode) }
        }
    }

    private func confirmationText(_ p: (group: ProcessGroup, mode: TerminationMode)) -> String {
        switch store.plan(for: p.group, mode: p.mode) {
        case .quitApp(_, let force): force ? "O app será encerrado à força. Trabalho não salvo pode ser perdido." : "O app será fechado normalmente."
        case .signals(let steps): "Serão encerrados \(steps.count) processo\(steps.count == 1 ? "" : "s"): " + steps.prefix(6).compactMap { s in store.allSnapshots.first { $0.id == s.pid }?.name }.joined(separator: ", ")
        case .notAllowed(let reason): reason
        }
    }
}
