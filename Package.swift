// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ScreenCheck",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ScreenCheck", targets: ["ScreenCheck"]),
        .executable(name: "screencheck-cli", targets: ["screencheck-cli"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .target(name: "ScreenCheckCore"),
        .executableTarget(
            name: "ScreenCheck",
            dependencies: ["ScreenCheckCore", "KeyboardShortcuts"]
        ),
        .executableTarget(name: "screencheck-cli", dependencies: ["ScreenCheckCore"]),
        .testTarget(name: "ScreenCheckCoreTests", dependencies: ["ScreenCheckCore"]),
    ]
)
