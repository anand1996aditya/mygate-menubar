// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MyGateMenuBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "MyGateMenuBar", path: "Sources/MyGateMenuBar")
    ]
)
