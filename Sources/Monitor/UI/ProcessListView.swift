import AppKit
import MonitorCore
import SwiftUI

enum Selection: Hashable {
    case group(String)
    case process(Int32)
}

struct ProcessListView: View {
    let store: MonitorStore
    @Binding var selection: Selection?
    @Binding var expanded: Set<String>
    let onClose: (ProcessGroup) -> Void

    var body: some View {
        let groups = store.groups
        let maxBytes = max(groups.first?.footprintBytes ?? 1, 1)
        let suspectIds = Set(store.suspects.map(\.id))
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(groups) { g in
                        groupRow(g, maxBytes: maxBytes, suspectIds: suspectIds)
                        if expanded.contains(g.id) && g.rows.count > 1 {
                            ForEach(g.rows) { r in childRow(r, in: g) }
                        }
                    }
                }
            }
        }
        .glassPanel()
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var header: some View {
        columns(icon: AnyView(Color.clear.frame(width: 20, height: 1)), name: AnyView(Text("NOME")), memory: AnyView(sortButton("MEMÓRIA", .memory)),
                cpu: AnyView(sortButton("CPU", .cpu).help("Percentual do Mac inteiro, somando todos os núcleos")), gpu: AnyView(sortButton("GPU", .gpu)), age: AnyView(Text("ABERTO HÁ")), action: AnyView(Color.clear.frame(width: 22, height: 1)))
            .font(.system(size: 10.5)).foregroundStyle(Theme.muted2)
            .background(Theme.panel2)
    }

    private func sortButton(_ title: String, _ sort: GroupSort) -> some View {
        Button { store.sort = sort } label: {
            Text(store.sort == sort ? title + " ▾" : title).foregroundStyle(store.sort == sort ? Theme.text : Theme.muted)
        }
        .buttonStyle(.plain)
    }

    private func groupRow(_ g: ProcessGroup, maxBytes: UInt64, suspectIds: Set<Int32>) -> some View {
        let isSuspect = g.rows.contains { suspectIds.contains($0.id) }
        let isRunaway = g.rows.contains { r in store.runaways.contains { $0.id == r.id } }
        let ignored = g.rows.allSatisfy { store.ignore.contains(.of($0)) }
        let stopped = g.rows.contains { $0.snapshot.state == .stopped }
        let selected = selection == .group(g.id)
        return columns(
            icon: AnyView(AppIcon(title: g.title, appPath: g.rows.first?.identified.appBundlePath)),
            name: AnyView(HStack(spacing: 6) {
                if g.rows.count > 1 {
                    Image(systemName: expanded.contains(g.id) ? "chevron.down" : "chevron.right").font(.system(size: 9)).foregroundStyle(Theme.muted)
                }
                Text(g.title).fontWeight(.semibold).lineLimit(1)
                if let s = g.subtitle { Text(s).foregroundStyle(Theme.muted).font(.system(size: 11)).lineLimit(1) }
                if stopped && g.kind == .claudeSession { Tag(text: g.rows.filter { $0.snapshot.state == .stopped }.count == 1 ? "1 suspensa" : "suspensas", color: Theme.bad) }
                else if isSuspect { Tag(text: "esquecido", color: Theme.warn) }
                if isRunaway { Tag(text: "descontrolado", color: Theme.bad) }
                if ignored { Tag(text: "ignorado", color: Theme.accent) }
            }),
            memory: AnyView(MemoryBar(bytes: g.footprintBytes, fraction: Double(g.footprintBytes) / Double(maxBytes), color: isSuspect ? Theme.warn : ignored ? Theme.muted2 : Theme.accent)),
            cpu: AnyView(Text(Format.cpu(g.cpuPercent, cores: ProcessInfo.processInfo.activeProcessorCount))),
            gpu: AnyView(Text(Format.cpu(g.gpuPercent, cores: 1))),
            age: AnyView(Text(Format.age(since: g.oldestStart, now: store.now))),
            action: AnyView(closeButton(g))
        )
        .background(selected ? Theme.accent.opacity(0.10) : .clear)
        .overlay(alignment: .leading) { if selected { Theme.accent.frame(width: 2) } }
        .contentShape(Rectangle())
        .onTapGesture {
            selection = .group(g.id)
            if g.rows.count > 1 { if expanded.contains(g.id) { expanded.remove(g.id) } else { expanded.insert(g.id) } }
        }
    }

    private func childRow(_ r: ProcessRow, in g: ProcessGroup) -> some View {
        let selected = selection == .process(r.id)
        return columns(
            icon: AnyView(Color.clear.frame(width: 20, height: 1)),
            name: AnyView(HStack(spacing: 6) {
                Text(r.snapshot.name).lineLimit(1)
                Text(([r.ports.isEmpty ? nil : r.ports.map { ":\($0)" }.joined(separator: " ")] + ["PID \(r.id)"]).compactMap { $0 }.joined(separator: " · "))
                    .foregroundStyle(Theme.muted).font(.system(size: 11))
                if r.snapshot.state == .stopped { Tag(text: "suspenso", color: Theme.bad) }
            }.padding(.leading, 18)),
            memory: AnyView(Text(Format.bytes(r.snapshot.footprintBytes))),
            cpu: AnyView(Text(Format.cpu(r.cpuPercent, cores: ProcessInfo.processInfo.activeProcessorCount))),
            gpu: AnyView(Text(Format.cpu(r.gpuPercent, cores: 1))),
            age: AnyView(Text(Format.age(since: r.snapshot.startTime, now: store.now))),
            action: AnyView(closeButton(ProcessWindowModel.single(r)))
        )
        .foregroundStyle(Theme.text.opacity(0.85))
        .background(selected ? Theme.accent.opacity(0.10) : Theme.row)
        .contentShape(Rectangle())
        .onTapGesture { selection = .process(r.id) }
    }

    private func closeButton(_ g: ProcessGroup) -> some View {
        CloseButton(store: store, group: g) { onClose(g) }
    }

    private func columns(icon: AnyView, name: AnyView, memory: AnyView, cpu: AnyView, gpu: AnyView, age: AnyView, action: AnyView) -> some View {
        HStack(spacing: 10) {
            icon.frame(width: 22)
            name.frame(maxWidth: .infinity, alignment: .leading)
            memory.frame(width: 96, alignment: .leading)
            cpu.frame(width: 60, alignment: .leading)
            gpu.frame(width: 60, alignment: .leading)
            age.frame(width: 76, alignment: .leading)
            action.frame(width: 22)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .overlay(alignment: .top) { Theme.line.frame(height: 1) }
    }
}

struct CloseButton: View {
    let store: MonitorStore
    let group: ProcessGroup
    let action: () -> Void

    var body: some View {
        let reason: String? = if case .notAllowed(let r) = store.plan(for: group, mode: .normal) { r } else { nil }
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(reason == nil ? Theme.muted : Theme.muted2.opacity(0.4))
        .disabled(reason != nil)
        .modifier(DisabledReason(reason: reason))
    }
}

struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text).font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.16)))
    }
}

struct MemoryBar: View {
    let bytes: UInt64
    let fraction: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Format.bytes(bytes))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.panel2)
                    Capsule().fill(color).frame(width: geo.size.width * min(max(fraction, 0.02), 1))
                }
            }
            .frame(height: 5)
        }
    }
}

enum ProcessWindowModel {
    static func single(_ r: ProcessRow) -> ProcessGroup {
        TerminationPlanner.singleRowGroup(r, isRunningApp: NSRunningApplication(processIdentifier: r.id) != nil)
    }
}

private struct DisabledReason: ViewModifier {
    let reason: String?

    func body(content: Content) -> some View {
        if let reason { content.help(reason) } else { content }
    }
}
