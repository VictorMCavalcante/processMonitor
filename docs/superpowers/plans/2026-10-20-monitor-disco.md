# Monitor — aba Disco — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Aba "Disco" na janela principal que mostra o que ocupa espaço (seguro limpar, sobras de apps desinstalados, dados de apps) e limpa, mandando para a Lixeira, o que o Victor escolher.

**Architecture:** A regra fica no `MonitorCore`, em `Sources/MonitorCore/Disk/`, como funções puras sobre um protocolo `DiskFS` (sistema de arquivos falso nos testes) e um protocolo `AppIndex` (apps instalados):
- **Catálogo seguro:** o que se recria sozinho.
- **Detector de sobras:** pastas de apps que não estão mais instalados.
- **Resumo de dados de apps:** as maiores pastas de apps instalados.
- **Analisador:** junta os três com contagem disjunta.
- **Limpador:** Lixeira e prune do Docker.

O Docker ganha `diskUsage()` e `prune()` no `DockerClient` existente. O `MonitorStore` roda a análise sob demanda num `Task.detached`. A interface é uma nova `DiskView` seguindo o mockup.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Swift Testing (`scripts/test.sh`), Foundation (`FileManager`, `URLResourceValues`), CoreServices (`LSCopyApplicationURLsForBundleIdentifier`), CLI `docker`. Sem dependências novas.

**Spec:** `docs/superpowers/specs/2026-10-20-monitor-disco-design.md`. Mockup: `docs/design/mockup-disco.html`. Valem também os designs v1 e v2. Ler o spec inteiro antes da Task 1.

## Global Constraints

- macOS 14+, sem Xcode, sem dependências de terceiros, interface em pt-BR, tema `Theme` da v1, **zero comentários no código**, commits em inglês **sem coautoria e sem linhas de atribuição**.
- Nunca apagar nada sem confirmação. Tudo vai para a Lixeira (`FileManager.trashItem`); só o Docker é permanente, e a confirmação diz isso.
- Item só aparece com **≥ 50 MB** (`DiskRules.minItemBytes = 50 * 1_048_576`). Um app só entra em "Seus dados" com **≥ 1 GB** (`DiskRules.minAppDataBytes = 1_073_741_824`).
- Cada byte conta em uma categoria só, com prioridade Seguro > Sobras > Dados de apps. Hard links contam uma vez (deduplicação por inode na instância de `DiskFS`). Sistema e outros = usado − (Seguro + Sobras + Dados).
- A análise roda fora da thread principal, só ao abrir a aba pela primeira vez na sessão ou no ↻. Nunca roda no ciclo de 3 s/10 s.
- A análise nunca faz aparecer o pedido de permissão "acessar dados de outros apps". Sem Acesso Total ao Disco, pula `~/Library/Containers` e `~/Library/Group Containers` inteiros e liga `protectedSkipped`.
- Na dúvida sobre o dono, a pasta não é sobra. `com.apple.*`, pastas com cara de dados e pastas de dono desconhecido nunca aparecem como sobra.
- Volumes do Docker nunca entram.
- O cache cujo app dono está aberto aparece desmarcado com o aviso "feche o app primeiro". Na hora de limpar, o limpador verifica de novo e pula o item.

## Review Focus

- Um item que sumiu entre a análise e a limpeza (o Victor apagou à mão, o projeto foi movido) gera a falha "já não existe", e os outros itens continuam. (teste na Task 6)
- Symlinks dentro de `~`, como uma pasta de projeto apontando para outro volume ou um link circular: o `RealDiskFS` não segue symlinks, não conta duas vezes e termina. (teste na Task 1)
- Pasta parcialmente ilegível (permissão negada no meio da árvore) soma só o que conseguiu ler e nunca vira sobra quando a própria pasta não é listável. (teste na Task 3)
- App instalado fora de `/Applications` (`~/Applications`, subpasta como `/Applications/CrossOver/`) ou com o `.app` na Lixeira: a instalação é decidida pelo bundle id. Um app só na Lixeira conta como desinstalado. (teste na Task 3)
- Docker travado ou fechado no meio da limpeza: o prune falha em até 5 s com mensagem, e os itens da Lixeira são processados mesmo assim. (testes nas Tasks 5 e 6)

---

## File Structure

```
Sources/MonitorCore/Disk/DiskModel.swift        NEW: DiskCategory, DiskAction, DockerPrune, DiskItem, DiskReport, DiskRules
Sources/MonitorCore/Disk/DiskFS.swift           NEW: protocolo DiskFS + RealDiskFS (tamanho alocado, inode, sem symlink)
Sources/MonitorCore/Disk/SafeCatalog.swift      NEW: caches de dev + node_modules
Sources/MonitorCore/Disk/AppIndex.swift         NEW: protocolo AppIndex + SystemAppIndex
Sources/MonitorCore/Disk/LeftoverDetector.swift NEW: sobras confiáveis, "talvez sobra" e dono por bundle id
Sources/MonitorCore/Disk/DiskAnalyzer.swift     NEW: dados de apps, contagem disjunta, relatório
Sources/MonitorCore/Disk/DiskCleaner.swift      NEW: Lixeira + prune, CleanResult
Sources/MonitorCore/Docker/DockerClient.swift   MODIFY: diskUsage(), prune(_:)
Sources/Monitor/Store/MonitorStore.swift        MODIFY: disk, analyzeDisk(), cleanDisk(_:)
Sources/Monitor/UI/DiskView.swift               NEW: cards, barra, seções, rodapé
Sources/Monitor/UI/MainWindow.swift             MODIFY: aba .disk, PendingAction.cleanDisk
Tests/MonitorCoreTests/DiskFakes.swift          NEW: FakeDiskFS, FakeAppIndex
Tests/MonitorCoreTests/Disk*Tests.swift         um arquivo por arquivo novo do Core
```

---

### Task 1: Modelo e sistema de arquivos

**Files:** Create `Sources/MonitorCore/Disk/DiskModel.swift`, `Sources/MonitorCore/Disk/DiskFS.swift`, `Tests/MonitorCoreTests/DiskFakes.swift`; Test `Tests/MonitorCoreTests/DiskFSTests.swift`

