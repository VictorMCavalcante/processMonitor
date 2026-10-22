# Vernio — Bateria e energia — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Aba "Bateria" que mostra quem gasta energia e por quê, quem impede o Mac de dormir, sessões na bateria comparadas, despertares no sono e sugestões aprovadas pelo usuário.

**Architecture:**
- **Coleta:** a energia por processo vem de `rusage_info_v6`, com uma média móvel de 10 min feita por um `EnergyTracker` no molde do `CPUTracker`. Bateria e potência total vêm do IOKit (`AppleSmartBattery`), os bloqueios de sono de `IOPMCopyAssertionsByProcess`, e o histórico de sono e despertares do `pmset -g log` (só sob demanda).
- **Regras:** tudo puro e testável em `Sources/MonitorCore/Energy/`: previsão, sessões, motivo principal, sugestões. A interface fica numa nova `BatteryView`.

**Tech Stack:** Swift 6.2, SwiftUI, IOKit (`IOKit.ps`, `IOKit.pwr_mgt`), Swift Testing (`scripts/test.sh`). Sem dependências novas.

**Spec:** `docs/superpowers/specs/2026-10-22-vernio-bateria-design.md` (ler inteiro antes da Task 1).

## Global Constraints

- macOS 14+, sem Xcode e sem dependências.
- pt-BR, tema `Theme`, **zero comentários no código**.
- Commits em inglês **sem coautoria nem linhas de atribuição**.
- Nunca fazer nada sozinho; nunca rodar `sudo`/`pmset` para alterar configurações. Só copiar o comando para o usuário.
- O nome visível é **Vernio**. Os identificadores do código continuam `Monitor`/`MonitorCore`.
- A energia do ciclo vem da mesma chamada `proc_pid_rusage`, só passando para V6; nada de subprocesso no ciclo.
- `pmset -g log` só roda ao abrir a aba Bateria, no máximo a cada **10 min**, com timeout de 10 s.
- Média "agora" = janela de **10 min** (600 s).
- Previsão só depois de **≥ 3 min** na bateria **e** queda **≥ 1%**; antes disso, "calculando…".
- Sessões em `~/Library/Application Support/Monitor/battery-sessions.json`, no máximo **60**; a sessão aberta é gravada a cada **5 min**.
- Motivo principal, nesta ordem de regras e com estas constantes:
  - CPU > **50%** de um núcleo;
  - GPU > **20%**;
  - despertares > **100/s**;
  - bloqueio de sono;
  - senão "uso leve".
- Sugestões: no máximo **4**:
  - bloqueio de sono parado > **30 min** sem atividade do usuário;
  - servidor de dev ou banco ligado > **8 h** na bateria.
- Alerta de energia: processo com média > **2 W** por **10 min** estando na bateria, usando a política anti-repetição e "sempre ignorar" existentes.
- Toda estimativa aparece com "~" ou "estimado".
- PID reutilizado (outra hora de início) zera o histórico de energia.

## Review Focus

- **Mac sem bateria** (sem `AppleSmartBattery`): a aba mostra só energia, potência e bloqueios, sem quebrar e sem card de bateria. (teste na Task 2: `read()` dá `nil` sem o serviço; `parse([:])` dá `nil`)
- **Ligou na tomada no meio de uma sessão, e desligou e ligou de novo várias vezes:**
  - fecha a sessão anterior e abre uma nova;
  - a previsão some na tomada.
  
  (teste na Task 5)
- **Contador de energia que diminui** (processo reiniciado com o mesmo PID, ou estouro): dá 0, nunca negativo. (teste na Task 1)
- **`pmset -g log` vazio, sem permissão, travado ou com linhas desconhecidas:** resumo vazio, sem travar a aba. (teste na Task 4)
- **Arquivo de sessões corrompido ou de outra versão:** começa vazio e regrava. (teste na Task 5)

---

## File Structure

```
Sources/MonitorCore/Model/ProcessSnapshot.swift      MODIFY: energyNj, wakeups
Sources/MonitorCore/Sampling/ProcessSampler.swift    MODIFY: rusage V6
Sources/MonitorCore/Energy/EnergyTracker.swift       NEW: médias de mW e despertares/s por PID
Sources/MonitorCore/Classify/Grouping.swift          MODIFY: milliwatts/wakeups em ProcessRow/ProcessGroup, GroupSort.energy
Sources/MonitorCore/Energy/BatterySampler.swift      NEW: BatteryReading, leitura IOKit, parse puro, BatteryForecast
Sources/MonitorCore/Energy/SleepBlockers.swift       NEW: bloqueios de sono por PID, nomes legíveis
Sources/MonitorCore/Energy/PowerLog.swift            NEW: parser do pmset -g log (sessões, despertares, térmico, queda dormindo)
Sources/MonitorCore/Energy/BatterySessions.swift     NEW: BatterySession, SessionRecorder, BatterySessionStore, comparação
Sources/MonitorCore/Energy/EnergyAdvisor.swift       NEW: motivo principal, sugestões
Sources/MonitorCore/Runaway/RunawayTracker.swift     MODIFY: RunawayReason.energy
Sources/Monitor/Store/MonitorStore.swift             MODIFY: coleta, sessões, power log sob demanda
Sources/Monitor/UI/BatteryView.swift                 NEW: aba Bateria
Sources/Monitor/UI/MainWindow.swift, PopoverView.swift  MODIFY: aba e linha no popover
Tests/MonitorCoreTests/Energy*Tests.swift            testes por arquivo do Core
```

