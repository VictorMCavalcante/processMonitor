# Monitor — Disco v2 e GPU — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:**
- **Aba Disco:** progresso visível, seções que aparecem conforme ficam prontas, o último relatório salvo aparecendo na hora, análise mais rápida e wallpapers aéreos apagáveis.
- **GPU:** uso total, memória de GPU, % por processo com ordenação, alerta de descontrolado e GPU nos picos.

**Architecture:**
- **Disco:** `DiskAnalyzer.analyze` ganha callbacks `@Sendable` de progresso e de relatório parcial. Mede em paralelo dentro de cada etapa e mantém as etapas em ordem (Seguro → Sobras → Dados), por causa do desconto do que já foi contado.
- **Persistência:** `DiskReport` passa a ser `Codable` e é salvo por um `DiskReportStore`, no mesmo molde do `PeakStore`.
- **GPU:** um `GPUSampler` em `MonitorCore` lê o IOKit dentro do processo. Funções puras de parse e um `GPUTracker`, no molde do `CPUTracker`, convertem o tempo acumulado em %. A GPU entra em `ProcessRow`, `ProcessGroup`, `SystemStats`, `RunawayTracker` e `PeakRecorder`.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, IOKit, Swift Testing (`scripts/test.sh`). Sem dependências novas.

**Spec:** `docs/superpowers/specs/2026-10-21-monitor-disco-v2-gpu-design.md`. Ele estende `2026-10-20-monitor-disco-design.md` e os designs v1 e v2. Ler o spec inteiro antes da Task 1.

## Global Constraints

- macOS 14+, sem Xcode, sem dependências de terceiros.
- Interface em pt-BR, tema `Theme`, **zero comentários no código**.
- Commits em inglês **sem coautoria e sem linhas de atribuição**.
- Nunca apagar nada sem confirmação. Tudo vai para a Lixeira, exceto o Docker.
- Cada byte numa categoria só, com prioridade Seguro > Sobras > Dados. O paralelismo não pode quebrar isso.
- A análise de disco roda fora da thread principal e só ao abrir a aba ou no ↻. Nunca roda no ciclo de 3 s/10 s.
- O relatório salvo é só para olhar. Limpar só fica habilitado depois que uma análise desta sessão termina.
- Relatório salvo com mais de **1 h** (3600 s) faz uma nova análise começar sozinha ao abrir a aba.
- Meta de tempo da análise no Mac do Victor: **≤ 30 s** com o Docker fechado. Medir antes e depois.
- A GPU é lida pelo IOKit dentro do processo, nunca rodando `ioreg` como subprocesso. A leitura cabe no ciclo atual.
- GPU % por processo = Δ`accumulatedGPUTime` (ns) / Δtempo (ns) × 100, com **teto de 100**.
  - O primeiro ciclo de um processo vale 0.
  - Um PID reutilizado (outra hora de início) zera o histórico.
  - Uma diferença negativa vale 0.
  - Vários clientes do mesmo PID são somados.
- Descontrolado por GPU: **≥ 80% contínuo por ≥ 5 min**, com as mesmas regras de elegibilidade da CPU.
- Picos guardam os **3** maiores de GPU no mesmo momento em que gravam o `top` de memória. O campo é opcional, para que picos antigos continuem abrindo.
- Falha de leitura da GPU mostra "–" e não quebra nada.

## Review Focus

- **Arquivo de relatório corrompido, ausente ou de formato antigo:** começa vazio e analisa, sem travar. (teste na Task 3)
- **Limpeza enquanto aparece o relatório salvo de uma sessão anterior:** fica bloqueada até a análise nova terminar. (teste na Task 4, `canClean`)
- **Medição em paralelo do mesmo inode por duas pastas (hard link):** conta uma vez, e o total é igual ao da medição sequencial. (teste na Task 2)
- **Cliente de GPU que fecha entre dois ciclos (acumulado diminui) ou PID reutilizado:** dá 0, nunca negativo nem herdado. (teste na Task 5)
- **Mac sem a chave `PerformanceStatistics` ou com uma chave ausente:** a leitura dá `nil` naquele campo, e o card mostra "–". (teste na Task 5)

