# Monitor de processos e memória — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** App nativo de barra de menus para macOS que mostra a pressão de memória, traduz cada processo (o que é, projeto, porta, idade), aponta os esquecidos e permite fechá-los manualmente.

**Architecture:** Pacote SwiftPM com dois alvos: `MonitorCore` (lógica pura e coleta de dados do sistema via `sysctl`/`libproc`/`lsof`, toda testável) e `Monitor` (app SwiftUI: `MenuBarExtra` + `Window`, store observável com timer, ações via `NSRunningApplication`/`kill`). Um script empacota o executável num `Monitor.app` com `LSUIElement` e assinatura ad-hoc.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Darwin (`sysctl`, `libproc`), UserNotifications, ServiceManagement, Swift Testing. Sem dependências externas.

**Spec:** `docs/superpowers/specs/2026-10-20-monitor-memoria-design.md` (mockup aprovado: `docs/design/mockup-aprovado.html`). Ler os dois antes de qualquer tarefa.

## Global Constraints

- Mac Apple Silicon, macOS 26.6; `platforms: [.macOS(.v14)]`. Build só com Command Line Tools (sem Xcode): `swift build`, testes via `scripts/test.sh`.
- Sem dependências de terceiros.
- Meta de consumo do próprio app: menos de ~50 MB de RAM e CPU desprezível em repouso.
- O app **nunca** fecha nada sozinho; toda ação de fechar parte de um clique do usuário.
- Toda a interface em português do Brasil. Tema escuro conforme o mockup (cores: fundo `#16171b`, painel `#1e1f24`, linha `#2e3037`, texto `#ececf1`, secundário `#8b8d98`, destaque `#7c8cff`, ok `#3ddc84`, aviso `#ffb340`, crítico `#ff5c5c`).
- Número principal = pressão de memória = `100 - kern.memorystatus_level`; cor = `kern.memorystatus_vm_pressure_level` (1 normal → verde, 2 aviso → âmbar, 4 crítico → vermelho).
- Memória por processo = `ri_phys_footprint` de `proc_pid_rusage` (a mesma métrica da coluna Memória do Monitor de Atividade).
- Sem comentários no código. Commits em inglês, Conventional Commits, sem trailers de coautoria.

## Review Focus

- Processo que termina entre a listagem e a leitura dos detalhes: é pulado sem erro e sem linha fantasma. (teste na Task 3)
- Processo de outro usuário (root, `_mysql`): aparece com o que for legível; ✕ desabilitado com motivo; nada trava. (testes nas Tasks 3 e 8)
- PID reutilizado: fechar só se o PID ainda tiver a mesma hora de início do instantâneo clicado; senão, avisar "o processo já terminou". (teste na Task 8)
- Processo suspenso (estado `SSTOP`): fechar envia `SIGCONT` antes do `SIGTERM`, como descoberto em 20/10. (teste na Task 8)
- Repetição de avisos: o mesmo esquecido gera uma notificação só, até sumir; pressão só notifica ao subir de nível, com intervalo mínimo de 10 min. (teste na Task 11)

---

## File Structure

```
Package.swift
scripts/test.sh                      roda swift test com o caminho do Testing.framework das CLT
scripts/bundle.sh                    build release + monta Monitor.app + assina ad-hoc + copia para ~/Applications
Resources/Info.plist                 LSUIElement, bundle id dev.victor.monitor
Sources/MonitorCore/
  Model/ProcessSnapshot.swift        ProcessSnapshot, ProcessState
  Model/SystemStats.swift            SystemStats, PressureLevel
  Sampling/SystemSampler.swift       leitura de pressão, memória, swap, CPU total
  Sampling/ProcessSampler.swift      libproc → [ProcessSnapshot]
  Sampling/CPUTracker.swift          % de CPU por delta de tempo
  Sampling/PortScanner.swift         lsof → [pid: [UInt16]]
  Classify/Classifier.swift          ProcessKind, Identified, classify()
  Classify/Grouping.swift            ProcessGroup, GroupingMode, group()
  Classify/ForgottenDetector.swift   Suspect, detect()
  Prefs/IgnoreList.swift             IgnoreKey, IgnoreList (UserDefaults)
  Actions/TerminationPlanner.swift   TerminationPlan, plan(), Signaler
  History/RingBuffer.swift           RingBuffer<T>
Sources/Monitor/
  MonitorApp.swift                   @main: MenuBarExtra + Window("Monitor")
  Store/MonitorStore.swift           @Observable, timer, junta tudo
  UI/Theme.swift                     cores e estilos do mockup
  UI/MenuBarLabel.swift              bolinha + %
  UI/PopoverView.swift               resumo do popover
  UI/MainWindow.swift                layout da janela
  UI/MetricCards.swift, UI/Sparkline.swift
  UI/ForgottenBanner.swift
  UI/ProcessListView.swift
  UI/DetailPanel.swift
  UI/AppIcon.swift                   ícone real do app ou letra colorida
  Services/AppTerminator.swift       quit normal / forçar via NSRunningApplication
  Services/Notifier.swift            UserNotifications + regras anti-repetição
  Services/LaunchAtLogin.swift       SMAppService
Tests/MonitorCoreTests/              um arquivo por arquivo do Core
```

---

### Task 1: Pacote, scripts e RingBuffer

**Files:**
- Create: `Package.swift`, `scripts/test.sh`, `Sources/MonitorCore/History/RingBuffer.swift`, `Sources/Monitor/MonitorApp.swift` (placeholder mínimo: `MenuBarExtra("Monitor", systemImage: "memorychip") { Text("Monitor") }`), `Tests/MonitorCoreTests/RingBufferTests.swift`