---

### Task 1: Energia por processo

**Files:** Modify `ProcessSnapshot.swift`, `ProcessSampler.swift`, `Grouping.swift`; Create `Sources/MonitorCore/Energy/EnergyTracker.swift`; Test `Tests/MonitorCoreTests/EnergyTrackerTests.swift`

**Interfaces:**
- **`ProcessSnapshot`:** ganha `public var energyNj: UInt64` e `public var wakeups: UInt64`, este último a soma de `ri_interrupt_wkups` e `ri_pkg_idle_wkups`. O init ganha `energyNj: UInt64 = 0, wakeups: UInt64 = 0` ao final. O `ProcessSampler` passa a usar `rusage_info_v6` / `RUSAGE_INFO_V6`, sem mudar os outros campos.
- Produces: `public struct EnergyRate: Sendable, Equatable { public var milliwatts: Double; public var wakeupsPerSecond: Double }`, com um init público.
- Produces: `public struct EnergyTracker: Sendable { public init(window: TimeInterval = 600); public mutating func update(_ snaps: [ProcessSnapshot], at now: Date) -> [Int32: EnergyRate] }`.
  - **`milliwatts`:** (energia agora − a amostra mais antiga dentro da janela) / tempo / 1e6. As amostras mais velhas que a janela são descartadas, mas a mais recente fora dela fica guardada como base.
  - **`wakeupsPerSecond`:** usa só o último intervalo.
  - **Casos que dão 0:** a primeira amostra, uma hora de início diferente e qualquer contador que diminuiu.
  - Os PIDs que sumiram são esquecidos.
- **`ProcessRow`:** ganha `public var milliwatts: Double` e `public var wakeupsPerSecond: Double`, com `= 0` no init.
- **`ProcessGroup`:** ganha `milliwatts` e `wakeupsPerSecond`, somas das linhas.
- **`GroupSort`:** ganha o case `.energy`.

- [ ] **Step 1: Failing tests**

```swift
@Test func energyRateUsesTenMinuteWindowAndResetsSafely() {
    var t = EnergyTracker(window: 600)
    let s = Date(timeIntervalSince1970: 0), t0 = Date(timeIntervalSince1970: 1000)
    func snap(_ nj: UInt64, _ w: UInt64, start: Date = s) -> ProcessSnapshot { var p = ProcessSnapshot.fixture(pid: 1, start: start); p.energyNj = nj; p.wakeups = w; return p }
    #expect(t.update([snap(0, 0)], at: t0)[1] == EnergyRate(milliwatts: 0, wakeupsPerSecond: 0))
    #expect(t.update([snap(10_000_000_000, 500)], at: t0.addingTimeInterval(10))[1] == EnergyRate(milliwatts: 1000, wakeupsPerSecond: 50))
    let r = t.update([snap(10_000_000_000 + 600_000_000_000, 500)], at: t0.addingTimeInterval(610))[1]
    #expect(r?.milliwatts == 1000 && r?.wakeupsPerSecond == 0)
    #expect(t.update([snap(5, 0)], at: t0.addingTimeInterval(620))[1]?.milliwatts == 0)
    #expect(t.update([snap(9_000_000_000, 0, start: Date(timeIntervalSince1970: 5))], at: t0.addingTimeInterval(630))[1]?.milliwatts == 0)
}
@Test func groupsSumEnergyAndSortByIt() {
    var a = ProcessRow.fixture(pid: 1, app: "/Applications/A.app"); a.milliwatts = 300
    var b = ProcessRow.fixture(pid: 2, app: "/Applications/B.app"); b.milliwatts = 900
    var c = ProcessRow.fixture(pid: 3, app: "/Applications/B.app"); c.milliwatts = 100
    let g = Grouping.group([a, b, c], mode: .byApp, sort: .energy)
    #expect(g.map(\.title) == ["B", "A"] && g[0].milliwatts == 1000)
}
```

- [ ] **Step 2:** `scripts/test.sh --filter EnergyTrackerTests` → FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** PASS, e a suíte inteira → PASS.
- [ ] **Step 5:** Commit `feat(core): per-process energy and wakeups`.

