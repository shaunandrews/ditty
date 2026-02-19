// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MusicController",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MusicController",
            path: "Sources/MusicController"
        )
    ]
)
