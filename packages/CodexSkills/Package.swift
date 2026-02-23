// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexSkills",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexSkills", targets: ["CodexSkills"]),
    ],
    dependencies: [
        .package(path: "../CodexProcess"),
    ],
    targets: [
        .target(
            name: "CodexSkills",
            dependencies: ["CodexProcess"]
        ),
        .testTarget(name: "CodexSkillsTests", dependencies: ["CodexSkills"]),
    ]
)
