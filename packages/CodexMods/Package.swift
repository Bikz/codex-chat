// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexMods",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexMods", targets: ["CodexMods"]),
    ],
    dependencies: [
        .package(path: "../CodexProcess"),
    ],
    targets: [
        .target(
            name: "CodexMods",
            dependencies: ["CodexProcess"]
        ),
        .testTarget(
            name: "CodexModsTests",
            dependencies: ["CodexMods"],
            resources: [
                .process("Fixtures"),
            ]
        ),
    ]
)