**Interfaces:**
- Produces: `public struct RingBuffer<T>: Sendable where T: Sendable { public init(capacity: Int); public mutating func append(_ x: T); public var elements: [T] }` (ordem do mais antigo ao mais novo).
- Produces: `scripts/test.sh` — `swift test` com `-Xswiftc -F -Xswiftc $F -Xlinker -F -Xlinker $F -Xlinker -rpath -Xlinker $F`, `F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks`, repassando `"$@"`.

- [ ] **Step 1:** `Package.swift` com tools-version 6.0, alvos `MonitorCore` (library), `Monitor` (executable, depende de `MonitorCore`), `MonitorCoreTests`.
- [ ] **Step 2: Write the failing test**

```swift
@Test func keepsOnlyLastNInOrder() {
    var b = RingBuffer<Int>(capacity: 3)
    for i in 1...5 { b.append(i) }
    #expect(b.elements == [3, 4, 5])
}
@Test func emptyAndPartial() {
    var b = RingBuffer<Int>(capacity: 3)
    #expect(b.elements.isEmpty)
    b.append(7)
    #expect(b.elements == [7])
}
```

- [ ] **Step 3:** `scripts/test.sh` → FAIL (RingBuffer não existe).
- [ ] **Step 4:** Implementar `RingBuffer`.
- [ ] **Step 5:** `scripts/test.sh` → PASS; `swift build` → "Build complete".
- [ ] **Step 6:** Commit `chore: scaffold swift package with ring buffer`.

### Task 2: SystemSampler

**Files:**
- Create: `Sources/MonitorCore/Model/SystemStats.swift`, `Sources/MonitorCore/Sampling/SystemSampler.swift`, `Tests/MonitorCoreTests/SystemSamplerTests.swift`

**Interfaces:**
- Produces: `public enum PressureLevel: Int, Sendable { case normal = 1, warning = 2, critical = 4 }`; `init(kernelValue: Int32)` mapeando valores desconhecidos para `.normal`.
- Produces: `public struct SystemStats: Sendable, Equatable { pressurePercent: Int; level: PressureLevel; usedBytes: UInt64; totalBytes: UInt64; swapUsedBytes: UInt64; cpuPercent: Double }`.
- Produces: `public struct SystemSampler { public init(); public mutating func sample() -> SystemStats }` (mutating porque guarda os ticks de CPU anteriores; primeira amostra tem `cpuPercent == 0`).
- Produces: `public static func pressurePercent(freePercent: Int32) -> Int` = `max(0, min(100, 100 - freePercent))`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func pressureFromFree() {
    #expect(SystemSampler.pressurePercent(freePercent: 28) == 72)
    #expect(SystemSampler.pressurePercent(freePercent: 120) == 0)
    #expect(SystemSampler.pressurePercent(freePercent: -5) == 100)
}
@Test func levelMapping() {
    #expect(PressureLevel(kernelValue: 1) == .normal)
    #expect(PressureLevel(kernelValue: 2) == .warning)
    #expect(PressureLevel(kernelValue: 4) == .critical)
    #expect(PressureLevel(kernelValue: 9) == .normal)
}
@Test func liveSampleIsSane() {
    var s = SystemSampler()
    let a = s.sample()
    #expect(a.totalBytes == ProcessInfo.processInfo.physicalMemory)
    #expect(a.usedBytes > 0 && a.usedBytes <= a.totalBytes)
    #expect((0...100).contains(a.pressurePercent))
}
```

- [ ] **Step 2:** `scripts/test.sh` → FAIL.
- [ ] **Step 3:** Implementar. Memória usada = (active + wired + compressor) páginas de `host_statistics64(HOST_VM_INFO64)` × page size (base do "Memória Usada" do Monitor de Atividade); swap via `sysctl vm.swapusage`; CPU total via delta de `host_processor_info`/`host_statistics(HOST_CPU_LOAD_INFO)`.
- [ ] **Step 4:** `scripts/test.sh` → PASS.
- [ ] **Step 5:** Commit `feat(core): sample system memory pressure, swap and cpu`.

### Task 3: ProcessSampler e CPUTracker

**Files:**
- Create: `Sources/MonitorCore/Model/ProcessSnapshot.swift`, `Sources/MonitorCore/Sampling/ProcessSampler.swift`, `Sources/MonitorCore/Sampling/CPUTracker.swift`, `Tests/MonitorCoreTests/ProcessSamplerTests.swift`, `Tests/MonitorCoreTests/CPUTrackerTests.swift`, `Tests/MonitorCoreTests/Fixtures.swift`

**Interfaces:**
- Produces: `public enum ProcessState: Sendable { case running, stopped, zombie, other }` (de `pbi_status`: `SSTOP`=4 → stopped, `SZOMB`=5 → zombie).
- Produces: `public struct ProcessSnapshot: Sendable, Identifiable, Equatable { id: Int32 (pid); ppid: Int32; uid: UInt32; name: String; executablePath: String?; arguments: [String]; cwd: String?; startTime: Date; state: ProcessState; footprintBytes: UInt64; cpuTimeNs: UInt64; ttyName: String? }`.
- Produces: `public struct ProcessSampler { public init(); public func sample() -> [ProcessSnapshot] }` — `proc_listallpids`, `proc_pidinfo(PROC_PIDTBSDINFO)`, `proc_pidpath`, `KERN_PROCARGS2`, `PROC_PIDVNODEPATHINFO` (cwd), `proc_pid_rusage(RUSAGE_INFO_V4)`. Campo ilegível vira `nil`/vazio; PID que some no meio é omitido.
- Produces: `public struct CPUTracker { public init(); public mutating func update(_ snaps: [ProcessSnapshot], at: Date) -> [Int32: Double] }` — % = Δ`cpuTimeNs` / Δtempo / 1e9 × 100, por PID com mesma `startTime`; PID novo ou reutilizado → 0.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func seesItselfWithDetails() {
    let me = ProcessSampler().sample().first { $0.id == getpid() }
    #expect(me != nil)
    #expect(me!.cwd == FileManager.default.currentDirectoryPath)
    #expect(!me!.arguments.isEmpty)
    #expect(me!.footprintBytes > 0)
    #expect(me!.startTime < Date())
}
@Test func otherUserProcessIsPartialNotFatal() {
    let launchd = ProcessSampler().sample().first { $0.id == 1 }
    #expect(launchd?.uid == 0)
}
@Test func vanishedProcessIsSkipped() {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/true"); try! p.run(); p.waitUntilExit()
    #expect(!ProcessSampler().sample().contains { $0.id == p.processIdentifier && $0.state != .zombie })
}
@Test func cpuPercentFromDeltas() {
    var t = CPUTracker()
    let t0 = Date(timeIntervalSince1970: 1000)
    let a = ProcessSnapshot.fixture(pid: 10, cpuTimeNs: 1_000_000_000, start: t0)
    let b = ProcessSnapshot.fixture(pid: 10, cpuTimeNs: 1_500_000_000, start: t0)
    #expect(t.update([a], at: Date(timeIntervalSince1970: 2000))[10] == 0)
    #expect(t.update([b], at: Date(timeIntervalSince1970: 2001))[10] == 50)
}
@Test func reusedPidResetsCpu() {
    var t = CPUTracker()
    _ = t.update([.fixture(pid: 10, cpuTimeNs: 9_000_000_000, start: Date(timeIntervalSince1970: 1))], at: Date(timeIntervalSince1970: 100))
    #expect(t.update([.fixture(pid: 10, cpuTimeNs: 100, start: Date(timeIntervalSince1970: 99))], at: Date(timeIntervalSince1970: 101))[10] == 0)
}
```

