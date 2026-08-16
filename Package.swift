// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "OpenConnectVPN",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "OpenConnectCore", targets: ["OpenConnectCore"]),
        .executable(name: "OpenConnectVPN", targets: ["OpenConnectVPN"]),
        .executable(name: "OpenConnectLauncher", targets: ["OpenConnectLauncher"])
    ],
    targets: [
        .target(
            name: "OpenConnectCore",
            path: "Sources/OpenConnectCore"
        ),
        .executableTarget(
            name: "OpenConnectVPN",
            dependencies: ["OpenConnectCore"],
            path: "Sources/OpenConnectVPN"
        ),
        .executableTarget(
            name: "OpenConnectLauncher",
            path: "Sources/OpenConnectLauncher"
        ),
        .testTarget(
            name: "OpenConnectCoreTests",
            dependencies: ["OpenConnectCore"],
            path: "Tests/OpenConnectCoreTests"
        )
    ]
)