### Task 2: Bateria, potência total e previsão

**Files:** Create `Sources/MonitorCore/Energy/BatterySampler.swift`; Test `Tests/MonitorCoreTests/BatterySamplerTests.swift`

**Interfaces:**
- Produces: `public struct BatteryReading: Sendable, Equatable`, com init público, e os campos:
  - `percent: Int`
  - `onBattery: Bool`
  - `charging: Bool`
  - `fullyCharged: Bool`
  - `systemMilliwatts: Double?`
  - `healthPercent: Int?`: `AppleRawMaxCapacity` × 100 / `DesignCapacity`, arredondado.
  - `cycles: Int?`
  - `temperatureC: Double?`: `Temperature` / 100.
- Produces: `public enum BatterySampler`, com:
  - `public static func read() -> BatteryReading?`, que lê via IOKit `IOServiceMatching("AppleSmartBattery")` e `IORegistryEntryCreateCFProperties`. Libera os objetos e retorna `nil` sem o serviço.
  - `static func parse(_ p: [String: Any]) -> BatteryReading?`, que retorna `nil` quando faltar `CurrentCapacity`/`AppleRawCurrentCapacity` e `MaxCapacity`.
    - **`percent`:** o `CurrentCapacity` quando `MaxCapacity == 100` (Apple Silicon). Senão, `AppleRawCurrentCapacity` × 100 / `AppleRawMaxCapacity`.
    - **`onBattery`:** `!ExternalConnected`.
    - **`systemMilliwatts`:** o `SystemLoad` de dentro de `PowerTelemetryData`.
- Produces: `public struct BatteryForecast: Sendable`, com:
  - `public init()`
  - `public mutating func add(percent: Int, onBattery: Bool, at: Date)`, que zera tudo ao entrar na tomada.
  - `public func minutesLeft(now: Date) -> Int?`: só com ≥ 180 s na bateria e queda ≥ 1 ponto. A taxa vem das amostras dos últimos 600 s (ou desde o início, se for menos). Resultado: minutos = % atual / (%/min).

- [ ] **Step 1: Failing tests**

```swift
@Test func parsesAppleSiliconBattery() {
    let p: [String: Any] = ["CurrentCapacity": 64, "MaxCapacity": 100, "ExternalConnected": false, "IsCharging": false, "FullyCharged": false,
                            "AppleRawMaxCapacity": 5513, "DesignCapacity": 6249, "CycleCount": 113, "Temperature": 3113,
                            "PowerTelemetryData": ["SystemLoad": 23246]]
    #expect(BatterySampler.parse(p) == BatteryReading(percent: 64, onBattery: true, charging: false, fullyCharged: false, systemMilliwatts: 23246, healthPercent: 88, cycles: 113, temperatureC: 31.13))
    #expect(BatterySampler.parse([:]) == nil)
}
@Test func forecastNeedsThreeMinutesAndOnePercent() {
    var f = BatteryForecast(); let t0 = Date(timeIntervalSince1970: 0)
    f.add(percent: 80, onBattery: true, at: t0)
    f.add(percent: 80, onBattery: true, at: t0.addingTimeInterval(200))
    #expect(f.minutesLeft(now: t0.addingTimeInterval(200)) == nil)
    f.add(percent: 78, onBattery: true, at: t0.addingTimeInterval(240))
    #expect(f.minutesLeft(now: t0.addingTimeInterval(240)) == 156)
    f.add(percent: 78, onBattery: false, at: t0.addingTimeInterval(250))
    #expect(f.minutesLeft(now: t0.addingTimeInterval(250)) == nil)
}
@Test func realBatteryReadDoesNotCrash() { _ = BatterySampler.read() }
```

A conta do segundo teste: 2 pontos em 240 s = 0,5 ponto/min, e 78 / 0,5 = 156 min. A saúde do primeiro: 5513 × 100 / 6249 = 88,2, que arredonda para 88.

- [ ] **Step 2:** `scripts/test.sh --filter BatterySamplerTests` → FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** PASS, e a suíte inteira → PASS.
- [ ] **Step 5:** Commit `feat(core): battery reading and honest forecast`.

### Task 3: Quem impede o sono

**Files:** Create `Sources/MonitorCore/Energy/SleepBlockers.swift`; Test `Tests/MonitorCoreTests/SleepBlockersTests.swift`

**Interfaces:**
- Produces: `public struct SleepBlocker: Sendable, Equatable, Identifiable`, com init público e os campos:
  - `id: String`, no formato `"<pid>:<tipo>"`
  - `pid: Int32`
  - `kind: String`, o tipo cru
  - `title: String`
  - `since: Date?`
  - `ownerPid: Int32`: o PID a fechar. Para um `caffeinate`, é o pai.