---

## File Structure

```
Sources/MonitorCore/Disk/SafeCatalog.swift      MODIFY: entrada de wallpapers; node_modules em duas fases com progresso; medição paralela
Sources/MonitorCore/Disk/DiskAnalyzer.swift     MODIFY: DiskProgress, callbacks, paralelismo em dados de apps
Sources/MonitorCore/Disk/DiskModel.swift        MODIFY: Codable
Sources/MonitorCore/Disk/DiskReportStore.swift  NEW: salvar/carregar o relatório
Sources/MonitorCore/GPU/GPUSampler.swift        NEW: GPUReading, leitura IOKit, parse puro
Sources/MonitorCore/GPU/GPUTracker.swift        NEW: tempo acumulado → %
Sources/MonitorCore/Classify/Grouping.swift     MODIFY: gpuPercent em ProcessRow/ProcessGroup; GroupSort
Sources/MonitorCore/Model/SystemStats.swift     MODIFY: gpuPercent, gpuMemoryBytes
Sources/MonitorCore/Runaway/RunawayTracker.swift MODIFY: .gpu
Sources/MonitorCore/Peaks/PeakRecorder.swift    MODIFY: PeakGPUItem, topGPU
Sources/Monitor/Store/MonitorStore.swift        MODIFY: progresso, relatório salvo, canClean, GPU no ciclo, ordenação
Sources/Monitor/UI/DiskView.swift               MODIFY: linha de progresso, seções parciais
Sources/Monitor/UI/MetricCards.swift, ProcessListView.swift, DetailPanel.swift, PopoverView.swift, PeaksView.swift  MODIFY: GPU
Tests/MonitorCoreTests/*                        testes por arquivo do Core
```

---

### Task 1: Wallpapers aéreos no Seguro

**Files:** Modify `Sources/MonitorCore/Disk/SafeCatalog.swift`; Test `Tests/MonitorCoreTests/SafeCatalogTests.swift`, `Tests/MonitorCoreTests/DiskAnalyzerTests.swift`

**Interfaces:**
- **Nova entrada no catálogo:**
  - título `"Wallpapers e protetores aéreos"`
  - caminho `Library/Application Support/com.apple.wallpaper/aerials/videos`
  - sem dono, marcado
  - warning `"o macOS baixa de novo se você usar um fundo animado"`
- **Efeito no analisador:** como a pasta passa a contar em Seguro, o item `wallpaper` de Dados continua existindo, mas medido pelo `ClaimedFS`. Ele só aparece se o resto da pasta passar de 1 GB.

- [ ] **Step 1: Failing tests**

```swift
@Test func aerialVideosAreSafeAndChecked() {
    let fs = FakeDiskFS(files: ["/h/Library/Application Support/com.apple.wallpaper/aerials/videos/a.mov": (9_000 * mb, .distantPast)])
    let w = SafeCatalog.scan(fs: fs, home: "/h", runningBundleIDs: [], busyPaths: [], skipProtectedHomeFolders: false).first { $0.title == "Wallpapers e protetores aéreos" }
    #expect(w?.checkedByDefault == true && w?.warning == "o macOS baixa de novo se você usar um fundo animado")
}
@Test func wallpaperAppDataExcludesAerialVideos() {
    let fs = FakeDiskFS(files: [
        "/h/Library/Application Support/com.apple.wallpaper/aerials/videos/a.mov": (9_000 * mb, .distantPast),
        "/h/Library/Application Support/com.apple.wallpaper/Store/x": (10 * mb, .distantPast),
    ])
    let r = DiskAnalyzer.analyze(fs: fs, home: "/h", apps: FakeAppIndex(), volume: (100_000 * mb, 10_000 * mb), docker: nil, runningBundleIDs: [], busyPaths: [], now: .distantPast)
    #expect(r.bytes(.safe) == 9_000 * mb && !r.items.contains { $0.id == "wallpaper" })
}
```

