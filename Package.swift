// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Monitor",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MonitorCore"),
        .executableTarget(name: "Monitor", dependencies: ["MonitorCore"]),
        .testTarget(name: "MonitorCoreTests", dependencies: ["MonitorCore"]),
    ]
)