- Produces: `public enum SleepBlockers`, com:
  - `public static func read(now: Date) -> [[String: Any]]`: `IOPMCopyAssertionsByProcess`, achatado em dicionários com `"pid"` acrescentado.
  - `public static func build(_ raw: [[String: Any]], rows: [ProcessRow], all: [ProcessSnapshot], now: Date) -> [SleepBlocker]`.
- **Regras do `build`:**
  - **Tipos que entram:** só `PreventUserIdleSystemSleep`, `PreventSystemSleep`, `PreventUserIdleDisplaySleep` e `NoIdleSleepAssertion`. `UserIsActive` e o resto ficam fora.
  - **`since`:** vem de `AssertStartWhen` (Date) quando houver.
  - **Título:**
    - `powerd` com o nome contendo "display is on" → `"Tela ligada"`;
    - `caffeinate` cujo pai é uma linha com kind `.claudeSession` → `"Claude Code está impedindo o Mac de dormir"`, com `ownerPid` = o PID do pai;
    - `caffeinate` com outro pai → `"\(título do pai) está impedindo o Mac de dormir"` (título via `rows`, senão o nome do snapshot);
    - qualquer outro → `"\(título do processo) está impedindo o Mac de dormir"`.
  - **Agrupamento:** um bloqueio por `ownerPid`+tipo. Vários `caffeinate` da mesma sessão viram um só, com o `since` mais antigo.

- [ ] **Step 1: Failing tests**

```swift
@Test func caffeinateUnderClaudeIsNamedAndMerged() {
    let claude = ProcessRow.fixture(pid: 50, kind: .claudeSession)
    let all = [ProcessSnapshot.fixture(pid: 50, name: "claude"), ProcessSnapshot.fixture(pid: 60, name: "caffeinate", ppid: 50), ProcessSnapshot.fixture(pid: 61, name: "caffeinate", ppid: 50),
               ProcessSnapshot.fixture(pid: 529, name: "powerd"), ProcessSnapshot.fixture(pid: 588, name: "WindowServer")]
    let raw: [[String: Any]] = [
        ["pid": 60, "AssertType": "PreventUserIdleSystemSleep", "AssertName": "caffeinate command-line tool", "AssertStartWhen": Date(timeIntervalSince1970: 100)],
        ["pid": 61, "AssertType": "PreventUserIdleSystemSleep", "AssertName": "caffeinate command-line tool", "AssertStartWhen": Date(timeIntervalSince1970: 50)],
        ["pid": 529, "AssertType": "PreventUserIdleSystemSleep", "AssertName": "Powerd - Prevent sleep while display is on"],
        ["pid": 588, "AssertType": "UserIsActive", "AssertName": "x"],
    ]
    let b = SleepBlockers.build(raw, rows: [claude], all: all, now: Date(timeIntervalSince1970: 200))
    #expect(b.map(\.title).sorted() == ["Claude Code está impedindo o Mac de dormir", "Tela ligada"])
    let c = b.first { $0.ownerPid == 50 }
    #expect(c?.since == Date(timeIntervalSince1970: 50))
}
@Test func realAssertionsReadDoesNotCrash() { _ = SleepBlockers.read(now: Date()) }
```

- [ ] **Step 2:** `scripts/test.sh --filter SleepBlockersTests` → FAIL.
- [ ] **Step 3:** Implementar (`import IOKit.pwr_mgt`, liberando o CF com `takeRetainedValue`).
- [ ] **Step 4:** PASS, e a suíte inteira → PASS.
- [ ] **Step 5:** Commit `feat(core): sleep blockers with readable owners`.

### Task 4: Histórico de sono e despertares (pmset)

**Files:** Create `Sources/MonitorCore/Energy/PowerLog.swift`; Test `Tests/MonitorCoreTests/PowerLogTests.swift`

**Interfaces:**
- Produces: `public enum WakeCause: String, Sendable, CaseIterable, Codable`, com os casos e os títulos em pt-BR:

  | Caso | Título |
  |---|---|
  | `network` | "Wi‑Fi/Bluetooth (rede e notificações)" |
  | `timer` | "Relógio (tarefas agendadas)" |
  | `user` | "Teclado, mouse ou tampa" |
  | `power` | "Carregador/USB‑C" |
  | `other` | "Outros" |

  Exposto em `public var title: String`.
- Produces: `public struct PowerLogSession: Sendable, Equatable { start: Date; end: Date; startPercent: Int; endPercent: Int }`.
- Produces: `public struct PowerLogSummary: Sendable, Equatable`, com:
  - `sessions: [PowerLogSession]`
  - `wakes: [WakeCause: Int]`
  - `thermalSleeps: Int`
  - `sleepDrainPerHour: Double?`
  - `static let empty`