**Interfaces:**
- Produces: `public enum DiskCategory: Sendable, Equatable { case safe, leftover, maybeLeftover, appData }`.
- Produces: `public enum DockerPrune: String, Sendable, Equatable { case danglingAndBuildCache, unusedImages }`.
- Produces: `public enum DiskAction: Sendable, Equatable { case trash([String]), docker(DockerPrune), none }`.
- Produces: `public struct DiskItem: Sendable, Identifiable, Equatable`, com:
  - Campos: `id: String`, `title: String`, `detail: String?`, `category: DiskCategory`, `bytes: UInt64`, `action: DiskAction`, `checkedByDefault: Bool`, `warning: String?`, `ownerBundlePrefix: String?`, `revealPath: String?`, `appPath: String?`, `modified: Date?`, `children: [DiskItem]`.
  - Um `init` com valores padrão para tudo depois de `bytes`: `action: .none`, `checkedByDefault: false`, demais `nil`/`[]`.
  - `public var leaves: [DiskItem]`: os próprios `children` quando houver, senão `[self]`.
- Produces: `public enum DiskRules { public static let minItemBytes: UInt64; public static let minAppDataBytes: UInt64 }`, com os valores das Global Constraints.
- Produces: `public protocol DiskFS: AnyObject`, com:
  - `func list(_ path: String) -> [String]?`: nomes; `nil` se não existir ou não for legível.
  - `func isDirectory(_ path: String) -> Bool`: `false` para symlink.
  - `func exists(_ path: String) -> Bool`
  - `func modified(_ path: String) -> Date?`
  - `func size(_ path: String) -> UInt64`: alocado, recursivo, sem seguir symlinks, cada inode uma vez por instância.
  - `func plistString(_ path: String, key: String) -> String?`
- Produces: `public final class RealDiskFS: DiskFS`. O `size` usa `FileManager.enumerator(at:includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileResourceIdentifierKey, .isSymbolicLinkKey])` e um `Set` dos identificadores já vistos. Erros de leitura são ignorados (`errorHandler` retorna `true`).
- Produces (teste): `final class FakeDiskFS: DiskFS`, montado com `files: [String: (bytes: UInt64, modified: Date)]` e `unreadable: Set<String>`. Diretórios são implícitos pelos prefixos dos caminhos. `plists: [String: [String: String]]`. Também `final class FakeAppIndex` (definido na Task 3, mesmo arquivo).

- [ ] **Step 1: Failing tests**

```swift
@Test func realSizeCountsHardLinkOnceAndSkipsSymlinks() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let a = dir.appendingPathComponent("a.bin")
    try Data(count: 1_000_000).write(to: a)
    try FileManager.default.linkItem(at: a, to: dir.appendingPathComponent("b.bin"))
    try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("loop"), withDestinationURL: dir)
    let fs = RealDiskFS()
    let size = fs.size(dir.path)
    #expect(size >= 1_000_000 && size < 1_200_000)
    #expect(!fs.isDirectory(dir.appendingPathComponent("loop").path))
}
@Test func fakeListsImplicitDirectories() {
    let fs = FakeDiskFS(files: ["/h/a/x": (10, .distantPast), "/h/a/y/z": (5, .distantPast)])
    #expect(fs.list("/h/a")?.sorted() == ["x", "y"])
    #expect(fs.size("/h/a") == 15 && fs.isDirectory("/h/a/y") && fs.list("/nope") == nil)
}
@Test func leavesFallBackToSelf() {
    let item = DiskItem(id: "a", title: "a", detail: nil, category: .safe, bytes: 1)
    #expect(item.leaves == [item])
}
```

- [ ] **Step 2:** `scripts/test.sh --filter DiskFSTests` → FAIL (tipos não existem).
- [ ] **Step 3:** Implementar os tipos acima.
- [ ] **Step 4:** `scripts/test.sh --filter DiskFSTests` → PASS.
- [ ] **Step 5:** Commit `feat(core): disk model and allocated-size file system`.

### Task 2: Catálogo seguro e node_modules

**Files:** Create `Sources/MonitorCore/Disk/SafeCatalog.swift`; Test `Tests/MonitorCoreTests/SafeCatalogTests.swift`

**Interfaces:**
- Consumes: `DiskFS`, `DiskItem`, `DiskRules` (Task 1).
- Produces: `public enum SafeCatalog { public static func scan(fs: DiskFS, home: String, runningBundleIDs: Set<String>, busyPaths: [String]) -> [DiskItem] }`.
- Catálogo fixo (caminhos relativos a `home`). Cada linha vira um item, desde que exista e tenha ≥ 50 MB; caminhos com o mesmo título somam num item só:

| title | paths | owner | marcado |
|---|---|---|---|
| npm cache | `.npm/_cacache` | — | sim |
| pnpm | `Library/Caches/pnpm`, `Library/pnpm/store` | — | sim |
| Yarn cache | `Library/Caches/Yarn` | — | sim |
| uv cache | `.cache/uv` | — | sim |
| Playwright browsers | `Library/Caches/ms-playwright`, `Library/Caches/ms-playwright-mcp` | — | sim |
| Homebrew cache | `Library/Caches/Homebrew` | — | sim |
| Xcode DerivedData | `Library/Developer/Xcode/DerivedData` | `com.apple.dt.Xcode` | sim |
| JetBrains cache | `Library/Caches/JetBrains` | `com.jetbrains` | sim |
| Gradle cache | `.gradle/caches` | — | sim |
| Hugging Face models | `.cache/huggingface` | — | **não**, warning `"baixar de novo é lento"` |

