// swift-tools-version: 6.2
//
// OBAKitCore and OBAKit as a Swift package. The apps in this repo consume it as
// a local package (see `packages:` in Apps/Shared/app_shared.yml); anyone else
// can add this repository as a package dependency.
//
// Every target builds in the Swift 6 language mode, which the 6.2 tools
// version implies. The settings below reproduce the rest of the project-wide
// base in Apps/Shared/app_shared.yml, so a package target is checked exactly as
// strictly as an Xcode target.

import PackageDescription

/// The two features of Xcode's "approachable concurrency" that the Swift 6
/// language mode doesn't already turn on, and the five concurrency diagnostic
/// groups that app_shared.yml escalates to errors (SWIFT_WARNINGS_AS_ERRORS_GROUPS).
let strictConcurrency: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .treatWarning("ActorIsolatedCall", as: .error),
    .treatWarning("SendableClosureCaptures", as: .error),
    .treatWarning("RegionIsolation", as: .error),
    .treatWarning("ConformanceIsolation", as: .error),
    .treatWarning("MutableGlobalVariable", as: .error),
]

let package = Package(
    name: "OBAKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
        // The release paired with the iOS 18 floor.
        .watchOS(.v11),
    ],
    products: [
        .library(name: "OBAKitCore", targets: ["OBAKitCore"]),
        // iOS only: OBAKit is UIKit throughout.
        .library(name: "OBAKit", targets: ["OBAKit"]),
        // watchOS only: the watch app's screens and host.
        .library(name: "OBAKitWatch", targets: ["OBAKitWatch"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.38.1"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.0"),
        .package(url: "https://github.com/SCENEE/FloatingPanel.git", from: "3.2.2"),
        // Pre-1.0, so a minor release can break the API.
        .package(url: "https://github.com/OneBusAway/otpkit.git", .upToNextMinor(from: "0.17.0")),
    ],
    targets: [
        // Core business logic, networking and models, for iOS and watchOS.
        //
        // SwiftPM can't include a source file on one platform only, so the
        // iOS-only half of the module lives in OBAKitCore/iOS/ and every file
        // there is wrapped in `#if os(iOS)`. Nothing outside that directory
        // should need a platform conditional.
        //
        // Default isolation stays `nonisolated` here, unlike the rest of the
        // project: Core owns the actors, networking and background decode.
        .target(
            name: "OBAKitCore",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "OBAKitCore",
            // The .proto schema is source material for the pre-generated Swift.
            exclude: ["Models/Protobuf/gtfs-realtime.proto"],
            // The .lproj string tables and PrivacyInfo.xcprivacy are picked up
            // as resources automatically; naming them here is a "duplicate
            // rule" error.
            swiftSettings: strictConcurrency
        ),

        // View controllers and UI components. Main-actor default isolation, as
        // in every Xcode target.
        .target(
            name: "OBAKit",
            dependencies: [
                "OBAKitCore",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "FloatingPanel", package: "FloatingPanel"),
                .product(name: "OTPKit", package: "otpkit"),
            ],
            path: "OBAKit",
            // The vendored BulletinBoard, Hyperconnectivity and MarqueeLabel
            // licenses are shown on the Credits screen
            // (Settings/OBAKit_Credits.plist); keep the raw files out of the
            // bundle.
            exclude: [
                "ThirdParty/BulletinBoard/LICENSE",
                "ThirdParty/Hyperconnectivity/LICENSE",
                "ThirdParty/MarqueeLabel/LICENSE",
            ],
            // String tables, the asset catalog and the privacy manifest are
            // picked up automatically; these two are not, and both are
            // force-unwrapped where they're loaded.
            resources: [
                .process("Settings/OBAKit_Credits.plist"),
                .process("WebView/document_web_view_content.html"),
            ],
            swiftSettings: strictConcurrency + [.defaultIsolation(MainActor.self)],
            // Health-based features read HealthKit; the app declares the purpose
            // strings.
            linkerSettings: [.linkedFramework("HealthKit")]
        ),

        // The watch app's SwiftUI screens and host. Logic stays in OBAKitCore,
        // where OBAKitTests covers it. Main-actor default isolation, as in
        // every Xcode target.
        .target(
            name: "OBAKitWatch",
            dependencies: ["OBAKitCore"],
            path: "OBAKitWatch",
            swiftSettings: strictConcurrency + [.defaultIsolation(MainActor.self)]
        ),
    ]
)
