// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PayDayCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(name: "PayDayCore", targets: ["PayDayCore"])
    ],
    targets: [
        .target(
            name: "PayDayCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "PayDayCoreTests",
            dependencies: ["PayDayCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
