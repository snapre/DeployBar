// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DeployBar",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DeployBar", targets: ["DeployBar"]),
        .library(name: "DeployBarCore", targets: ["DeployBarCore"])
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
            dependencies: ["DeployBarCore"],
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
