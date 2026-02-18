// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexChatCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexChatCore", targets: ["CodexChatCore"])
    ],
    targets: [
        .target(name: "CodexChatCore"),
        .testTarget(name: "CodexChatCoreTests", dependencies: ["CodexChatCore"])
    ]
)
