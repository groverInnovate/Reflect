// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "LifeReplayCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "LifeReplayCore", targets: ["LifeReplayCore"])],
    targets: [.target(name: "LifeReplayCore"), .testTarget(name: "LifeReplayCoreTests", dependencies: ["LifeReplayCore"])]
)
