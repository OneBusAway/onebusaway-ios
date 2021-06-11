// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OBAKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(name: "OBAKit", targets: ["OBAKit"]),
        .library(name: "OBAKitCore", targets: ["OBAKitCore"]),
    ],
    dependencies: [
        .package(name: "BLTNBoard", url: "https://github.com/alexaubry/BulletinBoard.git", .exact("5.0.0")),
        .package(url: "https://github.com/CocoaLumberjack/CocoaLumberjack.git", .exact("3.7.2")),
        .package(url: "https://github.com/xmartlabs/Eureka.git", .exact("5.3.3")),
        .package(url: "https://github.com/SCENEE/FloatingPanel.git", .exact("1.7.6")),
        .package(url: "https://github.com/rwbutler/Hyperconnectivity.git", .exact("1.1.0")),
        .package(url: "https://github.com/cbpowell/MarqueeLabel.git", .exact("4.0.5")),
        .package(name: "SwiftProtobuf", url: "https://github.com/apple/swift-protobuf.git", from: "1.17.0")
    ],
    targets: [
        .target(
            name: "OBAKit",
            dependencies: [
                "BLTNBoard",
                "Eureka",
                "FloatingPanel",
                "Hyperconnectivity",
                "MarqueeLabel",
                "OBAKitCore"
            ],
            path: "OBAKit",
            exclude: ["Info.plist", "project.yml"],
            resources: [
                .copy("Settings/OBAKit_Credits.plist"),
                .copy("Theme/OBAKit.xcassets")
            ]
        ),

        .target(
            name: "OBAKitCore",
            dependencies: [
                "CocoaLumberjack",
                .product(name: "CocoaLumberjackSwift", package: "CocoaLumberjack"),
                "SwiftProtobuf"
            ],
            path: "OBAKitCore",
            exclude: ["Info.plist", "Models/Protobuf/gtfs-realtime.proto", "project.yml"]
        )
    ]
)