- [ ] **Step 2:** `scripts/test.sh --filter "SafeCatalogTests|DiskAnalyzerTests"` → FAIL.
- [ ] **Step 3:** Acrescentar a entrada.
- [ ] **Step 4:** Rodar os mesmos testes → PASS, e a suíte inteira → PASS.
- [ ] **Step 5:** Commit `feat(disk): aerial wallpapers are safe to clean`.

### Task 2: Progresso, relatório parcial e paralelismo

**Files:** Modify `Sources/MonitorCore/Disk/SafeCatalog.swift`, `Sources/MonitorCore/Disk/DiskAnalyzer.swift`, `Tests/MonitorCoreTests/DiskFakes.swift`; Test `Tests/MonitorCoreTests/DiskProgressTests.swift`

**Interfaces:**
- Produces: `public struct DiskProgress: Sendable, Equatable { public var stage: String; public var done: Int?; public var total: Int? }`, com init público.
- **Textos exatos das etapas:**
  - `"Listando apps instalados"`
  - `"Medindo caches"`
  - `"Medindo node_modules"` (com `done` e `total`)
  - `"Procurando sobras"`
  - `"Medindo dados de apps"` (com `done` e `total` sobre as pastas)
  - `"Medindo Docker"`
- **Formatação:** fica para a UI ("Medindo node_modules… 12 de 33"). O `stage` não leva reticências.
- **Novos parâmetros de `DiskAnalyzer.analyze`**, ao final, com padrão:
  - `progress: @Sendable (DiskProgress) -> Void = { _ in }`
  - `partial: @Sendable (DiskReport) -> Void = { _ in }`
- **Quando o `partial` é chamado:** duas vezes antes do retorno. Uma depois do Seguro (só os itens `.safe`) e outra depois das Sobras (safe + leftovers). O retorno continua sendo o relatório final. `scannedAt` é o mesmo `now` em todos.
- **`SafeCatalog.scan` em duas fases:**
  - Primeiro acha todos os caminhos de `node_modules`, sem medir.
  - Depois mede em paralelo com `DispatchQueue.concurrentPerform`, com até `DiskAnalyzer.parallelism = 4` tarefas simultâneas, e chama o novo parâmetro `progress: @Sendable (Int, Int) -> Void = { _, _ in }` com `(feitos, total)`.
  - As entradas do catálogo também são medidas em paralelo.
- **Dados de apps:** as pastas candidatas também são medidas em paralelo pelo `ClaimedFS`. A soma por app é feita depois, em sequência.
- **Ordem das etapas:** `"Listando apps instalados"` só aparece se o store construir o `SystemAppIndex` dentro da análise (ver Task 4). O `"Medindo Docker"` é emitido pelo store antes de chamar `analyze`.
- **Thread-safety:**
  - O `RealDiskFS` já protege o conjunto `seen` com um lock.
  - O `ClaimedFS` só lê `claimed` durante a medição paralela; a escrita acontece entre as etapas.
  - O `FakeDiskFS` passa a proteger `listed` com um `NSLock`.
- **Medição de tempo:** antes de mudar qualquer coisa, meça o tempo atual de `analyze` no home real com um teste temporário não commitado (como o probe da revisão anterior). Meça de novo no fim. Ponha os dois números no relatório da tarefa. Meta: ≤ 30 s. Se não chegar lá, diga onde o tempo está indo; não é motivo para bloquear.

- [ ] **Step 1: Failing tests**

