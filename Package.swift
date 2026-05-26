// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DeployBar",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DeployBar", targets: ["DeployBar"]),
        .library(name: "DeployBarCore", targets: ["DeployBarCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.2")
    ],
    targets: [
        .target(
            name: "DeployBarCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "DeployBar",
            dependencies: [
                "DeployBarCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "DeployBarCoreTests",
            dependencies: ["DeployBarCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
