// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CLIProxyMenuBar",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(
            name: "CLIProxyMenuBar",
            targets: ["CLIProxyMenuBar"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.5.0")
    ],
    targets: [
        .executableTarget(
            name: "CLIProxyMenuBar",
            dependencies: ["Sparkle"],
            path: "Sources",
            resources: [
                .copy("Resources")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
