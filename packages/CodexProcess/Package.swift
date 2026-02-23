// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexProcess",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexProcess", targets: ["CodexProcess"]),
    ],
    targets: [
        .target(name: "CodexProcess"),
        .testTarget(name: "CodexProcessTests", dependencies: ["CodexProcess"]),
    ]
)
