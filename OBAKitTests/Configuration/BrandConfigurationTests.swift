//
//  BrandConfigurationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class BrandConfigurationTests: OBATestCase {

    private nonisolated class MockBrandBundle: Bundle, @unchecked Sendable {
        var info: [String: Any] = [:]

        override func object(forInfoDictionaryKey key: String) -> Any? {
            if let val = info[key] { return val }
            return super.object(forInfoDictionaryKey: key)
        }

        static func create(displayName: String? = nil, name: String? = nil) throws -> MockBrandBundle {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let bundle = try #require(MockBrandBundle(path: dir.path))
            var dict: [String: Any] = [:]
            if let displayName { dict["CFBundleDisplayName"] = displayName }
            if let name { dict["CFBundleName"] = name }
            bundle.info = dict
            return bundle
        }
    }

    // MARK: - Default Branded Target

    @Test func `Default target app name resolves to OneBusAway`() {
        let appName = Bundle.main.appName
        #expect(!appName.isEmpty)
        #expect(appName == "OneBusAway")
    }

    // MARK: - Alternate White-Label Target Resolution

    @Test func `White-label target app name resolves from CFBundleDisplayName`() throws {
        let kiedyBusBundle = try MockBrandBundle.create(displayName: "KiedyBus", name: "App")
        #expect(kiedyBusBundle.appName == "KiedyBus")
    }

    @Test func `Fallback app name resolves from CFBundleName when display name absent`() throws {
        let fallbackBundle = try MockBrandBundle.create(displayName: nil, name: "TransitApp")
        #expect(fallbackBundle.appName == "TransitApp")
    }

    // MARK: - Localized Dynamic Strings

    @Test func `Welcome title formats dynamic brand name`() throws {
        let template = OBAKit.OBALoc(
            "onboarding.welcome.title_fmt",
            value: "Welcome to %@",
            comment: "Title of the first onboarding screen; the argument is the app name"
        )

        // Default target output
        let defaultWelcome = String(format: template, Bundle.main.appName)
        #expect(defaultWelcome == "Welcome to OneBusAway")

        // Alternate white-label target output (KiedyBus)
        let kiedyBusBundle = try MockBrandBundle.create(displayName: "KiedyBus")
        let whiteLabelWelcome = String(format: template, kiedyBusBundle.appName)
        #expect(whiteLabelWelcome == "Welcome to KiedyBus")

        // Localized city-specific white-label output
        let localizedBundle = try MockBrandBundle.create(displayName: "KiedyBus Wrocław")
        let localizedWelcome = String(format: template, localizedBundle.appName)
        #expect(localizedWelcome == "Welcome to KiedyBus Wrocław")
    }
}
