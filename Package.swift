// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PayDayKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(name: "PayDayKit", targets: ["PayDayKit"])
    ],
    targets: [
        .target(
            name: "PayDayKit",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "PayDayKitTests",
            dependencies: ["PayDayKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