```swift
@Test func progressReportsNodeModulesCountsAndStages() {
    let fs = FakeDiskFS(files: [
        "/h/d/a/package.json": (1, .distantPast), "/h/d/a/node_modules/x": (60 * mb, .distantPast),
        "/h/d/b/package.json": (1, .distantPast), "/h/d/b/node_modules/x": (60 * mb, .distantPast),
    ])
    let log = Locked<[DiskProgress]>([])
    _ = DiskAnalyzer.analyze(fs: fs, home: "/h", apps: FakeAppIndex(), volume: (1_000 * mb, 100 * mb), docker: nil, runningBundleIDs: [], busyPaths: [], now: .distantPast,
                             progress: { p in log.mutate { $0.append(p) } })
    let stages = log.value.map(\.stage)
    #expect(stages.contains("Medindo caches") && stages.contains("Procurando sobras") && stages.contains("Medindo dados de apps"))
    #expect(log.value.contains(DiskProgress(stage: "Medindo node_modules", done: 2, total: 2)))
}
@Test func partialReportsArriveInOrderBeforeFinal() {
    let fs = FakeDiskFS(files: ["/h/.npm/_cacache/x": (100 * mb, .distantPast),
                                "/h/Library/Application Support/com.gone.app/x": (100 * mb, .distantPast),
                                "/h/Library/Preferences/com.gone.app.plist": (1, .distantPast)])
    let parts = Locked<[DiskReport]>([])
    let final = DiskAnalyzer.analyze(fs: fs, home: "/h", apps: FakeAppIndex(), volume: (1_000 * mb, 100 * mb), docker: nil, runningBundleIDs: [], busyPaths: [], now: .distantPast,
                                     partial: { r in parts.mutate { $0.append(r) } })
    #expect(parts.value.count == 2)
    #expect(parts.value[0].items.allSatisfy { $0.category == .safe } && parts.value[1].bytes(.leftover) > 0)
    #expect(final.bytes(.safe) == parts.value[0].bytes(.safe))
}
@Test func parallelSizingMatchesSequentialWithHardLinks() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let a = dir.appendingPathComponent(".npm/_cacache"), b = dir.appendingPathComponent(".cache/uv")
    try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try Data(count: 60_000_000).write(to: a.appendingPathComponent("f"))
    try FileManager.default.linkItem(at: a.appendingPathComponent("f"), to: b.appendingPathComponent("f"))
    let items = SafeCatalog.scan(fs: RealDiskFS(), home: dir.path, runningBundleIDs: [], busyPaths: [], skipProtectedHomeFolders: false)
    #expect(items.reduce(0) { $0 + $1.bytes } < 70_000_000)
}
```

- `Locked<T>` é um helper de teste que vai no `DiskFakes.swift`: `final class Locked<T>: @unchecked Sendable { init(_ v: T); var value: T { get }; func mutate(_ f: (inout T) -> Void) }`, com `NSLock`.
- O terceiro teste usa um item de 60 MB e o outro com 0 bytes contados. O `≥ 50 MB` filtra o segundo, e a soma prova que o hard link foi contado uma vez.

- [ ] **Step 2:** `scripts/test.sh --filter DiskProgressTests` → FAIL.
- [ ] **Step 3:** Medir o tempo atual (probe temporário), implementar, e medir de novo.
- [ ] **Step 4:** `scripts/test.sh --filter DiskProgressTests` → PASS, e a suíte inteira → PASS.
- [ ] **Step 5:** Commit `perf(disk): staged progress and parallel sizing`.

### Task 3: Relatório salvo

**Files:** Modify `Sources/MonitorCore/Disk/DiskModel.swift`, `Sources/MonitorCore/Disk/DiskAnalyzer.swift`; Create `Sources/MonitorCore/Disk/DiskReportStore.swift`; Test `Tests/MonitorCoreTests/DiskReportStoreTests.swift`

**Interfaces:**
- `DiskCategory`, `DockerPrune`, `DiskAction`, `DiskItem` e `DiskReport` passam a ser `Codable`, com síntese automática.
- Produces: `public struct DiskReportStore: Sendable`, com:
  - `public init(url: URL)`
  - `public static var defaultURL: URL`, que aponta para `…/Application Support/Monitor/disk-report.json`
  - `public func load() -> DiskReport?`
  - `public func save(_ r: DiskReport)`
  - Mesma estratégia de data do `PeakStore` (`secondsSince1970`), gravação atômica e criação da pasta.
- Produces: `public static let staleAfter: TimeInterval = 3600` em `DiskReportStore` e `public static func isStale(_ r: DiskReport, now: Date) -> Bool`, onde `isStale` = `now − scannedAt > staleAfter`.

- [ ] **Step 1: Failing tests**

