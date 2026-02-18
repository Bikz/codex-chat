// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexMemory",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexMemory", targets: ["CodexMemory"])
    ],
    targets: [
        .target(name: "CodexMemory"),
        .testTarget(name: "CodexMemoryTests", dependencies: ["CodexMemory"])
    ]
)
