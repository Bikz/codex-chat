// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexChatApp",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexChatShared", targets: ["CodexChatShared"]),
        .executable(name: "CodexChatCLI", targets: ["CodexChatCLI"]),
        .executable(name: "codexchat-action", targets: ["CodexChatActionCLI"]),
        .executable(name: "CodexChatApp", targets: ["CodexChatCLI"]),
        .executable(name: "CodexChatDesktopFallback", targets: ["CodexChatAppExecutable"]),
    ],
    dependencies: [
        .package(path: "../../packages/CodexChatCore"),
        .package(path: "../../packages/CodexChatInfra"),
        .package(path: "../../packages/CodexChatUI"),
        .package(path: "../../packages/CodexKit"),
        .package(path: "../../packages/CodexSkills"),
        .package(path: "../../packages/CodexMemory"),
        .package(path: "../../packages/CodexMods"),
        .package(path: "../../packages/CodexExtensions"),
        .package(path: "../../packages/CodexComputerActions"),
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.10.1"),
    ],
    targets: [
        .target(
            name: "CodexChatShared",
            dependencies: [
                "CodexChatCore",
                "CodexChatInfra",
                "CodexChatUI",
                "CodexKit",
                "CodexSkills",
                "CodexMemory",
                "CodexMods",
                "CodexExtensions",
                "CodexComputerActions",
                .product(name: "TOMLKit", package: "TOMLKit"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Sources/CodexChatApp",
            resources: [
                .copy("Resources"),
            ]
        ),
        .executableTarget(
            name: "CodexChatCLI",
            dependencies: ["CodexChatShared"],
            path: "Sources/CodexChatCLI"
        ),
        .executableTarget(
            name: "CodexChatActionCLI",
            dependencies: [],
            path: "Sources/CodexChatActionCLI"
        ),
        .executableTarget(
            name: "CodexChatAppExecutable",
            dependencies: ["CodexChatShared"],
            path: "Sources/CodexChatAppExecutable"
        ),
        .testTarget(
            name: "CodexChatAppTests",
            dependencies: ["CodexChatShared"],
            resources: [
                .process("Fixtures"),
            ]
        ),
    ]
)
