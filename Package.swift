// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacNetwork",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "MacNetwork", targets: ["MacNetwork"]),
        // Library product so Xcode makes a scheme for it: SwiftUI previews do not run in executable targets.
        .library(name: "MacNetworkUI", targets: ["MacNetworkUI"]),
    ],
    targets: [
        .target(name: "MacNetworkCore"),
        .target(name: "MacNetworkUI", dependencies: ["MacNetworkCore"]),
        .executableTarget(name: "MacNetwork", dependencies: ["MacNetworkUI"]),
        .testTarget(name: "MacNetworkCoreTests", dependencies: ["MacNetworkCore"]),
    ]
)
