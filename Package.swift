// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lamina",
    products: [
        .library(name: "LaminaCore", targets: ["LaminaCore"])
    ],
    targets: [
        .target(
            name: "LaminaCore",
            path: "Sources/LaminaCore",
            exclude: [],
            resources: [
                .copy("Resources/adobe_shortcuts_cn.txt")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "LaminaCoreTests",
            dependencies: ["LaminaCore"],
            path: "Tests/LaminaCoreTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
