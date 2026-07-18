// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Marker",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "Marker",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Marker",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "marker-cli",
            path: "Sources/MarkerCLI",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MarkerTests",
            dependencies: ["Marker"],
            path: "Tests/MarkerTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
