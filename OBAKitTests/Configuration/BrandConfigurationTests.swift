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

    @Test func `Default target app name resolves from CFBundleDisplayName`() throws {
        let displayName = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
        #expect(!displayName.isEmpty)
        #expect(Bundle.main.appName == displayName)
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

    @Test(arguments: ["TransitApp", "KiedyBus", "KiedyBus Wrocław"])
    func `Welcome title formats dynamic brand name`(appName: String) throws {
        let template = OBAKit.OBALoc(
            "onboarding.welcome.title_fmt",
            value: "Welcome to %@",
            comment: "Title of the first onboarding screen; the argument is the app name"
        )
        try #require(template.contains("%@"), "The localized welcome title must contain the app-name placeholder")

        let bundle = try MockBrandBundle.create(displayName: appName)
        defer { try? FileManager.default.removeItem(at: bundle.bundleURL) }
        let welcome = String(format: template, bundle.appName)
        #expect(welcome.contains(appName))
        #expect(!welcome.contains("%@"))
    }
}
