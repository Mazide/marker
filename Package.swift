// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Marker",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Marker",
            path: "Sources/Marker",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
