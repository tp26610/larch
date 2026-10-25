// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyBrowser",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MyBrowser", path: "Sources/MyBrowser"),
    ],
    swiftLanguageModes: [.v5]
)
