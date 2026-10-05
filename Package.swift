// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LifeReplay",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "LifeReplayCore", targets: ["LifeReplayCore"]),
        .executable(name: "LifeReplayMac", targets: ["LifeReplayMac"]),
    ],
    targets: [
        .target(
            name: "LifeReplayCore",
            path: "LifeReplayCore/Sources/LifeReplayCore"
        ),
        .executableTarget(
            name: "LifeReplayMac",
            dependencies: ["LifeReplayCore"],
            path: "LifeReplay-Mac/Sources/LifeReplayMac"
        ),
        .testTarget(
            name: "LifeReplayCoreTests",
            dependencies: ["LifeReplayCore"],
            path: "LifeReplayCore/Tests/LifeReplayCoreTests"
        ),
    ]
)
