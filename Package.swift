// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Udara",
    platforms: [.macOS(.v15)],
    products: [.library(name: "Udara", targets: ["Udara"])],
    targets: [
        .target(name: "Udara", path: "Sources/UdaraCore"),
        .testTarget(name: "UdaraTests", dependencies: ["Udara"], path: "Tests/UdaraTests")
    ]
)
