import Foundation

public struct DiskReportStore: Sendable {
    public static let staleAfter: TimeInterval = 3600
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Monitor", isDirectory: true)
            .appendingPathComponent("disk-report.json")
    }

    public static func isStale(_ r: DiskReport, now: Date) -> Bool {
        now.timeIntervalSince(r.scannedAt) > staleAfter
    }

    public func load() -> DiskReport? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(DiskReport.self, from: data)
    }

    public func save(_ r: DiskReport) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(r) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