`ProcessSnapshot.fixture(pid:cpuTimeNs:start:name:arguments:cwd:ppid:uid:state:executablePath:)` com valores padrão, definido no alvo de teste (extensão em `Tests/MonitorCoreTests/Fixtures.swift`), reutilizado nas tarefas seguintes.

- [ ] **Step 2:** `scripts/test.sh` → FAIL.
- [ ] **Step 3:** Implementar sampler e tracker.
- [ ] **Step 4:** `scripts/test.sh` → PASS.
- [ ] **Step 5:** Commit `feat(core): sample processes with libproc and track cpu`.

### Task 4: PortScanner

**Files:**
- Create: `Sources/MonitorCore/Sampling/PortScanner.swift`, `Tests/MonitorCoreTests/PortScannerTests.swift`

**Interfaces:**
- Produces: `public enum PortScanner { public static func parse(lsofOutput: String) -> [Int32: [UInt16]]; public static func scan() -> [Int32: [UInt16]] }` — `scan` roda `/usr/sbin/lsof -nP -iTCP -sTCP:LISTEN -Fpn` (timeout 3 s; falha → `[:]`). Portas únicas e ordenadas por PID.

- [ ] **Step 1: Write the failing test**

```swift
@Test func parsesLsofFieldOutput() {
    let out = "p71066\nf23\nn*:3000\nf24\nn[::1]:3000\np27322\nf30\nn127.0.0.1:5199\n"
    #expect(PortScanner.parse(lsofOutput: out) == [71066: [3000], 27322: [5199]])
}
@Test func garbageYieldsEmpty() { #expect(PortScanner.parse(lsofOutput: "xyz\n").isEmpty) }
```

- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS.
- [ ] **Step 5:** Commit `feat(core): map listening tcp ports to pids`.

### Task 5: Classifier

**Files:**
- Create: `Sources/MonitorCore/Classify/Classifier.swift`, `Tests/MonitorCoreTests/ClassifierTests.swift`

**Interfaces:**
- Consumes: `ProcessSnapshot`.
- Produces: `public enum ProcessKind: String, Sendable { case devServer, claudeSession, mcpServer, appProcess, shell, database, system, other }`.
- Produces: `public struct Identified: Sendable, Equatable { kind: ProcessKind; title: String; subtitle: String?; project: String?; appBundlePath: String? }`.
- Produces: `public enum Classifier { public static func classify(_ p: ProcessSnapshot, ports: [UInt16]) -> Identified }`.
- Regras (ordem): `.app/` no caminho → `appProcess`, `appBundlePath` = o `.app` mais externo, título = nome do bundle sem `.app`; `claude` (nome ou argv[0]) → `claudeSession`, título "Claude Code", subtítulo com "suspensa" se `state == .stopped`; argumentos contendo `mcp` (`playwright-mcp`, `… mcp`) → `mcpServer`; `next-server`, `vite`, `webpack`, `nest start`, `tsx watch`, `nodemon`, java com `spring`/`maven`/`plexus-classworlds`, `rails`, `uvicorn`, `manage.py runserver` → `devServer` com título do framework ("Next.js dev", "Vite dev", "Spring Boot dev"…) e portas no subtítulo; `mysqld`, `postgres`, `redis-server`, `mongod` → `database`; `zsh`/`bash`/`fish` → `shell`; uid 0 sem regra → `system`; resto → `other` com título = nome.
- `project` = último componente da pasta raiz encontrada subindo de `cwd` até achar `package.json`, `pom.xml`, `Cargo.toml` ou `.git` (sem passar de `~`); sem `cwd` → `nil`.

