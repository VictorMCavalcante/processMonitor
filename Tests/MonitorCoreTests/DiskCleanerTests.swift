import Testing
@testable import MonitorCore

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
