// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexChatInfra",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexChatInfra", targets: ["CodexChatInfra"])
    ],
    dependencies: [
        .package(path: "../CodexChatCore"),
        .package(path: "../CodexKit"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "CodexChatInfra",
            dependencies: [
                "CodexChatCore",
                "CodexKit",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "CodexChatInfraTests",
            dependencies: ["CodexChatInfra"]
        )
    ]
)
