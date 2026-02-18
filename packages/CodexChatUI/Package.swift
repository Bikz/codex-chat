// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexChatUI",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexChatUI", targets: ["CodexChatUI"])
    ],
    dependencies: [
        .package(path: "../CodexChatCore"),
        .package(path: "../CodexMods"),
        .package(path: "../CodexKit")
    ],
    targets: [
        .target(
            name: "CodexChatUI",
            dependencies: ["CodexChatCore", "CodexMods", "CodexKit"]
        ),
        .testTarget(name: "CodexChatUITests", dependencies: ["CodexChatUI"])
    ]
)