- [ ] **Step 1: Write the failing tests** — tabela com os casos reais de 20/10:

```swift
@Test(arguments: [
    ("next-server (v16.2.4)", ["next-server"], "/Users/v/m4all/contratos/eleva-contracts-ui", ProcessKind.devServer, "Next.js dev"),
    ("node", ["node", "/x/node_modules/.bin/vite", "dev", "--port", "5199"], "/Users/v/wra/systemwra", .devServer, "Vite dev"),
    ("java", ["/opt/java", "-cp", "/Users/v/m4all/eleva-contracts-api/target/classes", "org.springframework.boot.loader"], "/Users/v/m4all/eleva-contracts-api", .devServer, "Spring Boot dev"),
    ("claude", ["claude", "--dangerously-skip-permissions"], "/Users/v/immobile", .claudeSession, "Claude Code"),
    ("node", ["node", "/Users/v/.npm/_npx/x/node_modules/.bin/playwright-mcp"], "/Users/v/immobile", .mcpServer, "Playwright MCP"),
    ("mysqld", ["/usr/local/mysql/bin/mysqld"], nil, .database, "MySQL"),
    ("zsh", ["-zsh"], "/Users/v", .shell, "Terminal (zsh)"),
] as [(String, [String], String?, ProcessKind, String)])
func classifiesKnownCases(name: String, args: [String], cwd: String?, kind: ProcessKind, title: String) {
    let id = Classifier.classify(.fixture(name: name, arguments: args, cwd: cwd), ports: [])
    #expect(id.kind == kind)
    #expect(id.title == title)
}
@Test func helperGroupsUnderOuterApp() {
    let p = ProcessSnapshot.fixture(name: "Microsoft Teams WebView Helper (Renderer)",
        executablePath: "/Applications/Microsoft Teams.app/Contents/Helpers/Microsoft Teams WebView.app/Contents/Frameworks/x/Helpers/MSTeams WebView Helper (Renderer).app/Contents/MacOS/h")
    let id = Classifier.classify(p, ports: [])
    #expect(id.kind == .appProcess)
    #expect(id.appBundlePath == "/Applications/Microsoft Teams.app")
    #expect(id.title == "Microsoft Teams")
}
@Test func stoppedClaudeIsFlagged() {
    let id = Classifier.classify(.fixture(name: "claude", arguments: ["claude"], state: .stopped), ports: [])
    #expect(id.subtitle?.contains("suspensa") == true)
}
@Test func devServerShowsPorts() {
    let id = Classifier.classify(.fixture(name: "next-server (v16.2.4)", arguments: ["next-server"]), ports: [3000])
    #expect(id.subtitle?.contains(":3000") == true)
}
@Test func unknownKeepsName() {
    #expect(Classifier.classify(.fixture(name: "weird", arguments: ["weird"]), ports: []).title == "weird")
}
```

Para o teste de `project`, criar uma pasta temporária com `package.json` e uma subpasta como `cwd`; esperar o nome da raiz.

- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS.
- [ ] **Step 5:** Commit `feat(core): classify processes into readable kinds`.

### Task 6: Grouping

**Files:**
- Create: `Sources/MonitorCore/Classify/Grouping.swift`, `Tests/MonitorCoreTests/GroupingTests.swift`