- Produces: `public enum PowerLog`, com:
  - `public static func parse(_ text: String) -> PowerLogSummary`
  - `public static func load(runner: CommandRunner = SystemCommandRunner()) -> PowerLogSummary`, que roda `/usr/bin/pmset -g log` com timeout de 10 s. Qualquer falha devolve `.empty`.
- **Regras de leitura:**
  - **Formato das linhas:** `yyyy-MM-dd HH:mm:ss Z`, seguido do tipo de evento (`Sleep`, `Wake`, `DarkWake`, `Assertions`, …) e de "Using Batt|AC (Charge:NN%)" ou "Using BATT".
  - **Sessões na bateria:** sequências contínuas de linhas "Using Batt" com queda > 2 pontos e duração > 30 min.
  - **Causa do despertar:** vem do texto após "due to":
    - contém `wifibt` ou `Network` → `network`;
    - `rtc` ou `RTC` → `timer`;
    - `HID`, `UserActivity`, `lid` ou `Lid` → `user`;
    - `USB-C_plug`, `USB2_wake` ou `AC` → `power`;
    - o resto → `other`.
  - **`thermalSleeps`:** linhas `Sleep` contendo "Thermal".
  - **`sleepDrainPerHour`:** soma das quedas de % entre um `Sleep` "Using Batt" e o próximo `Wake` "Using Batt", dividida pelas horas dormindo. `nil` quando houver menos de 1 h dormindo na bateria.

- [ ] **Step 1: Failing tests**

```swift
let sampleLog = """
2026-10-15 02:21:47 -0300 DarkWake            \tDarkWake from Deep Idle [CDNP] : due to smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty/ Using Batt (Charge:99%) 2 secs
2026-10-15 02:21:52 -0300 Sleep               \tEntering Sleep state due to 'Maintenance Sleep':TCPKeepAlive=active Using Batt (Charge:99%) 27 secs
2026-10-15 05:21:52 -0300 Wake                \tWake from Deep Idle [CDNVA] : due to HID Activity Using Batt (Charge:96%) 2 secs
2026-10-15 09:00:00 -0300 Sleep               \tEntering Sleep state due to 'Dark Wake Thermal Emergency':TCPKeepAlive=active Using Batt (Charge:70%)
2026-10-15 09:10:00 -0300 DarkWake            \tDarkWake from Deep Idle [CDNPB] : due to NUB.SPMI0Sw3IRQ nub-spmi0.0x02 rtc/SleepService Using Batt (Charge:70%)
2026-10-15 10:00:00 -0300 Assertions          \tSummary- [System: PrevIdle] Using AC(Charge: 69)
garbage line
"""
@Test func parsesSessionsWakesAndSleepDrain() {
    let s = PowerLog.parse(sampleLog)
    #expect(s.sessions.count == 1 && s.sessions[0].startPercent == 99 && s.sessions[0].endPercent == 70)
    #expect(s.wakes[.network] == 1 && s.wakes[.user] == 1 && s.wakes[.timer] == 1)
    #expect(s.thermalSleeps == 1)
    #expect(s.sleepDrainPerHour == 1)
    #expect(PowerLog.parse("") == .empty)
}
@Test func loadFailsSoftly() {
    struct Dead: CommandRunner { func run(_ p: String, _ a: [String], timeout: TimeInterval) -> (status: Int32, output: String)? { nil } }
    #expect(PowerLog.load(runner: Dead()) == .empty)
}
```

A conta do `sleepDrainPerHour`: dormiu às 02:21:52 com 99% e acordou às 05:21:52 com 96%, ou seja, 3 pontos em 3 h, que dá 1. O trecho que começa às 09:00 não tem um `Wake` depois, só um `DarkWake` às 09:10 com o mesmo %. Quem construir decide se conta o `DarkWake` como fim de sono: some ao total 0 pontos em 10 min, o que leva o resultado a ~0,95. Mude a asserção para `abs(... - 1) < 0.1` se for o caso.

- [ ] **Step 2:** `scripts/test.sh --filter PowerLogTests` → FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** PASS, e a suíte inteira → PASS.
- [ ] **Step 5:** Commit `feat(core): parse pmset log for sessions and wakes`.

### Task 5: Sessões na bateria

**Files:** Create `Sources/MonitorCore/Energy/BatterySessions.swift`; Test `Tests/MonitorCoreTests/BatterySessionsTests.swift`

**Interfaces:**
- Produces: `public struct EnergyItem: Codable, Sendable, Equatable { title: String; milliwattHours: Double }`.
- Produces: `public struct BatterySession: Codable, Sendable, Equatable, Identifiable`, com:
  - **Campos:** `id: UUID`, `start: Date`, `end: Date?`, `startPercent: Int`, `endPercent: Int`, `awakeSeconds: Double`, `top: [EnergyItem]` (até 5) e `reconstructed: Bool`.
  - **`drainPerHour`:** queda / horas acordado. `nil` com < 0,25 h acordado.
