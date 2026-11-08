// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KTVLyrics",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "KTVCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "KTVOverlayUI",
            dependencies: ["KTVCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "KTVLyrics",
            dependencies: ["KTVOverlayUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "KTVCoreTests",
            dependencies: ["KTVCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "KTVOverlayUITests",
            dependencies: ["KTVOverlayUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
