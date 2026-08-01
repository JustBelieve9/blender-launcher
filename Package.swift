// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BlenderLauncher",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "BlenderLauncher",
            path: "Sources/BlenderLauncher"
        )
    ]
)
