// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OBAKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "OBAKitCore",
            targets: ["OBAKitCore"]
        ),
        .library(
            name: "OBAKit",
            targets: ["OBAKit"]
        )
    ],
    dependencies: [
        // OBAKitCore dependencies
        .package(url: "https://github.com/CocoaLumberjack/CocoaLumberjack.git", exact: "3.9.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.32.0"),

        // OBAKit dependencies
        .package(url: "https://github.com/alexaubry/BulletinBoard.git", exact: "5.0.0"),
        .package(url: "https://github.com/rwbutler/Hyperconnectivity.git", exact: "1.2.0"),
        .package(url: "https://github.com/xmartlabs/Eureka.git", exact: "5.5.0"),
        .package(url: "https://github.com/SCENEE/FloatingPanel.git", exact: "3.0.1"),
        .package(url: "https://github.com/cbpowell/MarqueeLabel.git", exact: "4.5.3"),
        .package(url: "https://github.com/OneBusAway/otpkit.git", "0.5.0"..<"1.0.0"),

        // Test dependencies
        .package(url: "https://github.com/Quick/Nimble.git", from: "13.7.0")
    ],
    targets: [
        // MARK: - OBAKitCore
        .target(
            name: "OBAKitCore",
            dependencies: [
                .product(name: "CocoaLumberjack", package: "CocoaLumberjack"),
                .product(name: "CocoaLumberjackSwift", package: "CocoaLumberjack"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
            ],
            path: "OBAKitCore",
            exclude: [
                "project.yml",
                "OBAKitCore.h",
                "Models/Protobuf/gtfs-realtime.proto"
            ],
            resources: [
                .process("Strings/en.lproj"),
                .process("Strings/es.lproj"),
                .process("Strings/it.lproj"),
                .process("Strings/pl.lproj"),
                .process("Strings/zh-Hans.lproj")
            ]
        ),

        // MARK: - OBAKit
        .target(
            name: "OBAKit",
            dependencies: [
                "OBAKitCore",
                .product(name: "BLTNBoard", package: "BulletinBoard"),
                .product(name: "Hyperconnectivity", package: "Hyperconnectivity"),
                .product(name: "Eureka", package: "Eureka"),
                .product(name: "FloatingPanel", package: "FloatingPanel"),
                .product(name: "MarqueeLabel", package: "MarqueeLabel"),
                .product(name: "OTPKit", package: "otpkit")
            ],
            path: "OBAKit",
            exclude: [
                "project.yml",
                "OBAKit.h"
            ],
            resources: [
                .process("Strings/en.lproj"),
                .process("Strings/es.lproj"),
                .process("Strings/it.lproj"),
                .process("Strings/pl.lproj"),
                .process("Strings/zh-Hans.lproj"),
                .process("Theme/OBAKit.xcassets"),
                .process("Settings/OBAKit_Credits.plist")
            ]
        ),

        // MARK: - Tests
        .testTarget(
            name: "OBAKitTests",
            dependencies: [
                "OBAKit",
                "OBAKitCore",
                .product(name: "Nimble", package: "Nimble")
            ],
            path: "OBAKitTests",
            exclude: [
                "project.yml",
                "OBAKitTests-Bridging-Header.h"
            ],
            resources: [
                .copy("fixtures")
            ]
        )
    ]
)
