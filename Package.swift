// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ditty",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Ditty",
            path: "Sources/Ditty",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
