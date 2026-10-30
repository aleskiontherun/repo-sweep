// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RepoSweep",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "RepoSweep", targets: ["RepoSweep"]),
    ],
    targets: [
        .target(name: "RepoSweepCore"),
        .executableTarget(name: "RepoSweep", dependencies: ["RepoSweepCore"]),
        .testTarget(name: "RepoSweepCoreTests", dependencies: ["RepoSweepCore"]),
    ]
)
