// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MusicController",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "MusicController",
            path: "Sources/MusicController",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
