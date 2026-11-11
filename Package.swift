// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MouseMover",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MouseMover",
            path: "Sources/MouseMover"
        )
    ]
)