```swift
@Test func reportRoundTripsAndCorruptFileLoadsNil() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "/r.json")
    let store = DiskReportStore(url: url)
    #expect(store.load() == nil)
    let item = DiskItem(id: "a", title: "npm cache", detail: nil, category: .safe, bytes: 5, action: .trash(["/a"]), checkedByDefault: true,
                        children: [DiskItem(id: "b", title: "b", detail: nil, category: .safe, bytes: 1, action: .docker(.unusedImages))])
    let r = DiskReport(total: 10, free: 2, items: [item], protectedSkipped: true, dockerMeasured: false, scannedAt: Date(timeIntervalSince1970: 1_000))
    store.save(r)
    #expect(store.load() == r)
    try Data("{oops".utf8).write(to: url)
    #expect(store.load() == nil)
}
@Test func staleAfterOneHour() {
    let r = DiskReport(total: 1, free: 1, items: [], protectedSkipped: false, dockerMeasured: false, scannedAt: Date(timeIntervalSince1970: 0))
    #expect(!DiskReportStore.isStale(r, now: Date(timeIntervalSince1970: 3600)))
    #expect(DiskReportStore.isStale(r, now: Date(timeIntervalSince1970: 3601)))
}
```

- `isStale` é `static`, e o teste a chama assim.
- `DiskReport` precisa de um init público memberwise. Acrescente-o se ainda não existir.

- [ ] **Step 2:** `scripts/test.sh --filter DiskReportStoreTests` → FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** `scripts/test.sh --filter DiskReportStoreTests` → PASS, e a suíte inteira → PASS.
- [ ] **Step 5:** Commit `feat(disk): persist last disk report`.

### Task 4: Store e interface do Disco v2

**Files:** Modify `Sources/Monitor/Store/MonitorStore.swift`, `Sources/Monitor/UI/DiskView.swift`, `Sources/Monitor/UI/MainWindow.swift`

**Interfaces:**
- Consumes: `DiskProgress`, os callbacks `progress`/`partial` de `analyze`, `DiskReportStore` (`load`/`save`/`isStale`).
- **`MonitorStore` ganha:**
  - `var diskProgress: DiskProgress?`, que vale `nil` quando não há análise rodando.
  - `var diskFresh = false`, que fica `true` quando uma análise desta sessão termina.
  - `var canClean: Bool { diskFresh && !diskScanning && !diskCleaning }`
  - `func openDiskTab() async`, que no primeiro uso carrega o salvo em `disk`. Se não houver salvo ou ele estiver velho, chama `analyzeDisk()`.
- **`analyzeDisk()` muda assim:**
  - Os callbacks fazem `Task { @MainActor in … }` para atualizar `diskProgress` e `disk` (o parcial).
  - A construção do `SystemAppIndex` emite `"Listando apps instalados"`.
  - Com o Docker rodando, `"Medindo Docker"` é emitido antes de `diskUsage()`.
  - No fim: `disk` = o final, `diskFresh = true`, `diskProgress = nil`, e o relatório é salvo.
  - O `cleanDisk` continua chamando `analyzeDisk()` no fim. Isso também salva.
- **`MainWindow`:** ao entrar na aba, chama `openDiskTab()` em vez de `analyzeDisk()`.
- **`DiskView`:**
  - **Topo durante a análise:** mostra o texto de progresso no lugar de "analisado há X". O texto é `stage`, mais `"… \(done) de \(total)"` quando houver `total`, ou `"…"` sem total. Embaixo vai um `ProgressView(value: done, total: total)` fino de 2 pt quando houver total.
  - **Seções:** são desenhadas a partir de `store.disk`, inclusive no parcial. Quando o relatório for o salvo (`!store.diskFresh`), aparece `"de \(Format.age(...)) atrás"` como hoje.
  - **Botões:** "Limpar o seguro…" e "Limpar marcados…" usam `store.canClean`. O `.help` é `"Aguarde a análise terminar"` quando estão desabilitados.
  - **Seleção:** continua sendo reiniciada a cada novo `disk` (o parcial inclusive). Itens que já existiam mantêm a seleção, desde que ainda existam (escolha do Claude).

