import MonitorCore
import SwiftUI

enum WindowTab: Hashable {
    case processes(GroupingMode)
    case ports
    case docker
    case peaks
    case disk
}

enum PendingAction {
    case close(ProcessGroup, TerminationMode, dockerContainers: Int?)
    case stopContainer(id: String, name: String)
    case restart(ProcessGroup, dockerContainers: Int)
    case cleanDisk([DiskItem])

    var title: String {
        switch self {
        case .close(let g, _, _): "Fechar \(g.title)?"
        case .stopContainer(_, let name): "Parar o container \(name)?"
        case .restart(let g, _): "Reiniciar \(g.title)?"
        case .cleanDisk(let items): "Limpar \(Format.bytes(items.reduce(0) { $0 + $1.bytes }))?"
        }
    }
}

struct MainWindow: View {
    @Bindable var store: MonitorStore
    @State private var selection: Selection?
    @State private var expanded: Set<String> = []
    @State private var pending: PendingAction?
    @State private var showPreferences = false
    @State private var tab: WindowTab = .processes(.byApp)
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            HStack(spacing: 0) {
                VStack(spacing: 12) {
                    MetricCards(store: store)
                    content
                    if let message = store.lastMessage {
                        Text(message).font(.system(size: 11)).foregroundStyle(Theme.warn).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(14)
                if case .processes = tab {
                    DetailPanel(store: store, group: selectedGroup, row: selectedRow, onClose: { request($0, $1) }, onRestart: { g in
                        if TerminationPlanner.restartNeedsConfirmation(g) {
                            Task { pending = .restart(g, dockerContainers: await store.dockerRunningCount()) }
                        } else {
                            Task { _ = await store.restart(g) }
                        }
                    })
                }
            }
        }
        .background(Theme.bg)
        .foregroundStyle(Theme.text)
        .toolbar { windowToolbar }
        .modifier(HiddenWindowTitle())
        .toolbarBackground(Theme.barTop, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .preferredColorScheme(.dark)
        .tint(Theme.brand)
        .frame(minWidth: 1100, idealWidth: 1240, minHeight: 720, idealHeight: 820)
        .confirmationDialog(pending?.title ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button(confirmLabel, role: .destructive) {
                if let p = pending { perform(p) }
                pending = nil
            }
            Button("Cancelar", role: .cancel) { pending = nil }
        } message: {
            Text(pending.map(confirmationText) ?? "")
        }
        .onChange(of: store.dockerRunning) { _, running in
            if !running, tab == .docker { tab = .processes(store.mode) }
        }
    }

    @ToolbarContentBuilder
    private var windowToolbar: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .navigation) { brand }.sharedBackgroundVisibility(.hidden)
            ToolbarSpacer(.flexible)
            ToolbarItem(placement: .primaryAction) { toolbarActions }.sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) { brand }
            ToolbarItem(placement: .primaryAction) { toolbarActions }
        }
    }

    private var brand: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 22, height: 22)
            Text("vernio").font(.system(size: 15, weight: .semibold)).kerning(-0.3)
        }
        .padding(.leading, 4)
    }

    private var toolbarActions: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Buscar processo, projeto, porta…", text: $store.search)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                Text("⌘F").font(.system(size: 10)).foregroundStyle(Theme.muted2)
                    .padding(.horizontal, 4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.line))
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .frame(width: 300)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.field))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line))
            .background(Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command).opacity(0))
            Button { showPreferences.toggle() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.muted)
                .help("Preferências")
                .popover(isPresented: $showPreferences) { PreferencesView(store: store) }
        }
    }

    private var tabBar: some View {
        HStack(alignment: .bottom, spacing: 20) {
            group("Processos")
            tabButton("Por app", .processes(.byApp))
            tabButton("Por projeto", .processes(.byProject))
            tabButton("Lista", .processes(.flat))
            Theme.line.frame(width: 1, height: 16).padding(.bottom, 11)
            group("Sistema")
            tabButton("Portas", .ports)
            if store.dockerRunning { tabButton("Docker", .docker) }
            tabButton("Picos", .peaks)
            tabButton("Disco", .disk)
            Spacer()
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 18)
        .frame(height: 40, alignment: .bottom)
        .background(Theme.barBottom)
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
    }

    private func group(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .medium))
            .kerning(0.6)
            .foregroundStyle(Theme.muted2)
            .padding(.bottom, 11)
    }

    private func tabButton(_ title: String, _ value: WindowTab) -> some View {
        let on = tab == value
        return Button {
            select(value)
        } label: {
            Text(title)
                .fontWeight(on ? .semibold : .regular)
                .foregroundStyle(on ? Theme.text : Theme.muted)
                .padding(.bottom, 10)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(on ? Theme.brand : .clear).frame(height: 2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    private func select(_ new: WindowTab) {
        tab = new
        if case .processes(let m) = new { store.mode = m }
        if new == .disk { Task { await store.openDiskTab() } }
    }

    private var selectedGroup: ProcessGroup? {
        guard case .group(let id) = selection else { return nil }
        return store.groups.first { $0.id == id }
    }

    private var selectedRow: ProcessRow? {
        guard case .process(let pid) = selection else { return nil }
        return store.rows.first { $0.id == pid }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .processes:
            if !store.suspects.isEmpty { ForgottenBanner(store: store) }
            ProcessListView(store: store, selection: $selection, expanded: $expanded) { request($0, .normal) }
        case .ports:
            PortsView(store: store) { releasePort($0) }
        case .docker:
            DockerView(store: store) { c in pending = .stopContainer(id: c.id, name: c.name) }
        case .peaks:
            PeaksView(store: store)
        case .disk:
            DiskView(store: store) { pending = .cleanDisk($0) }
        }
    }

    private var confirmLabel: String {
        switch pending {
        case .close(_, let mode, _): mode == .force ? "Forçar" : "Fechar"
        case .stopContainer: "Parar"
        case .restart: "Reiniciar"
        case .cleanDisk: "Limpar"
        case nil: "OK"
        }
    }

    private func perform(_ action: PendingAction) {
        switch action {
        case .close(let g, let mode, _):
            Task { _ = await store.close(g, mode: mode) }
        case .stopContainer(let id, _):
            Task { _ = await store.stopContainer(id) }
        case .restart(let g, _):
            Task { _ = await store.restart(g) }
        case .cleanDisk(let items):
            Task { _ = await store.cleanDisk(items) }
        }
    }

    private func releasePort(_ port: UInt16) {
        Task { await handleRelease(port, await store.releasePort(port)) }
    }

    private func handleRelease(_ port: UInt16, _ release: PortRelease) async {
        switch release {
        case .free:
            store.lastMessage = "Porta \(port) livre."
        case .blocked(let reason):
            store.lastMessage = reason
        case .stopContainer(let id, let name):
            pending = .stopContainer(id: id, name: name)
        case .close(let group) where release.requiresConfirmation(all: store.allSnapshots, myUid: getuid()):
            pending = .close(group, .normal, dockerContainers: nil)
        case .close(let group):
            request(group, .normal) {
                if store.sockets.contains(where: { $0.port == port }) { store.lastMessage = "A porta \(port) ainda está em uso." }
                else { store.lastMessage = "Porta \(port) liberada." }
            }
        }
    }

    private func request(_ group: ProcessGroup, _ mode: TerminationMode, after: (@MainActor () -> Void)? = nil) {
        let isDocker = group.rows.first?.identified.appBundlePath == Classifier.dockerAppPath
        if isDocker {
            Task {
                let count = await store.dockerRunningCount()
                pending = .close(group, mode, dockerContainers: count)
            }
        } else if TerminationPlanner.needsConfirmation(group, all: store.allSnapshots, myUid: getuid()) || mode == .force {
            pending = .close(group, mode, dockerContainers: nil)
        } else {
            Task {
                _ = await store.close(group, mode: mode)
                after?()
            }
        }
    }

    private func confirmationText(_ action: PendingAction) -> String {
        switch action {
        case .cleanDisk(let items):
            let projects = items.filter { $0.id.hasSuffix("/node_modules") }.count
            var titles = items.filter { !$0.id.hasSuffix("/node_modules") }.map(\.title) + (projects > 0 ? ["node_modules · \(projects) projetos"] : [])
            if titles.count > 8 { titles = titles.prefix(8) + ["e mais \(titles.count - 8)"] }
            var lines = titles + ["", "Vai para a Lixeira. Esvazie a Lixeira para liberar o espaço."]
            if items.contains(where: { if case .docker = $0.action { true } else { false } }) {
                lines.append("As imagens do Docker são apagadas na hora, sem Lixeira.")
            }
            return lines.joined(separator: "\n")
        case .stopContainer(_, let name):
            return "O container \(name) será parado. Os outros containers continuam rodando."
        case .restart(_, let containers):
            return "O Docker será fechado e reaberto. Isso vai parar todos os containers (\(containers) em execução)."
        case .close(let group, let mode, let containers):
            if let containers { return "Isso vai parar todos os containers (\(containers) em execução)." }
            switch store.plan(for: group, mode: mode) {
            case .quitApp(_, let force): return force ? "O app \(group.title) será encerrado à força. Trabalho não salvo pode ser perdido." : "O app \(group.title) inteiro será fechado normalmente."
            case .signals(let steps): return "Serão encerrados \(steps.count) processo\(steps.count == 1 ? "" : "s"): " + steps.prefix(6).compactMap { s in store.allSnapshots.first { $0.id == s.pid }?.name }.joined(separator: ", ")
            case .notAllowed(let reason): return reason
            }
        }
    }
}

private struct HiddenWindowTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbar(removing: .title)
        } else {
            content.navigationTitle("")
        }
    }
}

