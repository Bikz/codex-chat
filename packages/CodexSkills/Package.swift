// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexSkills",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexSkills", targets: ["CodexSkills"]),
    ],
    targets: [
        .target(name: "CodexSkills"),
        .testTarget(name: "CodexSkillsTests", dependencies: ["CodexSkills"]),
    ]
)
