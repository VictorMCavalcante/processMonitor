import AppKit
import MonitorCore
import SwiftUI

struct DiskView: View {
    let store: MonitorStore
    let onClean: ([DiskItem]) -> Void
    @State private var selected: Set<String> = []
    @State private var expanded: Set<String> = []
    @State private var known: Set<String> = []
    @State private var defaults: [String: Bool] = [:]

    private var busy: Bool { store.diskScanning || store.diskCleaning }
    private var cleanHint: String { store.canClean ? "" : busy ? "Aguarde a análise terminar" : "Analise de novo (↻) para limpar" }

    var body: some View {
        VStack(spacing: 10) {
            header
            if let d = store.disk {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            cards(d, proxy)
                            bar(d)
                            if d.protectedSkipped { accessNote }
                            sections(d)
                        }
                    }
                }
                footer(d)
            } else {
                ProgressView("Analisando o disco…").font(.system(size: 12)).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .font(.system(size: 12.5))
        .onChange(of: store.disk, initial: true) { _, d in
            let leaves = (d?.items ?? []).flatMap(\.leaves)
            let ids = Set(leaves.map(\.id))
            let fresh = leaves.filter { $0.checkedByDefault && !known.contains($0.id) }.map(\.id)
            let turnedOff = leaves.filter { !$0.checkedByDefault && defaults[$0.id] == true }.map(\.id)
            selected = (store.diskScanning ? selected : selected.intersection(ids)).union(fresh).subtracting(turnedOff)
            known = store.diskScanning ? known.union(ids) : ids
            for leaf in leaves { defaults[leaf.id] = leaf.checkedByDefault }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Spacer()
            if busy { ProgressView().controlSize(.small) }
            if let p = store.diskProgress {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(p.stage + (p.total.map { "… \(p.done ?? 0) de \($0)" } ?? "…")).font(.system(size: 11)).foregroundStyle(Theme.muted).monospacedDigit()
                    if let total = p.total {
                        ProgressView(value: Double(min(p.done ?? 0, total)), total: Double(max(total, 1))).progressViewStyle(.linear).controlSize(.small).frame(width: 160, height: 2)
                    }
                }
            } else if let d = store.disk {
                Text("analisado há \(Format.age(since: d.scannedAt, now: store.now))").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            Button { Task { await store.analyzeDisk() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).foregroundStyle(Theme.muted).disabled(busy).help("Analisar de novo")
        }
    }

    private func cards(_ d: DiskReport, _ proxy: ScrollViewProxy) -> some View {
        let safe = d.items.filter { $0.category == .safe }.flatMap(\.leaves).filter(\.checkedByDefault)
        let removed = d.items.filter { $0.category == .leftover }.count
        let maybe = d.items.filter { $0.category == .maybeLeftover }.count
        let data = d.items.filter { $0.category == .appData }
        return HStack(spacing: 10) {
            card("Livre", Format.bytes(d.free), Theme.text, target: nil, proxy) {
                Text("de \(Format.bytes(d.total))").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            card("Seguro limpar", Format.bytes(d.bytes(.safe)), Theme.ok, target: "safe", proxy) {
                Button("Limpar o seguro…") { onClean(safe) }.buttonStyle(PillButton(color: Theme.ok)).disabled(safe.isEmpty || !store.canClean).help(cleanHint)
            }
            card("Sobras de apps", Format.bytes(d.bytes(.leftover)), Theme.warn, target: "leftover", proxy) {
                Text((removed == 1 ? "1 app removido" : "\(removed) apps removidos") + (maybe > 0 ? " + \(maybe) a conferir" : "")).font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            card("Dados de apps", Format.bytes(d.bytes(.appData)), Theme.accent, target: "appData", proxy) {
                Text(data.prefix(2).map(\.title).joined(separator: ", ") + (data.count > 2 ? "…" : ""))
                    .font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
            }
        }
    }

    private func card(_ title: String, _ value: String, _ color: Color, target: String?, _ proxy: ScrollViewProxy,
                      @ViewBuilder sub: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11)).foregroundStyle(Theme.muted)
            Text(value).font(.system(size: 18, weight: .semibold)).foregroundStyle(color)
            sub().padding(.top, 4)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel()
        .contentShape(Rectangle())
        .onTapGesture { if let target { withAnimation { proxy.scrollTo(target, anchor: .top) } } }
    }

    private func bar(_ d: DiskReport) -> some View {
        let parts: [(UInt64, Color)] = [(d.systemOther, Theme.muted2), (d.bytes(.safe), Theme.ok), (d.bytes(.leftover), Theme.warn),
                                        (d.bytes(.appData), Theme.accent), (d.free, Theme.line)]
        let sum = Double(max(1, parts.reduce(0) { $0 + $1.0 }))
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                        p.1.frame(width: geo.size.width * Double(p.0) / sum)
                    }
                }
            }
            .frame(height: 10)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            Text("Sistema · Seguro · Sobras · Dados de apps · Livre").font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
    }

    private var accessNote: some View {
        HStack(spacing: 8) {
            Text("Algumas pastas de apps não foram lidas. Dê Acesso Total ao Disco ao Vernio em Ajustes › Privacidade e Segurança para ver tudo.")
                .font(.system(size: 11)).foregroundStyle(Theme.muted)
            Spacer()
            Button("Abrir Ajustes") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
            }
            .buttonStyle(PillButton())
        }
    }

    @ViewBuilder
    private func sections(_ d: DiskReport) -> some View {
        let safe = d.items.filter { $0.category == .safe }
        let left = d.items.filter { $0.category == .leftover }
        let maybe = d.items.filter { $0.category == .maybeLeftover }
        let data = d.items.filter { $0.category == .appData }
        if !safe.isEmpty {
            section("safe", "Seguro: se recria sozinho", Theme.ok, d.bytes(.safe)) { ForEach(safe) { row($0) } }
        }
        if !left.isEmpty || !maybe.isEmpty {
            section("leftover", "Sobras de apps desinstalados", Theme.warn, d.bytes(.leftover)) {
                ForEach(left) { row($0) }
                if !maybe.isEmpty {
                    Text("Talvez sobra · confira antes").font(.system(size: 11)).foregroundStyle(Theme.muted).padding(.top, 6)
                    ForEach(maybe) { row($0) }
                }
            }
        }
        if !data.isEmpty {
            section("appData", "Seus dados: só informativo", Theme.accent, d.bytes(.appData)) { ForEach(data) { row($0) } }
        }
    }

    private func section(_ id: String, _ title: String, _ color: Color, _ total: UInt64, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title.uppercased()).foregroundStyle(color)
                Spacer()
                Text(Format.bytes(total)).foregroundStyle(Theme.muted)
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.bottom, 3)
            rows()
        }
        .id(id)
    }

    private func row(_ item: DiskItem, child: Bool = false) -> AnyView {
        let checkable = item.category != .appData && item.leaves.contains { $0.action != .none }
        let open = expanded.contains(item.id)
        return AnyView(VStack(spacing: 3) {
            HStack(spacing: 8) {
                if checkable { checkbox(item) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).lineLimit(1)
                    ForEach([item.detail, item.warning].compactMap { $0 }, id: \.self) {
                        Text($0).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
                Spacer()
                Text(item.bytes > 0 ? Format.bytes(item.bytes) : "—").monospacedDigit().frame(width: 70, alignment: .trailing)
                if !item.children.isEmpty {
                    Button(open ? "Ver ▾" : "Ver ▸") { if open { expanded.remove(item.id) } else { expanded.insert(item.id) } }.buttonStyle(PillButton())
                }
                if let path = item.revealPath {
                    Button("Revelar") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }.buttonStyle(PillButton())
                }
                if let app = item.appPath {
                    Button("Abrir app") { NSWorkspace.shared.open(URL(fileURLWithPath: app)) }.buttonStyle(PillButton())
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.panel))
            .padding(.leading, child ? 24 : 0)
            if open { ForEach(item.children) { row($0, child: true) } }
        })
    }

    private func checkbox(_ item: DiskItem) -> some View {
        let ids = Set(item.leaves.map(\.id))
        let on = ids.isSubset(of: selected)
        return Button {
            if on { selected.subtract(ids) } else { selected.formUnion(ids) }
        } label: {
            Image(systemName: on ? "checkmark.square.fill" : "square").foregroundStyle(on ? Theme.ok : Theme.muted2)
        }
        .buttonStyle(.plain)
    }

    private func footer(_ d: DiskReport) -> some View {
        let marked = d.items.flatMap(\.leaves).filter { selected.contains($0.id) }
        let total = marked.reduce(UInt64(0)) { $0 + $1.bytes }
        let docker = marked.contains { if case .docker = $0.action { true } else { false } }
        return HStack {
            (Text("\(marked.count) \(marked.count == 1 ? "item marcado" : "itens marcados") · ")
                + Text(Format.bytes(total)).foregroundColor(Theme.text).bold()
                + Text(docker ? " · vai para a Lixeira · Docker apagado na hora" : " · vai para a Lixeira"))
                .font(.system(size: 11)).foregroundStyle(Theme.muted)
            Spacer()
            Button("Limpar marcados…") { onClean(marked) }.buttonStyle(PillButton(color: Theme.ok)).disabled(marked.isEmpty || !store.canClean).help(cleanHint)
        }
        .padding(.top, 10)
        .overlay(alignment: .top) { Theme.line.frame(height: 1) }
    }
}
