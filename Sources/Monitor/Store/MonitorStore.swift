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
    var sockets: [ListeningSocket] = []
    var dockerRunning = false
    var containers: [DockerContainer] = []
    var runaways: [Runaway] = []
    var peaks: [PeakEpisode] = []
    @ObservationIgnored private var runawayTracker = RunawayTracker()
    @ObservationIgnored private var peakRecorder: PeakRecorder
    @ObservationIgnored private let peakStore = PeakStore(url: PeakStore.defaultURL)
    @ObservationIgnored private var lastPrune = Date.distantPast
    @ObservationIgnored private var lastContainerScan = Date.distantPast
    @ObservationIgnored private let docker = DockerClient()
    @ObservationIgnored private var containerScanInFlight = false
    @ObservationIgnored private var ports: [Int32: [UInt16]] = [:]
    @ObservationIgnored private var lastPortScan = Date.distantPast
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var stoppedSince: [String: Date] = [:]
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

    init() {
        peakRecorder = PeakRecorder(episodes: PeakStore(url: PeakStore.defaultURL).load())
        peaks = peakRecorder.episodes
    }

    var portEntries: [PortEntry] {
        let entries = PortTable.build(sockets: sockets, rows: rows, containers: containers)
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return entries }
        return entries.filter { e in
            [String(e.port), e.title, e.project ?? ""].contains { $0.lowercased().contains(query) }
        }
    }

    var highlightedPorts: [UInt16] {
        let entries = PortTable.build(sockets: sockets, rows: rows, containers: containers)
        let priority: (PortEntry) -> Int = { e in
            switch e.owner {
            case .container: 0
            case .process(let row): [.devServer, .database].contains(row.identified.kind) ? 0 : 1
            }
        }
        let sorted = entries.sorted { priority($0) != priority($1) ? priority($0) < priority($1) : $0.port < $1.port }
        var seen: Set<UInt16> = []
        return sorted.compactMap { seen.insert($0.port).inserted ? $0.port : nil }.prefix(6).map { $0 }
    }

    func sessionCost(_ snap: ProcessSnapshot) -> SessionCost {
        SessionCost.compute(session: snap, rows: rows)
    }

    func releasePort(_ port: UInt16) async -> PortRelease {
        lastPortScan = .distantPast
        await refresh()
        return PortTable.release(port: port, entries: PortTable.build(sockets: sockets, rows: rows, containers: containers), all: allSnapshots, myUid: getuid())
    }

    func stopContainer(_ id: String) async -> String? {
        let client = docker
        let message = await Task.detached { client.stop(id) }.value
        lastMessage = message
        lastContainerScan = .distantPast
        lastPortScan = .distantPast
        await refresh()
        return message
    }

    func restart(_ group: ProcessGroup) async -> String? {
        guard let app = group.rows.first?.identified.appBundlePath else { return "Só apps com janela podem ser reiniciados." }
        let message = await AppRestarter.restart(bundlePath: app)
        lastMessage = message
        await refresh()
        return message
    }

    func dockerRunningCount() async -> Int {
        let client = docker
        return await Task.detached { client.runningCount() }.value
    }

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
        let (snaps, newSockets) = await Task.detached(priority: .utility) { () -> ([ProcessSnapshot], [ListeningSocket]?) in
            (ProcessSampler().sample(), scanPorts ? PortScanner.scanSockets() : nil)
        }.value
        if let newSockets {
            sockets = newSockets
            ports = PortScanner.byPid(newSockets)
            lastPortScan = Date()
        }
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
        let context = ClassifyContext(dockerRunning: Classifier.dockerRunning(in: snaps))
        dockerRunning = context.dockerRunning
        rows = live.map { snap in
            let p = ports[snap.id] ?? []
            return ProcessRow(snapshot: snap, identified: Classifier.classify(snap, ports: p, context: context), cpuPercent: cpu[snap.id] ?? 0, ports: p)
        }
        var nextStopped: [String: Date] = [:]
        var stoppedByPid: [Int32: Date] = [:]
        for snap in live where snap.state == .stopped {
            let key = "\(snap.id):\(snap.startTime.timeIntervalSince1970)"
            let since = stoppedSince[key] ?? at
            nextStopped[key] = since
            stoppedByPid[snap.id] = since
        }
        stoppedSince = nextStopped
        suspects = ForgottenDetector.detect(rows, allPids: Set(snaps.map(\.id)), now: at, ignore: ignore, stoppedSince: stoppedByPid)
        runaways = runawayTracker.update(rows, at: at, myUid: getuid(), ignore: ignore)
        if peakRecorder.update(stats: s, groups: Grouping.group(rows, mode: .byApp), at: at) {
            peakStore.save(peakRecorder.episodes)
        }
        if at.timeIntervalSince(lastPrune) >= 3600 {
            peakRecorder.prune(now: at)
            peakStore.save(peakRecorder.episodes)
            lastPrune = at
        }
        peaks = peakRecorder.episodes
        if windowVisible && dockerRunning && !containerScanInFlight && at.timeIntervalSince(lastContainerScan) >= 15 {
            containerScanInFlight = true
            lastContainerScan = at
            let client = docker
            Task { [weak self] in
                let list = await Task.detached(priority: .utility) { client.list() }.value
                guard let self else { return }
                self.containers = self.dockerRunning ? list : []
                self.containerScanInFlight = false
            }
        } else if !dockerRunning {
            containers = []
        }
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
            let real = failures.values.filter { $0 != TerminationPlanner.alreadyGone }
            message = real.first ?? (failures.count == steps.count && !steps.isEmpty ? TerminationPlanner.alreadyGone : nil)
        }
        lastMessage = message
        try? await Task.sleep(for: .milliseconds(400))
        lastPortScan = .distantPast
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