- Produces: `public struct SessionRecorder: Sendable`, com:
  - **`public init(sessions: [BatterySession])`** e **`public private(set) var sessions`**.
  - **`public mutating func update(battery: BatteryReading, groups: [ProcessGroup], at now: Date, interval: TimeInterval) -> Bool`.** Retorna `true` quando algo mudou e precisa gravar.
    - **Abrir e fechar:** abre uma sessão ao passar para a bateria e fecha ao sair dela.
    - **Na bateria:** soma `interval` em `awakeSeconds` e soma `group.milliwatts * interval / 3600` por título de grupo. Guarda os totais num dicionário interno, e o `top` são os 5 maiores.
    - **Gravação periódica:** também retorna `true` a cada 300 s de sessão aberta.
  - **`public mutating func merge(_ log: [PowerLogSession])`:** acrescenta as sessões do log que não se sobrepõem às existentes, como `reconstructed: true`.
  - **Limite:** mantém as 60 sessões mais recentes.
- Produces: `public struct BatterySessionStore: Sendable { init(url:); static var defaultURL; load() -> [BatterySession]; save(_:) }`, no molde do `PeakStore`. Um arquivo corrompido ou ausente dá `[]`.
- Produces: `public enum SessionInsight { public static func compare(_ s: BatterySession, history: [BatterySession]) -> String? }`.
  - **Média:** a média de `drainPerHour` das outras sessões que não são `reconstructed`.
  - **Quando fala:** se a sessão for ≥ 1,5× a média, retorna `"Esta sessão gastou \(fator)× mais que a sua média; principais diferenças: \(títulos)"`.
  - **O fator:** 1 casa decimal, com vírgula.
  - **Os títulos:** até 2 títulos da sessão cuja energia esteja acima da média deles nas outras sessões, por diferença decrescente.
  - Senão, retorna `nil`.

- [ ] **Step 1: Failing tests**

```swift
@Test func recorderOpensAccumulatesAndCloses() {
    var r = SessionRecorder(sessions: [])
    var g = ProcessGroup.fixture(kind: .appProcess, app: "/Applications/Chrome.app"); g.milliwatts = 3600
    let bat = BatteryReading(percent: 90, onBattery: true, charging: false, fullyCharged: false, systemMilliwatts: nil, healthPercent: nil, cycles: nil, temperatureC: nil)
    let t0 = Date(timeIntervalSince1970: 0)
    #expect(r.update(battery: bat, groups: [g], at: t0, interval: 0))
    _ = r.update(battery: bat, groups: [g], at: t0.addingTimeInterval(3600), interval: 3600)
    var ac = bat; ac.onBattery = false; ac.percent = 70
    #expect(r.update(battery: ac, groups: [g], at: t0.addingTimeInterval(3601), interval: 1))
    let s = r.sessions[0]
    #expect(s.end != nil && s.startPercent == 90 && s.endPercent == 70 && s.top.first == EnergyItem(title: "Chrome", milliwattHours: 3600))
    #expect(s.drainPerHour == 20)
}
@Test func insightNamesDifferences() {
    func s(_ drain: Int, _ top: [EnergyItem]) -> BatterySession {
        BatterySession(id: UUID(), start: .distantPast, end: .distantPast, startPercent: 100, endPercent: 100 - drain, awakeSeconds: 3600, top: top, reconstructed: false)
    }
    let history = [s(10, [EnergyItem(title: "Arc", milliwattHours: 2000)]), s(10, [EnergyItem(title: "Arc", milliwattHours: 2000)])]
    let now = s(25, [EnergyItem(title: "supabase", milliwattHours: 9000), EnergyItem(title: "Arc", milliwattHours: 2000)])
    #expect(SessionInsight.compare(now, history: history) == "Esta sessão gastou 2,5× mais que a sua média; principais diferenças: supabase")
}
@Test func corruptSessionFileLoadsEmpty() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    try Data("{x".utf8).write(to: url)
    #expect(BatterySessionStore(url: url).load().isEmpty)
}
```

`ProcessGroup.gpuPercent` já existe. Para o fixture, `milliwatts` precisa ser `var` em `ProcessGroup`, como os outros campos.

- [ ] **Step 2:** `scripts/test.sh --filter BatterySessionsTests` → FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** PASS, e a suíte inteira → PASS.
- [ ] **Step 5:** Commit `feat(core): battery sessions with comparison`.

### Task 6: Motivo principal, sugestões e alerta de energia

**Files:** Create `Sources/MonitorCore/Energy/EnergyAdvisor.swift`; Modify `Sources/MonitorCore/Runaway/RunawayTracker.swift`; Test `Tests/MonitorCoreTests/EnergyAdvisorTests.swift`

