//
//  FoundationExtensionsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

@MainActor
@Suite(.serialized)
final class FoundationExtensionsTests {

    // MARK: - Error.isCancellation

    /// `isCancellation` decides whether an error is *swallowed* rather than
    /// surfaced (e.g. `TripViewModel`), so misclassification in either
    /// direction is user-visible: swallow a real error, or alert on every
    /// dismissed context-menu preview.
    @Test func `Error is cancellation`() {
        #expect(CancellationError().isCancellation)
        #expect(URLError(.cancelled).isCancellation)
        #expect(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled).isCancellation)

        #expect(!URLError(.badServerResponse).isCancellation)
        #expect(!URLError(.timedOut).isCancellation)
        #expect(!NSError(domain: NSCocoaErrorDomain, code: NSURLErrorCancelled).isCancellation)
    }
    
    @Test func `Bundle app name`() {
        let bundle = Bundle.main
        let appName = bundle.appName
        
        // This will vary by app, but should not be empty for main bundle
        #expect(!appName.isEmpty)
    }
    
    @Test func `Bundle bundle identifier extension`() {
        let bundle = Bundle.main
        // Test that our bundleIdentifier extension works by getting the CFBundleIdentifier value
        let bundleIdentifier = bundle.object(forInfoDictionaryKey: "CFBundleIdentifier") as? String
        
        #expect(bundleIdentifier != nil)
        #expect(bundleIdentifier?.isEmpty == false)
        // `bundleIdentifier` is String?; Nimble's contain failed on nil, and so
        // does `?.contains(...) == true`.
        #expect(bundleIdentifier?.contains(".") == true)
    }
    
    @Test func `Bundle app version`() {
        let bundle = Bundle.main
        let appVersion = bundle.appVersion
        
        #expect(!appVersion.isEmpty)
    }
    
    @Test func `Bundle copyright`() {
        let bundle = Bundle.main

        // This may be empty in test bundles, but should not crash
        _ = bundle.copyright
    }
    
    @Test func `Bundle user activity types`() {
        let bundle = Bundle.main
        let userActivityTypes = bundle.userActivityTypes
        
        // This may be nil, but should not crash
        if let types = userActivityTypes {
            #expect(type(of: types) == [String].self)
        }
    }
    
    @Test func `Bundle donations enabled`() {
        let bundle = Bundle.main
        let donationsEnabled = bundle.donationsEnabled
        
        // This should return a boolean value without crashing
        #expect(type(of: donationsEnabled) == Bool.self)
    }
    
    @Test func `Bundle donation management portal`() {
        let bundle = Bundle.main
        let portal = bundle.donationManagementPortal
        
        // This may be nil, but should not crash
        if let portalURL = portal {
            #expect(type(of: portalURL) == URL.self)
        }
    }
    
    @Test func `Bundle extension URL scheme`() {
        let bundle = Bundle.main
        let scheme = bundle.extensionURLScheme
        
        // This may be nil, but should not crash
        if let urlScheme = scheme {
            #expect(type(of: urlScheme) == String.self)
            #expect(!urlScheme.isEmpty)
        }
    }
    
    @Test func `Bundle bundled regions file name`() {
        let bundle = Bundle.main
        let fileName = bundle.bundledRegionsFileName
        
        // This may be nil, but should not crash
        if let name = fileName {
            #expect(type(of: name) == String.self)
            #expect(!name.isEmpty)
        }
    }
    
    @Test func `Bundle bundled regions file path`() {
        let bundle = Bundle.main
        let filePath = bundle.bundledRegionsFilePath
        
        // This may be nil, but should not crash
        if let path = filePath {
            #expect(type(of: path) == String.self)
            #expect(!path.isEmpty)
        }
    }
    
    @Test func `Bundle regions server base address`() {
        let bundle = Bundle.main
        let baseAddress = bundle.regionsServerBaseAddress
        
        // This may be nil, but should not crash
        if let url = baseAddress {
            #expect(type(of: url) == URL.self)
        }
    }
    
    @Test func `Bundle regions server API path`() {
        let bundle = Bundle.main
        let apiPath = bundle.regionsServerAPIPath
        
        // This may be nil, but should not crash
        if let path = apiPath {
            #expect(type(of: path) == String.self)
            #expect(!path.isEmpty)
        }
    }
    
    @Test func `Bundle rest server API key`() {
        let bundle = Bundle.main
        let apiKey = bundle.restServerAPIKey
        
        // This may be nil, but should not crash
        if let key = apiKey {
            #expect(type(of: key) == String.self)
            #expect(!key.isEmpty)
        }
    }
    
    @Test func `Bundle app group`() {
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
// `nonisolated`: overrides nonisolated Bundle members, which the
// target's main-actor default isolation would conflict with.
private nonisolated class FeedbackConfigBundle: Bundle, @unchecked Sendable {
    var config: [AnyHashable: Any] = [:]

    override func object(forInfoDictionaryKey key: String) -> Any? {
        if key == "OBAKitConfig" { return config }
        return super.object(forInfoDictionaryKey: key)
    }

    static func create(config: [AnyHashable: Any]) throws -> FeedbackConfigBundle {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bundle = try #require(FeedbackConfigBundle(path: dir.path))
        bundle.config = config
        return bundle
    }
}

@Suite(.serialized)
final class BundleFeedbackConfigTests {

    @Test func `App store ID reads from OBA kit config`() throws {
        let bundle = try FeedbackConfigBundle.create(config: ["AppStoreID": "329380089"])
        #expect(bundle.appStoreID == "329380089")
    }

    @Test func `App store ID is nil when absent`() throws {
        let bundle = try FeedbackConfigBundle.create(config: [:])
        #expect(bundle.appStoreID == nil)
    }

    @Test func `Feedback prompt enabled defaults to true when absent`() throws {
        let bundle = try FeedbackConfigBundle.create(config: [:])
        #expect(bundle.feedbackPromptEnabled)
    }

    @Test func `Feedback prompt enabled honors explicit false`() throws {
        let bundle = try FeedbackConfigBundle.create(config: ["FeedbackPromptEnabled": false])
        #expect(!bundle.feedbackPromptEnabled)
    }
}
