// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexComputerActions",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexComputerActions", targets: ["CodexComputerActions"]),
    ],
    dependencies: [
        .package(path: "../CodexChatCore"),
    ],
    targets: [
        .target(
            name: "CodexComputerActions",
            dependencies: ["CodexChatCore"]
        ),
        .testTarget(
            name: "CodexComputerActionsTests",
            dependencies: ["CodexComputerActions"]
        ),
    ]
)
