// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexKit", targets: ["CodexKit"]),
    ],
    targets: [
        .target(name: "CodexKit"),
        .testTarget(name: "CodexKitTests", dependencies: ["CodexKit"]),
    ]
)