- **Dono aberto:** quando algum `runningBundleIDs` começa com o `owner`, o item vem `checkedByDefault = false`, com warning `"feche o app primeiro"` e `ownerBundlePrefix = owner`.
- **node_modules:**
  - **Busca:** a partir de `home`, sem entrar em `Library`, em nomes que começam com `.` nem em symlinks, com profundidade máxima de 6. A busca para ao achar `node_modules`; não procura dentro dele.
  - **Quem entra:** só pastas `node_modules` cujo pai tem `package.json`. Cada uma vira um filho com `title` = nome do projeto, `detail` = caminho relativo ao `home`, `modified` = o mais recente entre o `package.json` e a pasta do projeto, e `action = .trash([caminho])`.
  - **Agrupamento:** os filhos ficam ordenados por `modified` crescente (os antigos primeiro) dentro de um item `id: "node_modules"`, com `title "node_modules · N projetos"` e `bytes` = soma.
  - **Limite de tamanho:** o grupo só aparece com ≥ 50 MB no total. Os filhos não têm limite.
  - **Em uso:** um filho cujo projeto contém um caminho de `busyPaths` (o cwd é igual ao projeto ou está dentro dele) fica `checkedByDefault = false`, com warning `"em uso"`.
- Todos os itens: `category .safe`, `revealPath` = primeiro caminho existente.

- [ ] **Step 1: Failing tests**

```swift
let mb: UInt64 = 1_048_576
@Test func catalogMergesPathsAndSkipsSmall() {
    let fs = FakeDiskFS(files: ["/h/Library/Caches/ms-playwright/a": (60 * mb, .distantPast), "/h/Library/Caches/ms-playwright-mcp/b": (40 * mb, .distantPast), "/h/.npm/_cacache/c": (10 * mb, .distantPast)])
    let items = SafeCatalog.scan(fs: fs, home: "/h", runningBundleIDs: [], busyPaths: [])
    #expect(items.map(\.title) == ["Playwright browsers"] && items[0].bytes == 100 * mb && items[0].checkedByDefault)
    #expect(items[0].action == .trash(["/h/Library/Caches/ms-playwright", "/h/Library/Caches/ms-playwright-mcp"]))
}
@Test func huggingFaceUncheckedAndRunningOwnerWarned() {
    let fs = FakeDiskFS(files: ["/h/.cache/huggingface/m": (3000 * mb, .distantPast), "/h/Library/Caches/JetBrains/x": (2000 * mb, .distantPast)])
    let items = SafeCatalog.scan(fs: fs, home: "/h", runningBundleIDs: ["com.jetbrains.intellij"], busyPaths: [])
    let hf = items.first { $0.title == "Hugging Face models" }, jb = items.first { $0.title == "JetBrains cache" }
    #expect(hf?.checkedByDefault == false && hf?.warning == "baixar de novo é lento")
    #expect(jb?.checkedByDefault == false && jb?.warning == "feche o app primeiro" && jb?.ownerBundlePrefix == "com.jetbrains")
}
@Test func nodeModulesGroupedOldestFirstSkippingLibraryAndBusy() {
    let old = Date(timeIntervalSince1970: 1_000), new = Date(timeIntervalSince1970: 2_000)
    let fs = FakeDiskFS(files: [
        "/h/dev/a/package.json": (1, old), "/h/dev/a/node_modules/x": (40 * mb, old),
        "/h/dev/b/package.json": (1, new), "/h/dev/b/node_modules/x": (30 * mb, new),
        "/h/dev/c/node_modules/x": (90 * mb, old),
        "/h/Library/z/package.json": (1, old), "/h/Library/z/node_modules/x": (90 * mb, old),
    ])
    let g = SafeCatalog.scan(fs: fs, home: "/h", runningBundleIDs: [], busyPaths: ["/h/dev/b/src"]).first { $0.id == "node_modules" }
    #expect(g?.title == "node_modules · 2 projetos" && g?.bytes == 70 * mb)
    #expect(g?.children.map(\.title) == ["a", "b"] && g?.children[1].checkedByDefault == false && g?.children[1].warning == "em uso")
}
```

- [ ] **Step 2:** `scripts/test.sh --filter SafeCatalogTests` → FAIL.
- [ ] **Step 3:** Implementar `SafeCatalog.scan`.
- [ ] **Step 4:** `scripts/test.sh --filter SafeCatalogTests` → PASS.
- [ ] **Step 5:** Commit `feat(core): safe-to-clean catalog and node_modules finder`.

### Task 3: Apps instalados e sobras

**Files:** Create `Sources/MonitorCore/Disk/AppIndex.swift`, `Sources/MonitorCore/Disk/LeftoverDetector.swift`; Modify `Tests/MonitorCoreTests/DiskFakes.swift`; Test `Tests/MonitorCoreTests/LeftoverDetectorTests.swift`

**Interfaces:**
- Consumes: `DiskFS`, `DiskItem`, `DiskRules`.
- Produces: `public protocol AppIndex: AnyObject`, com:
  - `func appPath(bundleID: String) -> String?`: `nil` quando não instalado.
  - `func appPath(matchingName name: String) -> String?`
  - `func isKnownTool(_ name: String) -> Bool`
