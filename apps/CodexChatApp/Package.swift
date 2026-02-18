// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexChatApp",
    platforms: [.macOS(.v14)],
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
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.10.1"),
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
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
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
