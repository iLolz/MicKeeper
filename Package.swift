// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MicKeeper",
    defaultLocalization: "pt-BR",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MicKeeperCore", targets: ["MicKeeperCore"]),
        .executable(name: "mickeeper-cli", targets: ["mickeeper-cli"]),
        .executable(name: "MicKeeperApp", targets: ["MicKeeperApp"]),
    ],
    targets: [
        .target(
            name: "MicKeeperCore",
            resources: [.process("Resources")],
            linkerSettings: [.linkedFramework("CoreAudio")]
        ),
        .executableTarget(
            name: "mickeeper-cli",
            dependencies: ["MicKeeperCore"]
        ),
        .executableTarget(
            name: "MicKeeperApp",
            dependencies: ["MicKeeperCore"]
        ),
        .testTarget(
            name: "MicKeeperCoreTests",
            dependencies: ["MicKeeperCore"]
        ),
    ]
)
