// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "cduyzhFileClean",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "cduyzhFileClean", targets: ["FileCleanApp"])],
    dependencies: [],
    targets: [
        .target(name: "FileCleanCore", path: "Sources/FileCleanCore"),
        .executableTarget(name: "FileCleanApp", dependencies: ["FileCleanCore"], path: "Sources/FileCleanApp"),
        .testTarget(name: "FileCleanCoreTests", dependencies: ["FileCleanCore"], path: "Tests/FileCleanCoreTests")
    ]
)