**Interfaces:**
- Consumes: `ProcessSnapshot`, `Identified`.
- Produces: `public struct ProcessRow: Sendable, Identifiable { id: Int32; snapshot: ProcessSnapshot; identified: Identified; cpuPercent: Double; ports: [UInt16] }`.
- Produces: `public enum GroupingMode: Sendable { case byApp, byProject, flat }`.
- Produces: `public struct ProcessGroup: Sendable, Identifiable { id: String; title: String; subtitle: String?; kind: ProcessKind; rows: [ProcessRow]; footprintBytes: UInt64; cpuPercent: Double; oldestStart: Date }`.
- Produces: `public enum Grouping { public static func group(_ rows: [ProcessRow], mode: GroupingMode) -> [ProcessGroup] }` — `byApp`: chave = `appBundlePath` se houver, senão `kind`+`project` para devServer/claude/mcp (ex.: "Claude Code" junta todas as sessões, subtítulo "N sessões"), senão PID; `byProject`: chave = `project` (sem projeto → por app); `flat`: um grupo por linha. Ordenado por `footprintBytes` decrescente.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func teamsHelpersBecomeOneGroup() {
    let rows = (1...9).map { ProcessRow.fixture(pid: Int32($0), app: "/Applications/Microsoft Teams.app", bytes: 100) }
    let g = Grouping.group(rows, mode: .byApp)
    #expect(g.count == 1)
    #expect(g[0].rows.count == 9)
    #expect(g[0].footprintBytes == 900)
}
@Test func claudeSessionsGroupTogether() {
    let rows = [ProcessRow.fixture(pid: 1, kind: .claudeSession, project: "immobile"), .fixture(pid: 2, kind: .claudeSession, project: "m4all")]
    #expect(Grouping.group(rows, mode: .byApp).count == 1)
    #expect(Grouping.group(rows, mode: .byProject).count == 2)
}
@Test func sortedByMemoryDesc() {
    let rows = [ProcessRow.fixture(pid: 1, bytes: 10), .fixture(pid: 2, bytes: 30)]
    #expect(Grouping.group(rows, mode: .flat).map(\.footprintBytes) == [30, 10])
}
```

- [ ] **Step 2:** FAIL. **Step 3:** Implementar (fixture `ProcessRow.fixture` em `Fixtures.swift`). **Step 4:** PASS.
- [ ] **Step 5:** Commit `feat(core): group process rows by app, project or flat`.

### Task 7: ForgottenDetector e IgnoreList

**Files:**
- Create: `Sources/MonitorCore/Classify/ForgottenDetector.swift`, `Sources/MonitorCore/Prefs/IgnoreList.swift`, `Tests/MonitorCoreTests/ForgottenDetectorTests.swift`, `Tests/MonitorCoreTests/IgnoreListTests.swift`

**Interfaces:**
- Produces: `public struct IgnoreKey: Hashable, Codable, Sendable { raw: String; public static func of(_ row: ProcessRow) -> IgnoreKey }` — app: `"app:" + appBundlePath`; devServer/claude/mcp: `"\(kind):" + (project ?? executablePath ?? name)`; resto: `"exe:" + (executablePath ?? name)`.
- Produces: `public final class IgnoreList: @unchecked Sendable { public init(defaults: UserDefaults = .standard); public func contains(_ k: IgnoreKey) -> Bool; public func add(_ k: IgnoreKey, label: String); public func remove(_ k: IgnoreKey); public var all: [(key: IgnoreKey, label: String)] }` — persistido em JSON na chave `ignoreList`.
- Produces: `public enum SuspectReason: Sendable, Equatable { case idleDevServer(hours: Int), suspendedSession(days: Int), orphanMcp }`; `public struct Suspect: Sendable, Identifiable { id: Int32; row: ProcessRow; reason: SuspectReason; public var hint: String }` com textos: idle → "Aberto há N dias e quase sem uso de CPU. Provavelmente esquecido."; suspended → "Sessão suspensa (Ctrl+Z) há N dias."; orphan → "Servidor MCP sem a sessão que o abriu.".
- Produces: `public enum ForgottenDetector { public static func detect(_ rows: [ProcessRow], allPids: Set<Int32>, now: Date, ignore: IgnoreList) -> [Suspect] }`.
- Regras: devServer com idade ≥ 24 h e CPU média de vida (`cpuTimeNs / idade`) < 0,5% → idle; claudeSession com `state == .stopped` → suspended; mcpServer cujo `ppid == 1` ou `ppid ∉ allPids` → orphan. Itens na IgnoreList nunca entram. Ordenado por `footprintBytes` decrescente.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func flagsTodaysCases() {
    let now = Date(timeIntervalSince1970: 10 * 86_400)
    let rows = [
        ProcessRow.fixture(pid: 1, kind: .devServer, start: now.addingTimeInterval(-4 * 86_400), cpuTimeNs: 1_000_000_000),
        ProcessRow.fixture(pid: 2, kind: .claudeSession, state: .stopped, start: now.addingTimeInterval(-19 * 86_400)),
        ProcessRow.fixture(pid: 3, kind: .mcpServer, ppid: 1),
        ProcessRow.fixture(pid: 4, kind: .devServer, start: now.addingTimeInterval(-3600)),
    ]
    let s = ForgottenDetector.detect(rows, allPids: [1, 2, 3, 4], now: now, ignore: IgnoreList(defaults: .ephemeral()))
    #expect(Set(s.map(\.id)) == [1, 2, 3])
}
@Test func busyDevServerIsNotForgotten() {
    let now = Date(timeIntervalSince1970: 10 * 86_400)
    let r = ProcessRow.fixture(pid: 1, kind: .devServer, start: now.addingTimeInterval(-2 * 86_400), cpuTimeNs: 172_800 * 1_000_000_000 / 10)
    #expect(ForgottenDetector.detect([r], allPids: [1], now: now, ignore: IgnoreList(defaults: .ephemeral())).isEmpty)
}
@Test func ignoredNeverFlaggedAndPersists() {
    let d = UserDefaults.ephemeral()
    let r = ProcessRow.fixture(pid: 3, kind: .mcpServer, ppid: 1, project: "immobile")
    IgnoreList(defaults: d).add(.of(r), label: "Playwright MCP")
    #expect(ForgottenDetector.detect([r], allPids: [3], now: Date(), ignore: IgnoreList(defaults: d)).isEmpty)
}
@Test func ignoreKeySurvivesRestart() {
    #expect(IgnoreKey.of(.fixture(pid: 10, kind: .devServer, project: "systemwra")) == IgnoreKey.of(.fixture(pid: 99, kind: .devServer, project: "systemwra")))
}
```

`UserDefaults.ephemeral()` = suite com nome UUID, em `Fixtures.swift`.

- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS.
- [ ] **Step 5:** Commit `feat(core): detect forgotten processes with persistent ignore list`.

### Task 8: TerminationPlanner

**Files:**
- Create: `Sources/MonitorCore/Actions/TerminationPlanner.swift`, `Tests/MonitorCoreTests/TerminationPlannerTests.swift`

