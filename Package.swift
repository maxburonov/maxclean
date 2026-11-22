// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MaxClean",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MaxClean",
            path: "Sources/MaxClean"
        )
    ]
)