- Produces: `public final class SystemAppIndex: AppIndex`, com `init(home: String)`.
  - **Varredura no init:** `/Applications`, `~/Applications` e `/System/Applications`, com profundidade 2 (para subpastas como `CrossOver/`). Lê `CFBundleIdentifier` e `CFBundleName` do `Info.plist` de cada `.app`.
  - **Fallback por bundle id:** `LSCopyApplicationURLsForBundleIdentifier`, descartando URLs que contêm `/.Trash/` ou que não existem mais.
  - **Casamento por nome:** normaliza (minúsculas, só `[a-z0-9]`) e casa pelo nome do app, pelo `CFBundleName` ou pelo fabricante, que é o 2º componente do bundle id (`com.adobe.x` → `adobe`). Vale igualdade, ou um conter o outro com ≥ 4 caracteres.
  - **Ferramentas conhecidas:** nomes em `/opt/homebrew/Cellar`, `/opt/homebrew/Caskroom`, `/usr/local/Cellar`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin` e `~/.cargo/bin`.
- Produces: `public enum LeftoverDetector`, com:
  - `public static func ownerBundleID(folder name: String, in parent: String, fs: DiskFS) -> String?`:
    - Em `Containers`, lê o `MCMMetadataIdentifier` de `<pasta>/.com.apple.containermanagerd.metadata.plist`.
    - Em `Group Containers`, tira o `group.` ou o prefixo de time (10 caracteres alfanuméricos + `.`) e o `groups.`.
    - Em `Preferences`, tira o `.plist`.
    - Em qualquer lugar, só vale se o resultado tiver ≥ 3 componentes separados por `.`, cada um com `[A-Za-z0-9-]`.
  - `public static func detect(fs: DiskFS, home: String, apps: AppIndex, includeProtected: Bool) -> [DiskItem]`.
- **Lugares:** `Library/` + `Application Support`, `Caches`, `Containers`, `Group Containers`, `Preferences`, `Logs`, `Saved Application State`, `HTTPStorages` e `WebKit`. `Containers` e `Group Containers` só entram com `includeProtected`. O `Saved Application State` usa `<bundleid>.savedState`, então tira o sufixo.
- **Sobra confiável (`.leftover`):**
  - Tem `ownerBundleID`, que não começa com `com.apple.`, e para o qual `apps.appPath(bundleID:)` é `nil`.
  - Em `Group Containers`, vale como instalado qualquer app cujo bundle id seja prefixo do resto, ou o contrário.
  - Agrupa por bundle id: `id "leftover:<bundleid>"`, `title` = 3º componente do bundle id (ex.: `atlas`), ou o `CFBundleName` gravado no plist de Preferences quando ele existir. `detail` = os nomes das pastas-mãe, unidos por `" · "`. Ex.: `"Application Support · Caches · Preferences"`.
  - `action .trash(caminhos)`, `checkedByDefault false`, `revealPath` = o maior caminho.
- **Talvez sobra (`.maybeLeftover`):** só em `Application Support`, `Caches` e `Logs`, para pastas sem `ownerBundleID` que passam em todas as condições:
  - `list` não é `nil`.
  - Não começa com `.`.
  - Não contém `apple` (sem diferenciar maiúsculas).
  - Não está em `appleNames`.
  - Não contém nenhum de `dataLike`.
  - `apps.appPath(matchingName:)` é `nil`.
  - `!apps.isKnownTool(nome)`.

  Agrupa por nome normalizado: `id "maybe:<nome>"`, `title` = nome original, sempre desmarcado.
  - `appleNames = ["AddressBook","Animoji","CallHistoryDB","CallHistoryTransactions","CloudDocs","CrashReporter","DiskImages","Dock","FileProvider","icdd","iCloud","Knowledge","MobileSync","networkserviceproxy","SyncServices","Accounts","ControlCenter","DifferentialPrivacy","FaceTime","Quick Look","SpeechRecognitionCore","Spotlight","TrustedPeersHelper","AppStore","Mail","Safari","Photos","Siri","homed","identityservicesd","locationaccessstored","videosubscriptionsd"]`
  - `dataLike = ["mysql","postgres","mongo","redis","sqlite","database","backup","save","mobilesync","keychain"]`
- **Filtro de tamanho:** itens com menos de 50 MB somados ficam fora.
- **Ordem:** `.leftover` por bytes decrescentes, depois `.maybeLeftover` por bytes decrescentes.
- Produces (teste): `final class FakeAppIndex: AppIndex`, com `init(bundles: [String: String] = [:], names: [String: String] = [:], tools: Set<String> = [])`.

- [ ] **Step 1: Failing tests**

```swift
@Test func ownerFromContainerMetadataAndGroupPrefix() {
    let fs = FakeDiskFS(files: ["/h/Library/Containers/x/Data/a": (1, .distantPast)], plists: ["/h/Library/Containers/x/.com.apple.containermanagerd.metadata.plist": ["MCMMetadataIdentifier": "net.whatsapp.WhatsApp"]])
    #expect(LeftoverDetector.ownerBundleID(folder: "x", in: "/h/Library/Containers", fs: fs) == "net.whatsapp.WhatsApp")
    #expect(LeftoverDetector.ownerBundleID(folder: "6N38VWS5BX.ru.keepcoder.Telegram", in: "/h/Library/Group Containers", fs: fs) == "ru.keepcoder.Telegram")
    #expect(LeftoverDetector.ownerBundleID(folder: "22MMUN2RN5.lv", in: "/h/Library/Group Containers", fs: fs) == nil)
    #expect(LeftoverDetector.ownerBundleID(folder: "com.openai.atlas.plist", in: "/h/Library/Preferences", fs: fs) == "com.openai.atlas")
}
@Test func confidentLeftoverGroupsAcrossFolders() {
    let fs = FakeDiskFS(files: [
        "/h/Library/Application Support/com.openai.atlas/d": (800 * mb, .distantPast),
        "/h/Library/Caches/com.openai.atlas/c": (57 * mb, .distantPast),
        "/h/Library/Application Support/com.apple.wallpaper/w": (900 * mb, .distantPast),
        "/h/Library/Application Support/com.tinyspeck.slackmacgap/s": (900 * mb, .distantPast),
    ])
    let items = LeftoverDetector.detect(fs: fs, home: "/h", apps: FakeAppIndex(bundles: ["com.tinyspeck.slackmacgap": "/Applications/Slack.app"]), includeProtected: false)
    #expect(items.map(\.id) == ["leftover:com.openai.atlas"])
    #expect(items[0].bytes == 857 * mb && items[0].detail == "Application Support · Caches" && items[0].checkedByDefault == false)
}
@Test func maybeLeftoverExcludesDataInstalledToolsAndUnreadable() {
    let fs = FakeDiskFS(files: [
        "/h/Library/Application Support/Farming Simulator 2025/a": (199 * mb, .distantPast),
        "/h/Library/Application Support/MySQL/db": (490 * mb, .distantPast),
        "/h/Library/Application Support/Steam/g": (900 * mb, .distantPast),
        "/h/Library/Application Support/GitKrakenCLI/x": (177 * mb, .distantPast),
        "/h/Library/Application Support/Locked/x": (300 * mb, .distantPast),
        "/h/Library/Application Support/MobileSync/Backup/x": (900 * mb, .distantPast),
    ], unreadable: ["/h/Library/Application Support/Locked"])
    let apps = FakeAppIndex(names: ["steam": "/Applications/Steam.app"], tools: ["gitkrakencli"])
    let items = LeftoverDetector.detect(fs: fs, home: "/h", apps: apps, includeProtected: false)
    #expect(items.map(\.title) == ["Farming Simulator 2025"] && items[0].category == .maybeLeftover)
}
@Test func protectedFoldersSkippedWithoutAccess() {
    let fs = FakeDiskFS(files: ["/h/Library/Containers/x/Data/a": (900 * mb, .distantPast)], plists: ["/h/Library/Containers/x/.com.apple.containermanagerd.metadata.plist": ["MCMMetadataIdentifier": "com.gone.app"]])
    #expect(LeftoverDetector.detect(fs: fs, home: "/h", apps: FakeAppIndex(), includeProtected: false).isEmpty)
    #expect(LeftoverDetector.detect(fs: fs, home: "/h", apps: FakeAppIndex(), includeProtected: true).count == 1)
}
@Test func systemIndexIgnoresTrashedApps() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let app = home.appendingPathComponent(".Trash/Gone.app/Contents")
    try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    try (["CFBundleIdentifier": "com.example.gone.test", "CFBundleName": "Gone"] as NSDictionary).write(to: app.appendingPathComponent("Info.plist"))
    #expect(SystemAppIndex(home: home.path).appPath(bundleID: "com.example.gone.test") == nil)
}
```

- [ ] **Step 2:** `scripts/test.sh --filter LeftoverDetectorTests` → FAIL.
- [ ] **Step 3:** Implementar `AppIndex`, `SystemAppIndex`, `LeftoverDetector` e o `FakeAppIndex`.
- [ ] **Step 4:** `scripts/test.sh --filter LeftoverDetectorTests` → PASS.
- [ ] **Step 5:** Commit `feat(core): detect leftovers of uninstalled apps`.

### Task 4: Dados de apps e analisador

**Files:** Create `Sources/MonitorCore/Disk/DiskAnalyzer.swift`; Test `Tests/MonitorCoreTests/DiskAnalyzerTests.swift`

**Interfaces:**
- Consumes: `SafeCatalog.scan`, `LeftoverDetector.detect`, `LeftoverDetector.ownerBundleID`, `AppIndex`, `DiskFS`, `DockerDiskUsage` (Task 5; nesta task use a struct já declarada aqui, e a Task 5 só a preenche).
- Produces: `public struct DockerDiskUsage: Sendable, Equatable`, com `danglingAndBuildCache: UInt64`, `unusedImages: UInt64` e `unusedImageNames: [String]`.
- Produces: `public struct DiskReport: Sendable, Equatable`, com:
  - Campos: `total: UInt64`, `free: UInt64`, `items: [DiskItem]`, `protectedSkipped: Bool`, `dockerMeasured: Bool`, `scannedAt: Date`.
  - `func bytes(_ c: DiskCategory) -> UInt64`, onde `.leftover` também soma `.maybeLeftover`.
  - `var used: UInt64` = total − free.
  - `var systemOther: UInt64` = usado − (safe + leftover + appData), mínimo 0.
- Produces: `public enum DiskAnalyzer`, com:
  - `public static func analyze(fs: DiskFS, home: String, apps: AppIndex, volume: (total: UInt64, free: UInt64), docker: DockerDiskUsage?, runningBundleIDs: Set<String>, busyPaths: [String], now: Date) -> DiskReport`
  - `public static func hasFullDiskAccess(fs: DiskFS, home: String) -> Bool` = `fs.list(home + "/Library/Application Support/com.apple.TCC") != nil`
  - `public static func volume(home: String) -> (total: UInt64, free: UInt64)`, via `volumeTotalCapacityKey` e `volumeAvailableCapacityForImportantUsageKey`.
- **Ordem de contagem (disjunta):** Seguro primeiro, depois Sobras, depois Dados de apps. Quem vem depois desconta o que já foi contado: o tamanho de qualquer caminho já contado que esteja dentro do caminho que está sendo medido.
- **Docker:**
  - Com `docker` não nulo, entram em Seguro dois itens:
    - `id "docker:dangling"`, `title "Docker · imagens órfãs e build cache"`, `action .docker(.danglingAndBuildCache)`, marcado.
    - `id "docker:unused"`, `title "Docker · imagens sem nenhum container"`, `detail` = os nomes unidos por `", "`, warning `"o Docker baixa de novo quando você subir o projeto"`, `action .docker(.unusedImages)`, **desmarcado**.
    - Cada um só aparece com ≥ 50 MB.
  - Com `docker` nulo e a pasta `Library/Containers/com.docker.docker` existindo, entra um item `id "docker:closed"`, `title "Docker"`, `detail "abra o Docker para medir"`, `bytes 0`, `action .none`.
  - Os bytes recuperáveis do Docker são descontados do tamanho do app Docker em Dados.
- **Dados de apps:**
  - **Pastas medidas:** as filhas de `Library/Application Support` e, com acesso total, de `Containers` e `Group Containers`.
  - **Dono de cada pasta:** quem `ownerBundleID` aponta (precisa estar instalado) ou, em `Application Support`, quem `appPath(matchingName:)` aponta.
  - **Itens:** soma por `appPath`, com `id "app:<appPath>"`, `title` = nome do `.app` sem extensão, `appPath` preenchido e `action .none`. Só entram apps com ≥ 1 GB.
  - **Wallpapers:** `Application Support/com.apple.wallpaper` com ≥ 1 GB vira o item `id "wallpaper"`, `title "Wallpapers dinâmicos"`, `detail "remova em Ajustes › Papel de Parede"`.
  - Ordenados por bytes decrescentes.
- **Itens no relatório:** na ordem safe, leftover, maybeLeftover, appData. Dentro de safe: por bytes decrescentes, com o `docker:closed` no fim.
- `protectedSkipped = !hasFullDiskAccess`, que também vai como `includeProtected` para o detector.

- [ ] **Step 1: Failing tests**

```swift
@Test func categoriesAreDisjointAndSystemOtherIsRemainder() {
    let fs = FakeDiskFS(files: [
        "/h/Library/Application Support/com.apple.TCC/x": (1, .distantPast),
        "/h/Library/Application Support/Steam/games": (75_000 * mb, .distantPast),
        "/h/Library/Containers/d/Data/v": (21_000 * mb, .distantPast),
        "/h/.npm/_cacache/x": (4_200 * mb, .distantPast),
    ], plists: ["/h/Library/Containers/d/.com.apple.containermanagerd.metadata.plist": ["MCMMetadataIdentifier": "com.docker.docker"]])
    let apps = FakeAppIndex(bundles: ["com.docker.docker": "/Applications/Docker.app"], names: ["steam": "/Applications/Steam.app"])
    let r = DiskAnalyzer.analyze(fs: fs, home: "/h", apps: apps, volume: (460_000 * mb, 73_000 * mb),
                                 docker: DockerDiskUsage(danglingAndBuildCache: 6_000 * mb, unusedImages: 9_000 * mb, unusedImageNames: ["wra-api"]),
                                 runningBundleIDs: [], busyPaths: [], now: .distantPast)
    #expect(r.bytes(.safe) == 4_200 * mb + 15_000 * mb)
    #expect(r.items.first { $0.id == "app:/Applications/Docker.app" }?.bytes == 6_000 * mb)
    #expect(r.items.first { $0.id == "docker:unused" }?.checkedByDefault == false)
    #expect(r.systemOther == r.used - r.bytes(.safe) - r.bytes(.leftover) - r.bytes(.appData) && !r.protectedSkipped)
}
@Test func dockerClosedShowsPlaceholderAndNoAccessSetsFlag() {
    let fs = FakeDiskFS(files: ["/h/Library/Containers/com.docker.docker/Data/x": (21_000 * mb, .distantPast)])
    let r = DiskAnalyzer.analyze(fs: fs, home: "/h", apps: FakeAppIndex(), volume: (100, 10), docker: nil, runningBundleIDs: [], busyPaths: [], now: .distantPast)
    #expect(r.protectedSkipped && r.items.contains { $0.id == "docker:closed" && $0.detail == "abra o Docker para medir" })
}
@Test func safeCacheInsideAppFolderIsNotCountedTwice() {
    let fs = FakeDiskFS(files: ["/h/Library/Caches/JetBrains/x": (2_000 * mb, .distantPast)])
    let r = DiskAnalyzer.analyze(fs: fs, home: "/h", apps: FakeAppIndex(), volume: (10_000 * mb, 1_000 * mb), docker: nil, runningBundleIDs: [], busyPaths: [], now: .distantPast)
    #expect(r.bytes(.safe) == 2_000 * mb && r.bytes(.leftover) == 0 && r.bytes(.appData) == 0)
}
```

- [ ] **Step 2:** `scripts/test.sh --filter DiskAnalyzerTests` → FAIL.
- [ ] **Step 3:** Implementar `DiskAnalyzer`, `DiskReport` e `DockerDiskUsage`.
- [ ] **Step 4:** `scripts/test.sh --filter DiskAnalyzerTests` → PASS.
- [ ] **Step 5:** Commit `feat(core): disk analyzer with disjoint categories`.

### Task 5: Docker — uso de disco e prune

**Files:** Modify `Sources/MonitorCore/Docker/DockerClient.swift`; Test `Tests/MonitorCoreTests/DockerClientTests.swift`

**Interfaces:**
- Consumes: `DockerDiskUsage`, `DockerPrune`; os existentes `CommandRunner`, `command(_:timeout:)` e `parseMemory`.
- Produces: `public func diskUsage() -> DockerDiskUsage?`: `nil` se qualquer comando falhar.
  - **Build cache:** `docker system df --format '{{json .}}'`. Na linha `"Type":"Build Cache"`, o campo `Reclaimable` (ex.: `"2.1GB (100%)"`) vai para o parser de tamanho, só a parte antes do espaço. Unidades decimais: kB, MB, GB, B.
  - **Imagens órfãs:** `docker images -f dangling=true --format '{{json .}}'`, somando o `Size` de cada uma.
  - **Imagens sem uso:** `docker images --format '{{json .}}'` menos as imagens referenciadas por `docker ps -a --format '{{.Image}}'` (casando por `Repository:Tag` ou `ID`), sem contar as órfãs. A soma do `Size` vai para `unusedImages`, e os nomes `Repository:Tag` vão para `unusedImageNames`.
  - `danglingAndBuildCache` = órfãs + build cache.
- Produces: `public func prune(_ kind: DockerPrune) -> String?`, que retorna o erro em pt-BR ou `nil`:
  - `.danglingAndBuildCache` roda `image prune -f` e depois `builder prune -f`.
  - `.unusedImages` roda `image prune -a -f`.
  - Timeout de 120 s por comando. Sem resposta, retorna `"O Docker não respondeu a tempo."`. Com status ≠ 0, retorna `"Não foi possível limpar o Docker."`. Sem executável, retorna `"Docker não encontrado."`.
- Produces: `static func parseDecimalSize(_ s: String) -> UInt64`, onde `"2.1GB (100%)"` → 2_100_000_000, `"512MB"` → 512_000_000, e lixo → 0.

- [ ] **Step 1: Failing tests**

```swift
@Test func parsesDecimalSizes() {
    #expect(DockerClient.parseDecimalSize("2.1GB (100%)") == 2_100_000_000)
    #expect(DockerClient.parseDecimalSize("512MB") == 512_000_000 && DockerClient.parseDecimalSize("x") == 0)
}
@Test func diskUsageSplitsDanglingAndUnused() {
    struct Fake: CommandRunner {
        func run(_ p: String, _ a: [String], timeout: TimeInterval) -> (status: Int32, output: String)? {
            switch a.prefix(3).joined(separator: " ") {
            case let s where s.hasPrefix("system df"): (0, #"{"Type":"Build Cache","Reclaimable":"1GB (100%)"}"#)
            case let s where s.hasPrefix("images -f dangling=true"): (0, #"{"ID":"d1","Repository":"<none>","Tag":"<none>","Size":"500MB"}"#)
            case let s where s.hasPrefix("images --format"): (0, #"{"ID":"d1","Repository":"<none>","Tag":"<none>","Size":"500MB"}"# + "\n" + #"{"ID":"i1","Repository":"postgres","Tag":"16","Size":"400MB"}"# + "\n" + #"{"ID":"i2","Repository":"wra-api","Tag":"latest","Size":"2GB"}"#)
            case let s where s.hasPrefix("ps -a"): (0, "postgres:16\n")
            default: nil
            }
        }
    }
    let u = DockerClient(runner: Fake(), paths: ["/usr/bin/true"]).diskUsage()
    #expect(u == DockerDiskUsage(danglingAndBuildCache: 1_500_000_000, unusedImages: 2_000_000_000, unusedImageNames: ["wra-api:latest"]))
}
@Test func pruneReportsHangAndMissingDocker() {
    struct Dead: CommandRunner { func run(_ p: String, _ a: [String], timeout: TimeInterval) -> (status: Int32, output: String)? { nil } }
    #expect(DockerClient(runner: Dead(), paths: ["/usr/bin/true"]).prune(.unusedImages) == "O Docker não respondeu a tempo.")
    #expect(DockerClient(runner: Dead(), paths: ["/nope"]).prune(.unusedImages) == "Docker não encontrado.")
    #expect(DockerClient(runner: Dead(), paths: ["/usr/bin/true"]).diskUsage() == nil)
}
```

- [ ] **Step 2:** `scripts/test.sh --filter DockerClientTests` → FAIL nos três testes novos.
- [ ] **Step 3:** Implementar no `DockerClient`.
- [ ] **Step 4:** `scripts/test.sh --filter DockerClientTests` → PASS (os antigos continuam verdes).
- [ ] **Step 5:** Commit `feat(core): docker disk usage and prune`.

### Task 6: Limpador

**Files:** Create `Sources/MonitorCore/Disk/DiskCleaner.swift`; Test `Tests/MonitorCoreTests/DiskCleanerTests.swift`

**Interfaces:**
- Consumes: `DiskItem`, `DiskAction`, `DockerPrune`.
- Produces: `public struct CleanResult: Sendable, Equatable`, com `trashedBytes: UInt64`, `dockerBytes: UInt64` e `failures: [String]`. Cada falha vem no formato `"<title>: <motivo>"`.
- Produces: `public enum DiskCleaner { public static func clean(_ items: [DiskItem], runningBundleIDs: Set<String>, exists: (String) -> Bool, trash: (String) throws -> Void, docker: (DockerPrune) -> String?) -> CleanResult }`, que recebe os itens folha selecionados.
- **Regras por item:**
  - Item com `ownerBundlePrefix` cujo dono está rodando: falha `"feche o app primeiro"` e nada é feito.
  - `.trash(paths)`:
    - Os caminhos inexistentes são pulados.
    - Se todos forem inexistentes, falha `"já não existe"`.
    - Se o `trash` lançar erro, falha com `"não foi possível mover para a Lixeira"`, e os demais caminhos e itens continuam.
    - Os `bytes` do item só somam em `trashedBytes` se pelo menos um caminho foi para a Lixeira.
  - `.docker(kind)`: uma mensagem de erro vira falha, e sem erro os bytes somam em `dockerBytes`.
  - `.none`: ignorado.
- **Ordem:** todos os itens não-Docker, na ordem recebida, antes dos `.docker`, para que um Docker travado não atrase a Lixeira. `failures` segue essa mesma ordem de processamento.

- [ ] **Step 1: Failing tests**

```swift
@Test func cleanerContinuesPastFailuresAndReportsThem() {
    let items = [
        DiskItem(id: "a", title: "npm cache", detail: nil, category: .safe, bytes: 10, action: .trash(["/a"]), checkedByDefault: true),
        DiskItem(id: "b", title: "sumiu", detail: nil, category: .safe, bytes: 20, action: .trash(["/b"]), checkedByDefault: true),
        DiskItem(id: "c", title: "travado", detail: nil, category: .safe, bytes: 30, action: .trash(["/c"]), checkedByDefault: true),
        DiskItem(id: "d", title: "Docker · imagens órfãs e build cache", detail: nil, category: .safe, bytes: 40, action: .docker(.danglingAndBuildCache), checkedByDefault: true),
        DiskItem(id: "e", title: "JetBrains cache", detail: nil, category: .safe, bytes: 50, action: .trash(["/e"]), checkedByDefault: true, ownerBundlePrefix: "com.jetbrains"),
    ]
    struct Locked: Error {}
    var trashed: [String] = []
    let r = DiskCleaner.clean(items, runningBundleIDs: ["com.jetbrains.intellij"], exists: { $0 != "/b" },
                              trash: { if $0 == "/c" { throw Locked() }; trashed.append($0) },
                              docker: { _ in "O Docker não respondeu a tempo." })
    #expect(trashed == ["/a"] && r.trashedBytes == 10 && r.dockerBytes == 0)
    #expect(r.failures == ["sumiu: já não existe", "travado: não foi possível mover para a Lixeira", "JetBrains cache: feche o app primeiro", "Docker · imagens órfãs e build cache: O Docker não respondeu a tempo."])
}
```

- [ ] **Step 2:** `scripts/test.sh --filter DiskCleanerTests` → FAIL.
- [ ] **Step 3:** Implementar `DiskCleaner.clean`.
- [ ] **Step 4:** `scripts/test.sh --filter DiskCleanerTests` → PASS.
- [ ] **Step 5:** Commit `feat(core): disk cleaner via trash and docker prune`.

### Task 7: Store, aba Disco e confirmação

**Files:** Create `Sources/Monitor/UI/DiskView.swift`; Modify `Sources/Monitor/Store/MonitorStore.swift`, `Sources/Monitor/UI/MainWindow.swift`

**Interfaces:**
- Consumes: `DiskAnalyzer.analyze`, `DiskAnalyzer.volume`, `RealDiskFS`, `SystemAppIndex`, `DockerClient.diskUsage/prune`, `DiskCleaner.clean`, `DiskReport`, `CleanResult`, `Format.bytes`, `Format.age`.
- **`MonitorStore` ganha:**
  - `var disk: DiskReport?` e `var diskScanning = false`.
  - `func analyzeDisk() async`, que não faz nada se já estiver rodando:
    - `runningBundleIDs` vem de `NSWorkspace.shared.runningApplications`.
    - `busyPaths` são os `cwd` de `rows` com kind `.devServer`, `.claudeSession` ou `.shell`.
    - O `docker` só é medido com `dockerRunning`.
    - A análise roda em `Task.detached(priority: .utility)` com um `RealDiskFS()` novo a cada análise, para a deduplicação por inode não vazar entre elas.
  - `func cleanDisk(_ leaves: [DiskItem]) async -> CleanResult`: roda `DiskCleaner.clean` em `Task.detached`, com `trash` = `FileManager.default.trashItem(at:resultingItemURL:)`. Depois chama `analyzeDisk()` e põe em `lastMessage` o texto `"<X> na Lixeira"`, mais as falhas unidas por `"; "` quando houver.
- **`MainWindow`:**
  - **Aba:** `WindowTab.disk`, com a tag `Text("Disco")` depois de "Picos". A largura do picker sobe 80.
  - **Análise:** ao entrar na aba sem `disk` já calculado, chama `analyzeDisk()`.
  - **Confirmação:** `PendingAction.cleanDisk([DiskItem])`, com título `"Limpar \(Format.bytes(total))?"` e botão `"Limpar"` com role `.destructive`.
  - **Texto da confirmação:** a lista dos títulos, uma por linha, seguida de `"Vai para a Lixeira. Esvazie a Lixeira para liberar o espaço."`. Se algum item for `.docker`, entra também `"As imagens do Docker são apagadas na hora, sem Lixeira."`.
- **`DiskView(store:, onClean: ([DiskItem]) -> Void)`**, seguindo `docs/design/mockup-disco.html`:
  - **Topo:**
    - "analisado há X" via `Format.age`, com o botão ↻ (`analyzeDisk`).
    - `ProgressView` pequeno enquanto `diskScanning`. O relatório anterior continua visível.
  - **Cards:** quatro, no visual dos `MetricCards`:
    - "Livre": `free`, "de `total`".
    - "Seguro limpar": `bytes(.safe)`, com o botão "Limpar o seguro…". O botão chama `onClean` com as folhas `.safe` que têm `checkedByDefault`.
    - "Sobras de apps": `bytes(.leftover)` e "N apps removidos".
    - "Dados de apps": `bytes(.appData)` e os 2 maiores títulos.

    Clicar num card rola até a seção dele com `ScrollViewReader`.
  - **Barra do disco:** segmentos proporcionais a `systemOther`, safe, leftover, appData e free. Cores: `Theme.muted2`, `Theme.ok`, `Theme.warn`, `Theme.accent` e `Theme.line`.
  - **Seções:**
    - **"Seguro: se recria sozinho"**, em `Theme.ok`.
    - **"Sobras de apps desinstalados"**, em `Theme.warn`, com a sublista "Talvez sobra · confira antes" para as `.maybeLeftover`.
    - **"Seus dados: só informativo"**, em `Theme.accent`.

    Cada seção mostra o total no cabeçalho e some quando está vazia.
  - **Linhas:** checkbox (menos em appData e `.none`), título, `detail`/`warning` em `Theme.muted` e tamanho.
    - Botão "Revelar" (`NSWorkspace.shared.activateFileViewerSelecting`) quando houver `revealPath`.
    - Botão "Abrir app" (`NSWorkspace.shared.open`) quando houver `appPath`.
  - **node_modules:** a linha tem "Ver ▸", que expande os filhos. O checkbox do pai marca e desmarca todos os filhos.
  - **Seleção:** `@State var selected: Set<String>` com os ids das folhas, iniciado com as folhas que têm `checkedByDefault` sempre que chega um `disk` novo.
  - **Rodapé:** "N itens marcados · `<total>` · vai para a Lixeira" e o botão "Limpar marcados…" (`onClean` com as folhas selecionadas), desabilitado com 0.
  - **Sem acesso total:** com `protectedSkipped`, aparece uma linha discreta: "Algumas pastas de apps não foram lidas. Dê Acesso Total ao Disco ao Monitor em Ajustes › Privacidade e Segurança para ver tudo." e o botão "Abrir Ajustes" (`x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`).

- [ ] **Step 1:** Implementar a parte do store e `swift build` (via `scripts/bundle.sh` ou `swift build`) → compila.
- [ ] **Step 2:** Implementar `DiskView` e a aba no `MainWindow`.
- [ ] **Step 3:** `scripts/test.sh` → toda a suíte PASS.
- [ ] **Step 4:** `scripts/bundle.sh` e verificação manual com o app aberto:
  - A aba Disco aparece e a análise termina sem travar a janela.
  - Os números batem aproximadamente com `du -sh ~/.npm ~/.cache/uv ~/Library/Caches/ms-playwright*`.
  - O ChatGPT Atlas aparece em Sobras. Farming Simulator, Adobe e LGHUB aparecem em "Talvez sobra".
  - MySQL não aparece em lugar nenhum como sobra.
  - Steam e WhatsApp aparecem em "Seus dados".
  - Com o Docker fechado, aparece "abra o Docker para medir".
  - Marcar só um `node_modules` de teste, criado com `mkdir -p ~/tmp-disco/x && cd ~/tmp-disco/x && echo {} > package.json && mkdir node_modules && mkfile 60m node_modules/f`, e limpar faz ele aparecer na Lixeira. A mensagem "60 MB na Lixeira" aparece.
- [ ] **Step 5:** Commit `feat(app): disk tab with cleanup`.