- [ ] **Step 1:** Implementar o store e rodar `swift build` (via `scripts/test.sh`) → compila e os testes passam.
- [ ] **Step 2:** Implementar `DiskView` e `MainWindow`.
- [ ] **Step 3:** `scripts/bundle.sh` → instala e reabre o app.
- [ ] **Step 4:** Commit `feat(app): disk progress and saved report`.

### Task 5: Leitura da GPU

**Files:** Create `Sources/MonitorCore/GPU/GPUSampler.swift`, `Sources/MonitorCore/GPU/GPUTracker.swift`; Test `Tests/MonitorCoreTests/GPUTests.swift`

**Interfaces:**
- Produces: `public struct GPUReading: Sendable, Equatable`, com:
  - `public var utilization: Double?`, que vem de `Device Utilization %`
  - `public var memoryInUse: UInt64?`, que vem de `In use system memory`
  - `public var perPid: [Int32: UInt64]`, o acumulado em ns por PID
- Produces: `public enum GPUSampler`, com:
  - `public static func read() -> GPUReading?`, que lê via IOKit (`IOServiceGetMatchingServices`, `IOServiceMatching("IOAccelerator")`):
    - A `PerformanceStatistics` sai do primeiro acelerador.
    - Os clientes são os filhos `AGXDeviceUserClient`, percorridos com `IORegistryEntryGetChildIterator` no `kIOServicePlane`.
    - Retorna `nil` só se não houver nenhum acelerador.
  - `static func parseStats(_ d: [String: Any]) -> (utilization: Double?, memoryInUse: UInt64?)`
  - `static func parseCreator(_ s: String) -> Int32?`, onde `"pid 588, WindowServer"` → 588 e lixo → `nil`.
  - `static func accumulate(_ clients: [(creator: String, appUsage: [[String: Any]])]) -> [Int32: UInt64]`, que soma `accumulatedGPUTime` de todos os itens de `AppUsage` e de todos os clientes do mesmo PID.
- Produces: `public struct GPUTracker: Sendable`, com:
  - `public init()`
  - `public mutating func update(_ perPid: [Int32: UInt64], starts: [Int32: Date], at now: Date) -> [Int32: Double]`, com as regras de % das Global Constraints. PIDs sem cliente de GPU ficam fora do dicionário; quem chama trata como 0.

- [ ] **Step 1: Failing tests**

```swift
@Test func parsesCreatorAndStats() {
    #expect(GPUSampler.parseCreator("pid 588, WindowServer") == 588 && GPUSampler.parseCreator("x") == nil)
    let s = GPUSampler.parseStats(["Device Utilization %": 79, "In use system memory": 1_975_123_968])
    #expect(s.utilization == 79 && s.memoryInUse == 1_975_123_968)
    #expect(GPUSampler.parseStats([:]).utilization == nil)
}
@Test func accumulateSumsClientsPerPid() {
    let r = GPUSampler.accumulate([
        ("pid 10, A", [["accumulatedGPUTime": 100], ["accumulatedGPUTime": 50]]),
        ("pid 10, A", [["accumulatedGPUTime": 25]]),
        ("pid 11, B", []),
    ])
    #expect(r == [10: 175, 11: 0])
}
@Test func trackerComputesPercentWithCapReuseAndNegative() {
    var t = GPUTracker()
    let s = Date(timeIntervalSince1970: 0), t0 = Date(timeIntervalSince1970: 100)
    #expect(t.update([1: 1_000_000_000], starts: [1: s], at: t0) == [1: 0])
    #expect(t.update([1: 1_500_000_000], starts: [1: s], at: t0.addingTimeInterval(1)) == [1: 50])
    #expect(t.update([1: 9_000_000_000], starts: [1: s], at: t0.addingTimeInterval(2)) == [1: 100])
    #expect(t.update([1: 1_000], starts: [1: s], at: t0.addingTimeInterval(3)) == [1: 0])
    #expect(t.update([1: 5_000_000_000], starts: [1: Date(timeIntervalSince1970: 50)], at: t0.addingTimeInterval(4)) == [1: 0])
}
@Test func realReadDoesNotCrash() {
    _ = GPUSampler.read()
}
```

