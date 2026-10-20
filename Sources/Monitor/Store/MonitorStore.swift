import Foundation
import MonitorCore
import Observation

@MainActor
@Observable
final class MonitorStore {
    var stats: SystemStats?
    var history: [String: RingBuffer<Double>] = [
        "pressure": RingBuffer(capacity: 120), "used": RingBuffer(capacity: 120),
        "cpu": RingBuffer(capacity: 120), "swap": RingBuffer(capacity: 120),
    ]
    var rows: [ProcessRow] = []
    var allSnapshots: [ProcessSnapshot] = []
    var suspects: [Suspect] = []
    var mode: GroupingMode = .byApp
    var search = ""
    var windowVisible = false
    var lastMessage: String?
    var now = Date()
    let ignore = IgnoreList()

    @ObservationIgnored private var systemSampler = SystemSampler()
    @ObservationIgnored private var cpuTracker = CPUTracker()
    @ObservationIgnored private var ports: [Int32: [UInt16]] = [:]
    @ObservationIgnored private var lastPortScan = Date.distantPast
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored var onCycle: (@MainActor (MonitorStore) -> Void)?

    var groups: [ProcessGroup] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = query.isEmpty ? rows : rows.filter { row in
            let id = row.identified
            let fields = [id.title, id.subtitle ?? "", id.project ?? "", row.snapshot.name] + row.ports.map(String.init)
            return fields.contains { $0.lowercased().contains(query) }
        }
        return Grouping.group(filtered, mode: mode)
    }

    var suspectBytes: UInt64 { suspects.reduce(0) { $0 + $1.row.snapshot.footprintBytes } }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.refresh()
                try? await Task.sleep(for: .seconds(self.windowVisible ? 3 : 10))
            }
        }
    }

    func refresh() async {
        let scanPorts = Date().timeIntervalSince(lastPortScan) >= 15
        let (snaps, newPorts) = await Task.detached(priority: .utility) { () -> ([ProcessSnapshot], [Int32: [UInt16]]?) in
            (ProcessSampler().sample(), scanPorts ? PortScanner.scan() : nil)
        }.value
        if let newPorts { ports = newPorts; lastPortScan = Date() }
        let at = Date()
        now = at
        let s = systemSampler.sample()
        stats = s
        history["pressure"]?.append(Double(s.pressurePercent))
        history["used"]?.append(Double(s.usedBytes))
        history["cpu"]?.append(s.cpuPercent)
        history["swap"]?.append(Double(s.swapUsedBytes))
        let cpu = cpuTracker.update(snaps, at: at)
        let live = snaps.filter { $0.state != .zombie && $0.id != getpid() }
        allSnapshots = snaps
        rows = live.map { snap in
            let p = ports[snap.id] ?? []
            return ProcessRow(snapshot: snap, identified: Classifier.classify(snap, ports: p), cpuPercent: cpu[snap.id] ?? 0, ports: p)
        }
        suspects = ForgottenDetector.detect(rows, allPids: Set(snaps.map(\.id)), now: at, ignore: ignore)
        onCycle?(self)
    }

    func plan(for group: ProcessGroup, mode: TerminationMode) -> TerminationPlan {
        TerminationPlanner.plan(group, all: allSnapshots, mode: mode, myUid: getuid())
    }

    func close(_ group: ProcessGroup, mode: TerminationMode) async -> String? {
        let message: String?
        switch plan(for: group, mode: mode) {
        case .notAllowed(let reason):
            message = reason
        case .quitApp(let bundlePath, let force):
            message = AppTerminator.quit(bundlePath: bundlePath, force: force)
        case .signals(let steps):
            let failures = await Task.detached { TerminationExecutor.run(steps, signaler: SystemSignaler()) }.value
            let real = failures.values.filter { $0 != "O processo já tinha terminado." }
            message = real.first
        }
        lastMessage = message
        try? await Task.sleep(for: .milliseconds(400))
        await refresh()
        return message
    }

    func closeSuspects(_ ids: Set<Int32>) async {
        for suspect in suspects where ids.contains(suspect.id) {
            let group = ProcessGroup(id: "suspect:\(suspect.id)", title: suspect.row.identified.title, subtitle: nil, kind: suspect.row.identified.kind, rows: [suspect.row])
            _ = await close(group, mode: .normal)
        }
    }
}
