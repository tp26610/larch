// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Larch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Larch", path: "Sources/Larch"),
    ],
    swiftLanguageModes: [.v5]
)
