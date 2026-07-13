// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ownscribe",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Ownscribe",
            path: "Sources/Ownscribe"
        )
    ]
)
