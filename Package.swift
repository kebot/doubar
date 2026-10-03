// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "doubar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "doubar",
            path: "Sources/doubar"
        ),
    ]
)