**Interfaces:**
- Produces: `public enum EnergyAdvisor`, com:
  - **`public static func reason(_ g: ProcessGroup, blockers: [SleepBlocker]) -> String`**, com as regras das Global Constraints e estes textos:

    | Condição | Texto |
    |---|---|
    | CPU | `"CPU alta (\(Int(g.cpuPercent))%)"` |
    | GPU | `"GPU (\(Int(g.gpuPercent))%)"` |
    | Despertares | `"acorda a CPU \(Int(g.wakeupsPerSecond))×/s"` |
    | Bloqueio de sono | `"impede o Mac de dormir"` (algum `ownerPid` ∈ PIDs do grupo) |
    | Nenhuma | `"uso leve"` |

    "Vence o que contribuir mais": quando mais de uma condição passar do limite, ganha a de maior razão valor/limite.
  - Produces: `public enum SuggestionAction: Sendable, Equatable { case close(groupID: String), closeOwner(pid: Int32), copy(String) }` e `public struct EnergySuggestion: Sendable, Equatable, Identifiable { id: String; title: String; detail: String; savingMilliwatts: Double?; action: SuggestionAction }`.
  - **`public static func suggestions(groups: [ProcessGroup], runaways: [Runaway], blockers: [SleepBlocker], log: PowerLogSummary, onBattery: Bool, userIdleSeconds: Double, now: Date) -> [EnergySuggestion]`**, com no máximo 4, nesta ordem:
    1. **Grupo com descontrolado** (`runaways` contém linha do grupo) e `milliwatts` > 500:
       - título `"Fechar \(g.title)"`;
       - detalhe = `hint` do descontrolado;
       - economia = `g.milliwatts`;
       - ação `.close(groupID: g.id)`.
    2. **Bloqueio com `since` há > 1800 s e `userIdleSeconds` > 1800:**
       - título = o título do bloqueio;
       - detalhe `"há \(Format.age)"`;
       - ação `.closeOwner(pid:)`.
    3. **Se `onBattery`, grupo de kind `.devServer` ou `.database` com `oldestStart` há > 8 h:**
       - título `"\(g.title) ligado há \(Format.age)"`;
       - detalhe `"Feche se não estiver usando"`;
       - economia = `g.milliwatts`;
       - ação `.close`.
    4. **Se `log.wakes[.network] ?? 0` ≥ 50:**
       - título `"O Mac acordou \(n)× pela rede enquanto dormia"`;
       - detalhe `"Ajustes › Bateria › Opções › Acordar para acesso à rede: Nunca na bateria"`;
       - ação `.copy("sudo pmset -b tcpkeepalive 0")`.
- **`RunawayReason`:**
  - Ganha `case energy(milliwatts: Int, minutes: Int)`, com o texto `"Gastando ~\(W) W há \(minutes) min na bateria."`, onde W tem 1 casa decimal e vírgula.
  - `RunawayTracker.update` ganha `onBattery: Bool = false` ao final. A condição de energia é `onBattery` e `row.milliwatts` > 2000 de forma contínua por ≥ 600 s, com a mesma elegibilidade da CPU e prioridade depois de CPU e GPU.

- [ ] **Step 1: Failing tests**

```swift
@Test func reasonPicksStrongestFactor() {
    var g = ProcessGroup.fixture(kind: .appProcess, app: "/Applications/A.app")
    g.cpuPercent = 60; g.gpuPercent = 80
    #expect(EnergyAdvisor.reason(g, blockers: []) == "GPU (80%)")
    g.gpuPercent = 0; g.cpuPercent = 10; g.wakeupsPerSecond = 333
    #expect(EnergyAdvisor.reason(g, blockers: []) == "acorda a CPU 333×/s")
    g.wakeupsPerSecond = 1
    #expect(EnergyAdvisor.reason(g, blockers: []) == "uso leve")
}
@Test func suggestionsRespectRulesAndLimit() {
    let now = Date(timeIntervalSince1970: 100_000)
    let blocker = SleepBlocker(id: "60:x", pid: 60, kind: "PreventUserIdleSystemSleep", title: "Claude Code está impedindo o Mac de dormir", since: now.addingTimeInterval(-3600), ownerPid: 50)
    var log = PowerLogSummary.empty; log.wakes = [.network: 268]
    let s = EnergyAdvisor.suggestions(groups: [], runaways: [], blockers: [blocker], log: log, onBattery: true, userIdleSeconds: 2000, now: now)
    #expect(s.map(\.action) == [.closeOwner(pid: 50), .copy("sudo pmset -b tcpkeepalive 0")])
    #expect(EnergyAdvisor.suggestions(groups: [], runaways: [], blockers: [blocker], log: .empty, onBattery: true, userIdleSeconds: 10, now: now).isEmpty)
}
@Test func energyRunawayOnlyOnBattery() {
    var t = RunawayTracker(); let ig = IgnoreList(defaults: .ephemeral())
    var r = ProcessRow.fixture(pid: 7, app: "/Applications/Game.app"); r.milliwatts = 2500
    let t0 = Date(timeIntervalSince1970: 0)
    _ = t.update([r], at: t0, myUid: 501, ignore: ig, onBattery: true)
    #expect(t.update([r], at: t0.addingTimeInterval(600), myUid: 501, ignore: ig, onBattery: true).first?.reason == .energy(milliwatts: 2500, minutes: 10))
    var t2 = RunawayTracker()
    _ = t2.update([r], at: t0, myUid: 501, ignore: ig, onBattery: false)
    #expect(t2.update([r], at: t0.addingTimeInterval(600), myUid: 501, ignore: ig, onBattery: false).isEmpty)
}
```

