// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AutonomousAIChat",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AutonomousAIChat", targets: ["AutonomousAIChat"])
    ],
    targets: [
        .binaryTarget(
            name: "Sparkle",
            path: "Vendor/Sparkle/Sparkle.xcframework"
        ),
        .executableTarget(
            name: "AutonomousAIChat",
            dependencies: ["Sparkle"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Security"),
                .linkedFramework("WebKit")
            ]
        ),
        .testTarget(
            name: "AutonomousAIChatTests",
            dependencies: ["AutonomousAIChat"]
        )
    ]
)
