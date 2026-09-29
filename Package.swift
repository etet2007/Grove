// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MyGit",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MyGit", targets: ["MyGit"])],
    targets: [
        .executableTarget(name: "MyGit", path: "Sources/MyGit"),
        .testTarget(name: "MyGitTests", dependencies: ["MyGit"], path: "Tests/MyGitTests")
    ]
)