`ProcessGroup` precisa ter `cpuPercent`, `gpuPercent`, `milliwatts` e `wakeupsPerSecond` como `var`.

- [ ] **Step 2:** `scripts/test.sh --filter EnergyAdvisorTests` → FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** PASS, e a suíte inteira → PASS.
- [ ] **Step 5:** Commit `feat(core): energy reasons, suggestions and battery alert`.

### Task 7: Aba Bateria, popover e alerta no app

**Files:** Create `Sources/Monitor/UI/BatteryView.swift`; Modify `MonitorStore.swift`, `MainWindow.swift`, `PopoverView.swift`

**Interfaces:**
- Consumes: tudo das Tasks 1–6.
- **Store, a cada ciclo:**
  - `EnergyTracker` → `ProcessRow.milliwatts` e `wakeupsPerSecond`.
  - `BatterySampler.read()`, rodando no `Task.detached` existente → `var battery: BatteryReading?`.
  - `BatteryForecast.add`.
  - `SleepBlockers.read` + `build` → `var sleepBlockers`.
  - `SessionRecorder.update`, usando `interval` = o tempo desde o último ciclo. Grava com `BatterySessionStore` quando retornar `true`.
  - `RunawayTracker.update(..., onBattery:)`.
  - **Tempo ocioso do usuário:** `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)`.
- **Store, ao entrar na aba Bateria:** se o último `PowerLog.load` tiver mais de 600 s, roda de novo em `Task.detached` e faz `merge` das sessões. Expõe `var powerLog: PowerLogSummary`.
- **`WindowTab.battery`:** "Bateria", depois de Disco, no grupo SISTEMA.
- **`BatteryView`, nesta ordem:**
  1. **Cards:** carga e estado; potência `"~\(W) W"`; previsão `"~4h20"` ou `"calculando…"`; saúde `"\(saúde)% · \(ciclos) ciclos · \(temp) °C"`. O card de carga e o de saúde somem sem bateria.
  2. **"Quem está gastando agora":** os grupos ordenados por `milliwatts`.
     - Cada linha mostra o ícone, o título, `"~\(mW) mW"`, o % do total medido e o `EnergyAdvisor.reason`, com o botão ✕ das regras atuais.
     - A última linha é "Sistema e tela" = `max(0, systemMilliwatts − soma)`, marcada "estimado".
  3. **"Impedindo o Mac de dormir":** os `sleepBlockers`, com título, "há X" e o botão Fechar (`ownerPid`), com confirmação.
  4. **"Como economizar":** as `EnergySuggestion`, com o botão da ação. `copy` vai para a área de transferência e mostra "Comando copiado".
  5. **"Sessões na bateria":** até 14, mais recentes primeiro. Cada uma mostra a data e hora, a duração, `startPercent→endPercent`, `"\(drain)%/h acordado"` (ou "—"), o top 3 e o insight da `SessionInsight`. As reconstruídas levam a etiqueta "do registro do sistema".
  6. **"Sono (7 dias)":** `wakes` por causa com contagem, `thermalSleeps` se > 0 e `sleepDrainPerHour` em "%/h dormindo".
- **Popover:**
  - Na bateria, mostra `"Bateria \(p)% · ~\(W) W · ~\(previsão)"`.
  - Mostra também `"Maior consumo: \(título)"` quando o maior grupo tiver > 30% do total medido.
- **Alerta:** passa pelo `RunawayReason.energy` existente; nenhum código novo de notificação.

- [ ] **Step 1:** Implementar o store e rodar `scripts/test.sh` → PASS.
- [ ] **Step 2:** Implementar `BatteryView`, a aba e o popover.
- [ ] **Step 3:** `scripts/bundle.sh` → instala e reabre. Medir o consumo do Vernio com a janela fechada por 2 min. Ele deve continuar perto de **0,6% de CPU e 20 MB**; anotar os números no relatório.
- [ ] **Step 4:** Commit `feat(app): battery tab with energy, sleep and sessions`.