- [ ] **Step 2:** `scripts/test.sh --filter GPUTests` → FAIL.
- [ ] **Step 3:** Implementar. As funções `parse`/`accumulate` recebem valores do IOKit como `[String: Any]`, convertendo `NSNumber` com segurança.
- [ ] **Step 4:** `scripts/test.sh --filter GPUTests` → PASS. Também rodar, uma vez, um probe temporário não commitado que imprime `GPUSampler.read()`, e colar a saída no relatório. Com o Mac em uso, `utilization` e `memoryInUse` devem vir preenchidos e `perPid` deve vir com o WindowServer.
- [ ] **Step 5:** Commit `feat(core): gpu sampler and tracker`.

### Task 6: GPU no modelo, ordenação, descontrolado e picos

**Files:** Modify `Sources/MonitorCore/Classify/Grouping.swift`, `Sources/MonitorCore/Model/SystemStats.swift`, `Sources/MonitorCore/Runaway/RunawayTracker.swift`, `Sources/MonitorCore/Peaks/PeakRecorder.swift`; Test `Tests/MonitorCoreTests/GPUModelTests.swift`

**Interfaces:**
- **`ProcessRow`:** ganha `public var gpuPercent: Double`. O init ganha `gpuPercent: Double = 0` ao final, para os usos existentes continuarem compilando.
- **`ProcessGroup`:** ganha `public var gpuPercent: Double`, a soma das linhas.
- Produces: `public enum GroupSort: Sendable, Hashable { case memory, cpu, gpu }`.
- **`Grouping.group`:** passa a ser `group(_ rows:, mode:, sort: GroupSort = .memory)`.
  - Ordena os grupos de forma decrescente pela métrica, com desempate por título.
  - As linhas dentro do grupo seguem a mesma métrica.
- **`SystemStats`:** ganha `public var gpuPercent: Double?` e `public var gpuMemoryBytes: UInt64?`, ambos com padrão `nil` no init.
- **`RunawayReason`:** ganha `case gpu(minutes: Int)`, com o texto `"GPU acima de 80% há \(minutes) min."`.
  - **Constantes:** `RunawayTracker.gpuThreshold = 80.0` e `gpuDuration: TimeInterval = 300`.
  - **Regras:** mesmas da CPU, mas a exceção de daemons de build não se aplica.
  - **Prioridade entre motivos:** CPU, depois GPU, depois memória.
- Produces: `public struct PeakGPUItem: Codable, Sendable, Equatable { public var title: String; public var percent: Double }`.
- **`PeakEpisode`:**
  - Ganha `public var topGPU: [PeakGPUItem]?`.
  - O init ganha `topGPU: [PeakGPUItem]? = nil` ao final.
  - `PeakRecorder.update` grava os 3 grupos com maior `gpuPercent > 0` nos mesmos pontos em que grava `top`.

- [ ] **Step 1: Failing tests**

```swift
@Test func groupsSortByGPU() {
    var a = ProcessRow.fixture(pid: 1, app: "/Applications/A.app", bytes: 900); a.gpuPercent = 5
    var b = ProcessRow.fixture(pid: 2, app: "/Applications/B.app", bytes: 100); b.gpuPercent = 60
    #expect(Grouping.group([a, b], mode: .byApp, sort: .gpu).map(\.title) == ["B", "A"])
    #expect(Grouping.group([a, b], mode: .byApp).map(\.title) == ["A", "B"])
}
@Test func gpuRunawayAfterFiveMinutes() {
    var t = RunawayTracker()
    var r = ProcessRow.fixture(pid: 7, app: "/Applications/Game.app"); r.gpuPercent = 95
    let t0 = Date(timeIntervalSince1970: 0)
    #expect(t.update([r], at: t0, myUid: 501, ignore: IgnoreList(defaults: .ephemeral())).isEmpty)
    let found = t.update([r], at: t0.addingTimeInterval(300), myUid: 501, ignore: IgnoreList(defaults: .ephemeral()))
    #expect(found.first?.reason == .gpu(minutes: 5))
}
@Test func peaksRecordTopGPUAndOldFilesDecode() throws {
    var rec = PeakRecorder(episodes: [])
    var row = ProcessRow.fixture(pid: 1, app: "/Applications/Game.app", bytes: 100); row.gpuPercent = 70
    _ = rec.update(stats: SystemStats(pressurePercent: 80, level: .warning, usedBytes: 1, totalBytes: 2, swapUsedBytes: 0, cpuPercent: 0),
                   groups: Grouping.group([row], mode: .byApp), at: Date(timeIntervalSince1970: 0))
    #expect(rec.episodes.first?.topGPU == [PeakGPUItem(title: "Game", percent: 70)])
    let old = #"[{"id":"00000000-0000-0000-0000-000000000000","start":0,"maxLevel":2,"maxPressure":80,"top":[]}]"#
    let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970
    #expect(try d.decode([PeakEpisode].self, from: Data(old.utf8)).first?.topGPU == nil)
}
```

