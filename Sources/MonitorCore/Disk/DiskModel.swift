import Foundation

public enum DiskCategory: Sendable, Equatable { case safe, leftover, maybeLeftover, appData }

public enum DockerPrune: String, Sendable, Equatable { case danglingAndBuildCache, unusedImages }

public enum DiskAction: Sendable, Equatable {
    case trash([String])
    case docker(DockerPrune)
    case none
}

public struct DiskItem: Sendable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var detail: String?
    public var category: DiskCategory
    public var bytes: UInt64
    public var action: DiskAction
    public var checkedByDefault: Bool
    public var warning: String?
    public var ownerBundlePrefix: String?
    public var revealPath: String?
    public var appPath: String?
    public var modified: Date?
    public var children: [DiskItem]

    public init(id: String, title: String, detail: String?, category: DiskCategory, bytes: UInt64,
                action: DiskAction = .none, checkedByDefault: Bool = false, warning: String? = nil,
                ownerBundlePrefix: String? = nil, revealPath: String? = nil, appPath: String? = nil,
                modified: Date? = nil, children: [DiskItem] = []) {
        self.id = id
        self.title = title
        self.detail = detail
        self.category = category
        self.bytes = bytes
        self.action = action
        self.checkedByDefault = checkedByDefault
        self.warning = warning
        self.ownerBundlePrefix = ownerBundlePrefix
        self.revealPath = revealPath
        self.appPath = appPath
        self.modified = modified
        self.children = children
    }

    public var leaves: [DiskItem] { children.isEmpty ? [self] : children }
}

public enum DiskRules {
    public static let minItemBytes: UInt64 = 50 * 1_048_576
    public static let minAppDataBytes: UInt64 = 1_073_741_824
}
