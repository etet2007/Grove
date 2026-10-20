// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MyGit",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MyGit", targets: ["MyGit"])],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.5.0")
    ],
    targets: [
        .executableTarget(name: "MyGit", dependencies: [.product(name: "Markdown", package: "swift-markdown")], path: "Sources/MyGit"),
        .testTarget(name: "MyGitTests", dependencies: ["MyGit"], path: "Tests/MyGitTests")
    ]
)