- [ ] **Step 2:** `scripts/test.sh --filter GPUModelTests` → FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** `scripts/test.sh --filter GPUModelTests` → PASS, e a suíte inteira → PASS.
- [ ] **Step 5:** Commit `feat(core): gpu in rows, sorting, runaway and peaks`.

### Task 7: GPU no app

**Files:** Modify `Sources/Monitor/Store/MonitorStore.swift`, `Sources/Monitor/UI/MetricCards.swift`, `Sources/Monitor/UI/ProcessListView.swift`, `Sources/Monitor/UI/DetailPanel.swift`, `Sources/Monitor/UI/PopoverView.swift`, `Sources/Monitor/UI/PeaksView.swift`

**Interfaces:**
- Consumes: `GPUSampler.read`, `GPUTracker`, `ProcessRow.gpuPercent`, `GroupSort`, `SystemStats.gpuPercent`/`gpuMemoryBytes`, `PeakEpisode.topGPU`, `RunawayReason.gpu`.
- **Store, a cada ciclo:**
  - `GPUSampler.read()` roda no mesmo `Task.detached` do `ProcessSampler`.
  - O `GPUTracker` converte em % usando `startTime` dos snapshots.
  - As linhas recebem `gpuPercent`, e `stats` recebe `gpuPercent` e `gpuMemoryBytes`.
  - `history["gpu"]` com `RingBuffer(capacity: 120)`.
  - `var sort: GroupSort = .memory`, passado a `Grouping.group` em `groups`.
- **`MetricCards`:** card `"GPU"` depois de `"CPU"`.
  - Valor `"\(Int(gpu))%"` ou `"–"`, sparkline com a chave `"gpu"` e cor `Theme.accent`.
  - Embaixo do valor, `"\(Format.bytes(mem)) de memória de GPU"` em 10 pt `Theme.muted`, quando houver.
- **`ProcessListView`:**
  - Coluna `"GPU"` ao lado de `"CPU"`, com o mesmo formato de % que a CPU usa na lista, mas sem dividir pelos núcleos: `String(format: "%.1f%%")` com vírgula, como o `Format.cpu` faz.
  - Os cabeçalhos "MEMÓRIA", "CPU" e "GPU" viram botões que mudam `store.sort`. A coluna ativa fica em `Theme.text` com `"▾"`; as outras ficam em `Theme.muted`.
- **`DetailPanel`:** linha `field("GPU", …)` depois da CPU, na forma `"X,X% da GPU"`.
- **`PopoverView`:** depois de `"CPU X%"`, mostra `" · GPU X%"` quando houver.
- **`PeaksView`:** quando o episódio tem `topGPU` não vazio, mostra uma linha `"GPU: Game 70% · Chrome 12%"` em `Theme.muted`.
- O descontrolado por GPU aparece pela etiqueta e pela dica existentes, porque o texto vem de `RunawayReason`. Confirme que nenhum `switch` sobre `RunawayReason` no app ficou sem tratar o `.gpu`.

- [ ] **Step 1:** Implementar o store e depois a interface.
- [ ] **Step 2:** `scripts/test.sh` → toda a suíte PASS.
- [ ] **Step 3:** `scripts/bundle.sh` → instala e reabre o app.
- [ ] **Step 4:** Commit `feat(app): gpu card, column, sorting and peaks`.
