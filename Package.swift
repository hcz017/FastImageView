// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FastImageView",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FastImageViewCore"),
        .executableTarget(name: "FastImageView", dependencies: ["FastImageViewCore"]),
        .testTarget(name: "FastImageViewCoreTests", dependencies: ["FastImageViewCore"])
    ]
)
