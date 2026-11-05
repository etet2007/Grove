// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Grove",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Grove", targets: ["Grove"])],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.5.0")
    ],
    targets: [
        .executableTarget(name: "Grove", dependencies: [.product(name: "Markdown", package: "swift-markdown")], path: "Sources/Grove"),
        .testTarget(name: "GroveTests", dependencies: ["Grove"], path: "Tests/GroveTests")
    ]
)
