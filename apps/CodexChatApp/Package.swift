// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexChatApp",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodexChatApp", targets: ["CodexChatApp"]),
    ],
    dependencies: [
        .package(path: "../../packages/CodexChatCore"),
        .package(path: "../../packages/CodexChatInfra"),
        .package(path: "../../packages/CodexChatUI"),
        .package(path: "../../packages/CodexKit"),
        .package(path: "../../packages/CodexSkills"),
        .package(path: "../../packages/CodexMemory"),
        .package(path: "../../packages/CodexMods"),
    ],
    targets: [
        .executableTarget(
            name: "CodexChatApp",
            dependencies: [
                "CodexChatCore",
                "CodexChatInfra",
                "CodexChatUI",
                "CodexKit",
                "CodexSkills",
                "CodexMemory",
                "CodexMods",
            ],
            resources: [
                .copy("Resources"),
            ]
        ),
        .testTarget(
            name: "CodexChatAppTests",
            dependencies: ["CodexChatApp"],
            resources: [
                .process("Fixtures"),
            ]
        ),
    ]
)
