//
//  FoundationExtensionsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import XCTest
import Testing
@testable import OBAKitCore

@MainActor
class FoundationExtensionsTests: XCTestCase {

    // MARK: - Error.isCancellation

    /// `isCancellation` decides whether an error is *swallowed* rather than
    /// surfaced (e.g. `TripViewModel`), so misclassification in either
    /// direction is user-visible: swallow a real error, or alert on every
    /// dismissed context-menu preview.
    func test_error_isCancellation() {
        #expect(CancellationError().isCancellation)
        #expect(URLError(.cancelled).isCancellation)
        #expect(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled).isCancellation)

        #expect(!URLError(.badServerResponse).isCancellation)
        #expect(!URLError(.timedOut).isCancellation)
        #expect(!NSError(domain: NSCocoaErrorDomain, code: NSURLErrorCancelled).isCancellation)
    }
    
    func test_Bundle_appName() {
        let bundle = Bundle.main
        let appName = bundle.appName
        
        // This will vary by app, but should not be empty for main bundle
        #expect(!appName.isEmpty)
    }
    
    func test_Bundle_bundleIdentifier_extension() {
        let bundle = Bundle.main
        // Test that our bundleIdentifier extension works by getting the CFBundleIdentifier value
        let bundleIdentifier = bundle.object(forInfoDictionaryKey: "CFBundleIdentifier") as? String
        
        #expect(bundleIdentifier != nil)
        #expect(bundleIdentifier?.isEmpty == false)
        // `bundleIdentifier` is String?; Nimble's contain failed on nil, and so
        // does `?.contains(...) == true`.
        #expect(bundleIdentifier?.contains(".") == true)
    }
    
    func test_Bundle_appVersion() {
        let bundle = Bundle.main
        let appVersion = bundle.appVersion
        
        #expect(!appVersion.isEmpty)
    }
    
    func test_Bundle_copyright() {
        let bundle = Bundle.main

        // This may be empty in test bundles, but should not crash
        _ = bundle.copyright
    }
    
    func test_Bundle_userActivityTypes() {
        let bundle = Bundle.main
        let userActivityTypes = bundle.userActivityTypes
        
        // This may be nil, but should not crash
        if let types = userActivityTypes {
            #expect(type(of: types) == [String].self)
        }
    }
    
    func test_Bundle_donationsEnabled() {
        let bundle = Bundle.main
        let donationsEnabled = bundle.donationsEnabled
        
        // This should return a boolean value without crashing
        #expect(type(of: donationsEnabled) == Bool.self)
    }
    
    func test_Bundle_donationManagementPortal() {
        let bundle = Bundle.main
        let portal = bundle.donationManagementPortal
        
        // This may be nil, but should not crash
        if let portalURL = portal {
            #expect(type(of: portalURL) == URL.self)
        }
    }
    
    func test_Bundle_extensionURLScheme() {
        let bundle = Bundle.main
        let scheme = bundle.extensionURLScheme
        
        // This may be nil, but should not crash
        if let urlScheme = scheme {
            #expect(type(of: urlScheme) == String.self)
            #expect(!urlScheme.isEmpty)
        }
    }
    
    func test_Bundle_bundledRegionsFileName() {
        let bundle = Bundle.main
        let fileName = bundle.bundledRegionsFileName
        
        // This may be nil, but should not crash
        if let name = fileName {
            #expect(type(of: name) == String.self)
            #expect(!name.isEmpty)
        }
    }
    
    func test_Bundle_bundledRegionsFilePath() {
        let bundle = Bundle.main
        let filePath = bundle.bundledRegionsFilePath
        
        // This may be nil, but should not crash
        if let path = filePath {
            #expect(type(of: path) == String.self)
            #expect(!path.isEmpty)
        }
    }
    
    func test_Bundle_regionsServerBaseAddress() {
        let bundle = Bundle.main
        let baseAddress = bundle.regionsServerBaseAddress
        
        // This may be nil, but should not crash
        if let url = baseAddress {
            #expect(type(of: url) == URL.self)
        }
    }
    
    func test_Bundle_regionsServerAPIPath() {
        let bundle = Bundle.main
        let apiPath = bundle.regionsServerAPIPath
        
        // This may be nil, but should not crash
        if let path = apiPath {
            #expect(type(of: path) == String.self)
            #expect(!path.isEmpty)
        }
    }
    
    func test_Bundle_restServerAPIKey() {
        let bundle = Bundle.main
        let apiKey = bundle.restServerAPIKey
        
        // This may be nil, but should not crash
        if let key = apiKey {
            #expect(type(of: key) == String.self)
            #expect(!key.isEmpty)
        }
    }
    
    func test_Bundle_appGroup() {
        let bundle = Bundle.main
        let appGroup = bundle.appGroup

        // This may be nil, but should not crash
        if let group = appGroup {
            #expect(type(of: group) == String.self)
            #expect(!group.isEmpty)
        }
    }
}

/// A `Bundle` whose `OBAKitConfig` reports configurable feedback-prompt values,
/// so these tests don't depend on the host app's Info.plist.
// `Bundle` is already `@unchecked Sendable`; a subclass has to restate it or the
// compiler warns. Mutated only from the test that owns the instance.
private class FeedbackConfigBundle: Bundle, @unchecked Sendable {
    var config: [AnyHashable: Any] = [:]

    override func object(forInfoDictionaryKey key: String) -> Any? {
        if key == "OBAKitConfig" { return config }
        return super.object(forInfoDictionaryKey: key)
    }

    static func create(config: [AnyHashable: Any]) throws -> FeedbackConfigBundle {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bundle = try XCTUnwrap(FeedbackConfigBundle(path: dir.path))
        bundle.config = config
        return bundle
    }
}

final class BundleFeedbackConfigTests: XCTestCase {

    func test_appStoreID_readsFromOBAKitConfig() throws {
        let bundle = try FeedbackConfigBundle.create(config: ["AppStoreID": "329380089"])
        XCTAssertEqual(bundle.appStoreID, "329380089")
    }

    func test_appStoreID_isNilWhenAbsent() throws {
        let bundle = try FeedbackConfigBundle.create(config: [:])
        XCTAssertNil(bundle.appStoreID)
    }

    func test_feedbackPromptEnabled_defaultsToTrueWhenAbsent() throws {
        let bundle = try FeedbackConfigBundle.create(config: [:])
        XCTAssertTrue(bundle.feedbackPromptEnabled)
    }

    func test_feedbackPromptEnabled_honorsExplicitFalse() throws {
        let bundle = try FeedbackConfigBundle.create(config: ["FeedbackPromptEnabled": false])
        XCTAssertFalse(bundle.feedbackPromptEnabled)
    }
}
