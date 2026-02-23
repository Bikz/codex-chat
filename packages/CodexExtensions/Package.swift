// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexExtensions",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexExtensions", targets: ["CodexExtensions"]),
    ],
    dependencies: [
        .package(path: "../CodexProcess"),
    ],
    targets: [
        .target(
            name: "CodexExtensions",
            dependencies: ["CodexProcess"]
        ),
        .testTarget(name: "CodexExtensionsTests", dependencies: ["CodexExtensions"]),
    ]
)
