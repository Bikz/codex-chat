// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexMods",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexMods", targets: ["CodexMods"]),
    ],
    targets: [
        .target(name: "CodexMods"),
        .testTarget(name: "CodexModsTests", dependencies: ["CodexMods"]),
    ]
)
