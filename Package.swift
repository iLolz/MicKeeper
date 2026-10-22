// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MicPriority",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MicPriorityCore", targets: ["MicPriorityCore"]),
        .executable(name: "micpriority-cli", targets: ["micpriority-cli"]),
        .executable(name: "MicPriorityApp", targets: ["MicPriorityApp"]),
    ],
    targets: [
        .target(
            name: "MicPriorityCore",
            linkerSettings: [.linkedFramework("CoreAudio")]
        ),
        .executableTarget(
            name: "micpriority-cli",
            dependencies: ["MicPriorityCore"]
        ),
        .executableTarget(
            name: "MicPriorityApp",
            dependencies: ["MicPriorityCore"]
        ),
        .testTarget(
            name: "MicPriorityCoreTests",
            dependencies: ["MicPriorityCore"]
        ),
    ]
)
