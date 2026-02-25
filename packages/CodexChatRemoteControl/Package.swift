// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexChatRemoteControl",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexChatRemoteControl", targets: ["CodexChatRemoteControl"]),
    ],
    targets: [
        .target(name: "CodexChatRemoteControl"),
        .testTarget(
            name: "CodexChatRemoteControlTests",
            dependencies: ["CodexChatRemoteControl"]
        ),
    ]
)
