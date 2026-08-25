// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Volume",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Volume",
            path: "Sources/Volume",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