**Interfaces:**
- Produces: `public enum TerminationMode: Sendable { case normal, force }`.
- Produces: `public struct TerminationStep: Sendable, Equatable { pid: Int32; startTime: Date; signals: [Int32] }`.
- Produces: `public enum TerminationPlan: Sendable, Equatable { case quitApp(bundlePath: String, force: Bool); case signals([TerminationStep]); case notAllowed(reason: String) }`.
- Produces: `public enum TerminationPlanner { public static func plan(_ group: ProcessGroup, all: [ProcessSnapshot], mode: TerminationMode, myUid: UInt32) -> TerminationPlan; public static func needsConfirmation(_ group: ProcessGroup) -> Bool }`.
- Produces: `public protocol Signaler: Sendable { func currentStartTime(of pid: Int32) -> Date?; func send(_ signal: Int32, to pid: Int32) -> Int32 }` (retorna errno ou 0); `public struct SystemSignaler: Signaler`; `public enum TerminationExecutor { public static func run(_ steps: [TerminationStep], signaler: Signaler) -> [Int32: String] }` (PID → mensagem de falha em pt-BR; vazio = sucesso).
- Regras: grupo `appProcess` → `quitApp` (force conforme modo); outros → `signals` para os PIDs do grupo **mais** a cadeia: para devServer, subir pelos pais enquanto o pai for `npm`/`pnpm`/`yarn`/`node`/`sh` (não shell interativo, não `launchd`) e incluir o pai mais alto; incluir todos os descendentes dos PIDs escolhidos (via `ppid` em `all`); ordem: descendentes antes dos pais. Sinais: normal → `[SIGTERM]`, force → `[SIGKILL]`; processo `stopped` recebe `SIGCONT` antes. Qualquer PID com `uid != myUid` → `notAllowed(reason: "Processo de outro usuário (root). Feche pelo Terminal com sudo.")` (ou o nome do usuário). `needsConfirmation` = claudeSession não suspensa, shell, ou plano com mais de 5 PIDs. O executor confere `currentStartTime(of:) == startTime` antes de cada sinal; diferente/nulo → "O processo já tinha terminado." e pula.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func devServerKillsWholeChainChildrenFirst() {
    let all: [ProcessSnapshot] = [
        .fixture(pid: 50, name: "zsh", ppid: 1), .fixture(pid: 60, name: "npm", arguments: ["npm", "run", "dev"], ppid: 50),
        .fixture(pid: 71066, name: "next-server (v16.2.4)", ppid: 60), .fixture(pid: 71070, name: "node", ppid: 71066)]
    let g = ProcessGroup.fixture(kind: .devServer, pids: [71066], in: all)
    guard case .signals(let steps) = TerminationPlanner.plan(g, all: all, mode: .normal, myUid: 501) else { Issue.record(); return }
    #expect(steps.map(\.pid) == [71070, 71066, 60])
    #expect(steps.allSatisfy { $0.signals == [SIGTERM] })
}
@Test func stoppedGetsContFirst() {
    let all: [ProcessSnapshot] = [.fixture(pid: 16567, name: "claude", ppid: 1, state: .stopped)]
    guard case .signals(let steps) = TerminationPlanner.plan(.fixture(kind: .claudeSession, pids: [16567], in: all), all: all, mode: .normal, myUid: 501) else { Issue.record(); return }
    #expect(steps[0].signals == [SIGCONT, SIGTERM])
}
@Test func appUsesNormalQuit() {
    let g = ProcessGroup.fixture(kind: .appProcess, app: "/Applications/Microsoft Teams.app")
    #expect(TerminationPlanner.plan(g, all: [], mode: .normal, myUid: 501) == .quitApp(bundlePath: "/Applications/Microsoft Teams.app", force: false))
}
@Test func otherUserNotAllowed() {
    let all: [ProcessSnapshot] = [.fixture(pid: 96676, name: "mysqld", uid: 74)]
    guard case .notAllowed = TerminationPlanner.plan(.fixture(kind: .database, pids: [96676], in: all), all: all, mode: .normal, myUid: 501) else { Issue.record(); return }
}
@Test func reusedPidIsNotSignaled() {
    final class Fake: Signaler, @unchecked Sendable { var sent: [Int32] = []
        func currentStartTime(of pid: Int32) -> Date? { Date(timeIntervalSince1970: 999) }
        func send(_ s: Int32, to pid: Int32) -> Int32 { sent.append(pid); return 0 } }
    let f = Fake()
    let r = TerminationExecutor.run([.init(pid: 5, startTime: Date(timeIntervalSince1970: 1), signals: [SIGTERM])], signaler: f)
    #expect(f.sent.isEmpty)
    #expect(r[5] == "O processo já tinha terminado.")
}
@Test func activeClaudeNeedsConfirmation() {
    #expect(TerminationPlanner.needsConfirmation(.fixture(kind: .claudeSession, pids: [1], in: [.fixture(pid: 1, name: "claude")])))
}
```

- [ ] **Step 2:** FAIL. **Step 3:** Implementar (fixture `ProcessGroup.fixture` em `Fixtures.swift`). **Step 4:** PASS.
- [ ] **Step 5:** Commit `feat(core): plan safe process termination`.

### Task 9: Store, barra de menus, popover e empacotamento

**Files:**
- Create: `Sources/MonitorCore/Format.swift`, `Tests/MonitorCoreTests/FormatTests.swift`, `Sources/Monitor/Store/MonitorStore.swift`, `Sources/Monitor/UI/Theme.swift`, `Sources/Monitor/UI/MenuBarLabel.swift`, `Sources/Monitor/UI/PopoverView.swift`, `Resources/Info.plist`, `scripts/bundle.sh`
- Modify: `Sources/Monitor/MonitorApp.swift`

**Interfaces:**
- Consumes: tudo do Core.
- Produces: `@MainActor @Observable final class MonitorStore { var stats: SystemStats?; var history: [String: RingBuffer<Double>] (chaves "pressure", "used", "cpu", "swap"; capacidade 120); var rows: [ProcessRow]; var suspects: [Suspect]; var mode: GroupingMode; var search: String; var groups: [ProcessGroup] (computado com busca por título, subtítulo, projeto, porta); var windowVisible: Bool; func start(); func refresh() async; func close(_ g: ProcessGroup, mode: TerminationMode) async -> String?; let ignore: IgnoreList }`.
- Intervalo: 3 s com a janela aberta, 10 s fechada; portas (`lsof`) a cada 15 s; coleta fora da main thread (`Task.detached`).
- `scripts/bundle.sh`: `swift build -c release`, monta `Monitor.app/Contents/{MacOS/Monitor,Info.plist}`, `codesign --force -s - Monitor.app`, copia para `~/Applications/Monitor.app`. `Info.plist`: `CFBundleIdentifier dev.victor.monitor`, `CFBundleName Monitor`, `LSUIElement true`, `LSMinimumSystemVersion 14.0`.

- [ ] **Step 1:** `MonitorApp`: `MenuBarExtra { PopoverView } label: { MenuBarLabel }` com `.menuBarExtraStyle(.window)` + `Window("Monitor", id: "main")` (conteúdo provisório até a Task 10).
- [ ] **Step 2:** `MenuBarLabel`: bolinha na cor do nível + "72%". `PopoverView` conforme o mockup: anel de pressão, "Pressão normal/moderada/crítica" (normal → "normal", warning → "moderada", critical → "crítica"), "X de Y GB · swap Z GB", CPU; bloco "N esquecidos · X GB" com até 4 itens (título · projeto, idade, memória) ou "Nada esquecido" quando vazio; "Maiores consumidores" (top 3 grupos `byApp`); botão "Abrir janela detalhada" (`openWindow(id: "main")`, atalho ⌘D local).
- [ ] **Step 3:** Formatação em `Sources/MonitorCore/Format.swift` (testável): `public enum Format { static func bytes(_ b: UInt64) -> String; static func age(since: Date, now: Date) -> String }`. Testes em `Tests/MonitorCoreTests/FormatTests.swift`: `bytes(2_684_354_560) == "2,5 GB"`, `bytes(640_680_000) == "611 MB"`; `age` de 20 h → "20 h", de 4 dias → "4 dias", de 1 dia → "1 dia", de 5 min → "5 min".
- [ ] **Step 4:** `scripts/bundle.sh` e `open ~/Applications/Monitor.app`.
- [ ] **Step 5: Verificação manual:** o % na barra é igual a `100 - $(sysctl -n kern.memorystatus_level)` (±2); a memória usada bate com o Monitor de Atividade (±10%); o próprio Monitor usa menos de 50 MB na coluna Memória do Monitor de Atividade; o popover mostra "Nada esquecido" ou os esquecidos reais da máquina.
- [ ] **Step 6:** Commit `feat(app): menu bar label, popover and app bundle script`.

### Task 10: Janela detalhada

**Files:**
- Create: `Sources/Monitor/UI/MainWindow.swift`, `Sources/Monitor/UI/MetricCards.swift`, `Sources/Monitor/UI/Sparkline.swift`, `Sources/Monitor/UI/ForgottenBanner.swift`, `Sources/Monitor/UI/ProcessListView.swift`, `Sources/Monitor/UI/DetailPanel.swift`, `Sources/Monitor/UI/AppIcon.swift`, `Sources/Monitor/Services/AppTerminator.swift`
- Modify: `Sources/Monitor/MonitorApp.swift`

**Interfaces:**
- Consumes: `MonitorStore` (Task 9), `TerminationPlanner`, `IgnoreList`.
- Produces: `enum AppTerminator { static func quit(bundlePath: String, force: Bool) -> String? }` — `NSRunningApplication.runningApplications` filtrando `bundleURL.path == bundlePath`; `terminate()` / `forceTerminate()`; retorna mensagem de erro em pt-BR ou `nil`.

- [ ] **Step 1:** Layout do mockup: barra superior com busca ("Buscar processo, projeto, porta…") e seletor "Por app / Por projeto / Lista"; 4 cartões ("Pressão de memória", "Memória usada", "CPU", "Swap") com `Sparkline` do `history`; faixa "N esquecidos · liberaria X GB" com checkbox por item (marcado por padrão, exceto `suspendedSession`) e botão "Fechar N selecionados"; tabela com colunas Nome / Memória (com barra proporcional ao maior grupo) / CPU / Aberto há / ✕, linhas expansíveis mostrando os processos do grupo, etiquetas "esquecido" (âmbar), "suspensa" (vermelho), "ignorado" (azul).
- [ ] **Step 2:** `DetailPanel` do item selecionado (grupo ou processo): ícone, título, descrição (`Identified.subtitle`), dica do `Suspect.hint` quando houver, e os campos Projeto, Pasta (cwd abreviado com `~`), Porta, Iniciado ("16/10 às 17:43 · 4 dias"), Memória, CPU, Pai (nome + tty), PID; botões "Fechar", "Forçar", "Abrir pasta" (`NSWorkspace.shared.open` no cwd; desabilitado sem cwd); checkbox "Sempre ignorar este processo" ligado à `IgnoreList`.
- [ ] **Step 3:** Ações: `store.close` usa `TerminationPlanner.plan`; `.quitApp` → `AppTerminator`; `.signals` → `TerminationExecutor` com `SystemSignaler`; `.notAllowed` → ✕ desabilitado com o motivo no tooltip; `needsConfirmation` → `confirmationDialog` "Fechar <título>?" com o que será encerrado. Erros aparecem num aviso discreto no rodapé da janela. Após fechar, `refresh()` imediato.
- [ ] **Step 4:** `AppIcon`: `NSWorkspace.shared.icon(forFile: appBundlePath)` para apps; letra inicial em quadrado colorido (cor estável por nome) para o resto.
- [ ] **Step 5: Verificação manual:** `scripts/bundle.sh` e abrir a janela.
  - `mkdir -p /tmp/vtest && cd /tmp/vtest && echo '{}' > package.json && npx --yes http-server -p 8799 &` → aparece com projeto "vtest" e porta 8799; buscar "8799" filtra a lista; fechar pelo ✕ → `lsof -iTCP:8799 -sTCP:LISTEN` vazio.
  - `sleep 999 & kill -STOP $!` → aparece com estado suspenso; fechar pelo app → `ps -p <pid>` vazio (prova do SIGCONT antes do SIGTERM).
  - Teams e Arc aparecem cada um como uma linha; o MySQL mostra ✕ desabilitado com o motivo.
- [ ] **Step 6:** Commit `feat(app): detailed window with grouping, details and close actions`.

### Task 11: Notificações, abrir com o Mac e preferências

**Files:**
- Create: `Sources/MonitorCore/Prefs/NotificationPolicy.swift`, `Tests/MonitorCoreTests/NotificationPolicyTests.swift`, `Sources/Monitor/Services/Notifier.swift`, `Sources/Monitor/Services/LaunchAtLogin.swift`, `README.md`
- Modify: `Sources/Monitor/Store/MonitorStore.swift`, `Sources/Monitor/UI/MainWindow.swift`

**Interfaces:**
- Produces (Core, testável): `public struct NotificationPolicy: Sendable { public init(); public mutating func evaluate(level: PressureLevel, suspects: [Suspect], now: Date) -> [AlertKind] }`; `public enum AlertKind: Equatable, Sendable { case pressureRose(PressureLevel); case newSuspect(IgnoreKey, title: String) }`. Regras: pressão notifica só quando o nível sobe acima do último notificado e passaram ≥ 10 min do último aviso de pressão; volta a normal zera o nível notificado. Suspeito notifica uma vez por `IgnoreKey` enquanto continuar presente; se sumir e voltar, notifica de novo.
- Produces: `enum Notifier { static func requestAuthorization(); static func post(_ a: AlertKind) }` — títulos: "Pressão de memória moderada" / "Pressão de memória crítica"; "Processo esquecido: <título>".
- Produces: `enum LaunchAtLogin { static var isEnabled: Bool; static func set(_ on: Bool) }` via `SMAppService.mainApp`; ligado na primeira execução (flag `didSetupLaunchAtLogin` no UserDefaults).

- [ ] **Step 1: Write the failing tests**

```swift
@Test func pressureNotifiesOnRiseWithCooldown() {
    var p = NotificationPolicy(); let t = Date(timeIntervalSince1970: 0)
    #expect(p.evaluate(level: .warning, suspects: [], now: t) == [.pressureRose(.warning)])
    #expect(p.evaluate(level: .warning, suspects: [], now: t.addingTimeInterval(60)).isEmpty)
    #expect(p.evaluate(level: .critical, suspects: [], now: t.addingTimeInterval(120)).isEmpty)
    #expect(p.evaluate(level: .critical, suspects: [], now: t.addingTimeInterval(601)) == [.pressureRose(.critical)])
}
@Test func suspectNotifiesOnceUntilGone() {
    var p = NotificationPolicy(); let s = Suspect.fixture(pid: 1, kind: .mcpServer, project: "immobile")
    #expect(p.evaluate(level: .normal, suspects: [s], now: .now).count == 1)
    #expect(p.evaluate(level: .normal, suspects: [s], now: .now).isEmpty)
    _ = p.evaluate(level: .normal, suspects: [], now: .now)
    #expect(p.evaluate(level: .normal, suspects: [s], now: .now).count == 1)
}
```

- [ ] **Step 2:** FAIL (acrescentar `Suspect.fixture(pid:kind:project:)` em `Fixtures.swift`). **Step 3:** Implementar política, `Notifier`, `LaunchAtLogin`; store chama `evaluate` a cada ciclo e `Notifier.post` para cada alerta.
- [ ] **Step 4:** Preferências na janela (botão de engrenagem na barra superior, popover): "Abrir ao iniciar o Mac" (toggle), "Notificações" (toggle, padrão ligado), lista "Ignorados" com botão remover.
- [ ] **Step 5:** `scripts/test.sh` → todos PASS; `scripts/bundle.sh`. Verificação manual: na primeira abertura o macOS pede permissão de notificação; o app aparece em Ajustes → Geral → Itens de Início; marcar "Sempre ignorar" num item faz ele sumir da faixa de esquecidos e aparecer na lista "Ignorados", e remover de lá o traz de volta.
- [ ] **Step 6:** `README.md` curto: o que é, `scripts/test.sh`, `scripts/bundle.sh`, onde fica instalado.
- [ ] **Step 7:** Commit `feat(app): notifications, launch at login and preferences`.
