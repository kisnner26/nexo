// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NexoCore",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
    products: [.library(name: "NexoCore", targets: ["NexoCore"])],
    targets: [
        .target(name: "NexoCore"),
        .executableTarget(name: "nexoprobe", dependencies: ["NexoCore"]),
        .testTarget(name: "NexoCoreTests", dependencies: ["NexoCore"]),
    ]
)
