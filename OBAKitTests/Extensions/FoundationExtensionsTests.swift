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

    // MARK: - URLComponents.appendPath

    /// Every combination of a trailing slash on the base and a leading slash on
    /// the appended part comes out with exactly one slash between them.
    @Test(arguments: [
        ("/api", "foo"),
        ("/api/", "foo"),
        ("/api", "/foo"),
        ("/api/", "/foo")
    ])
    func `Append path joins with exactly one slash`(base: String, appended: String) throws {
        var components = try #require(URLComponents(string: "https://example.com"))
        components.path = base

        components.appendPath(appended)

        #expect(components.path == "/api/foo")
    }

    /// `ObacoAPIService` appends paths like this to the region's sidecar base
    /// URL, which may come with or without a trailing slash.
    @Test func `Append path builds the sidecar URL from a bare or slashed host`() throws {
        for base in ["https://obaco.example.com", "https://obaco.example.com/"] {
            var components = try #require(URLComponents(string: base))
            components.appendPath("/api/v1/regions/1/weather.json")
            #expect(components.url?.absoluteString == "https://obaco.example.com/api/v1/regions/1/weather.json")
        }
    }

    // MARK: - String.caseInsensitiveMatch

    private let stopPagePattern = "/regions/(?<region>[^/]+)/stops/(?<stop>[^/]+)$"

    /// Shared stop links are typed and pasted by people, so the path's case
    /// can't be trusted; the captured values keep the case they arrived in.
    @Test func `Case insensitive match extracts named groups whatever the case`() {
        let matches = "/REGIONS/1/Stops/1_ABC".caseInsensitiveMatch(pattern: stopPagePattern, namedGroups: ["region", "stop"])

        #expect(matches == ["region": "1", "stop": "1_ABC"])
    }

    @Test func `Case insensitive match is nil when the string does not match`() {
        #expect("/regions/1/routes/1_100".caseInsensitiveMatch(pattern: stopPagePattern, namedGroups: ["region", "stop"]) == nil)
        #expect("/regions/1/stops/1_75403/trips".caseInsensitiveMatch(pattern: stopPagePattern, namedGroups: ["region", "stop"]) == nil)
    }

    /// A group the match didn't use is left out, rather than reported as an
    /// empty string, and a name the pattern doesn't have is ignored.
    @Test func `Case insensitive match leaves out groups that took no part`() {
        let pattern = "/stops/(?<stop>[^/]+)(/trips/(?<trip>[^/]+))?$"

        // `route` isn't in the pattern.
        let stopOnly = "/stops/1_75403".caseInsensitiveMatch(pattern: pattern, namedGroups: ["stop", "trip", "route"])
        let withTrip = "/stops/1_75403/trips/1_604".caseInsensitiveMatch(pattern: pattern, namedGroups: ["stop", "trip", "route"])

        #expect(stopOnly == ["stop": "1_75403"])
        #expect(withTrip == ["stop": "1_75403", "trip": "1_604"])
    }

    // MARK: - HTTPURLResponse.hasJSONContentType

    private func response(contentType: String?) throws -> HTTPURLResponse {
        let url = try #require(URL(string: "https://api.example.com/where/stop.json"))
        let headers = contentType.map { ["Content-Type": $0] }
        return try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers))
    }

    /// Servers add parameters after the type, and some still send the older
    /// `text/json`; both carry JSON the decoder can read.
    @Test func `Has JSON content type accepts JSON with parameters and text json`() throws {
        #expect(try response(contentType: "application/json").hasJSONContentType)
        #expect(try response(contentType: "application/json; charset=utf-8").hasJSONContentType)
        #expect(try response(contentType: "text/json").hasJSONContentType)
    }

    /// A captive portal answers API requests with an HTML login page. That
    /// must be refused before the decoder sees it.
    @Test func `Has JSON content type rejects HTML and a missing header`() throws {
        #expect(try response(contentType: "text/html; charset=utf-8").hasJSONContentType == false)
        #expect(try response(contentType: "text/plain").hasJSONContentType == false)
        #expect(try response(contentType: nil).hasJSONContentType == false)
    }

    // MARK: - String.isNumeric

    /// Decides whether a stop code is shown as a number. Only the ASCII digits
    /// count: no sign, no decimal point, no spaces, and no other scripts' digits.
    @Test func `Is numeric is true only for ASCII digits`() {
        #expect("0".isNumeric)
        #expect("10914".isNumeric)

        #expect("".isNumeric == false)
        #expect("12a".isNumeric == false)
        #expect(" 12".isNumeric == false)
        #expect("-1".isNumeric == false)
        #expect("1.5".isNumeric == false)
        #expect("١٢".isNumeric == false)
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

    // MARK: - Fixed region (issue #608)

    /// White-label apps pin a region in `OBAKitConfig` so the picker never
    /// appears. These keys are how `RegionsService` is configured at launch.
    @Test func `Fixed region name reads from OBA kit config`() throws {
        let bundle = try FeedbackConfigBundle.create(config: ["FixedRegionName": "Puget Sound"])
        #expect(bundle.fixedRegionName == "Puget Sound")
    }

    @Test func `Fixed region name is nil when absent`() throws {
        let bundle = try FeedbackConfigBundle.create(config: [:])
        #expect(bundle.fixedRegionName == nil)
    }

    @Test func `Fixed region OBA base URL reads from OBA kit config`() throws {
        let bundle = try FeedbackConfigBundle.create(config: [
            "FixedRegionOBABaseURL": "https://api.tampa.onebusawaycloud.com/"
        ])
        #expect(bundle.fixedRegionOBABaseURL == URL(string: "https://api.tampa.onebusawaycloud.com/"))
    }

    @Test func `Fixed region OBA base URL is nil when absent or unparseable`() throws {
        let missing = try FeedbackConfigBundle.create(config: [:])
        #expect(missing.fixedRegionOBABaseURL == nil)

        let garbage = try FeedbackConfigBundle.create(config: ["FixedRegionOBABaseURL": ""])
        #expect(garbage.fixedRegionOBABaseURL == nil)
    }

    // MARK: - Launch route (issue #617)

    @Test func `Launch route ID reads from OBA kit config`() throws {
        let bundle = try FeedbackConfigBundle.create(config: ["LaunchRouteID": "1_100479"])
        #expect(bundle.launchRouteID == "1_100479")
    }

    @Test func `Launch route ID is nil when absent or not a string`() throws {
        let missing = try FeedbackConfigBundle.create(config: [:])
        #expect(missing.launchRouteID == nil)

        let number = try FeedbackConfigBundle.create(config: ["LaunchRouteID": 100479])
        #expect(number.launchRouteID == nil)
    }

    // MARK: - OBAKitConfig.MoreTab

    @Test func `More tab configuration uses defaults when MoreTab is absent`() throws {
        let bundle = try FeedbackConfigBundle.create(config: [:])
        let more = bundle.moreTabConfiguration
        #expect(more.headerSupportText == nil)
        #expect(more.showHelpOutSection)
        #expect(more.translateURL == nil)
        #expect(more.developURL?.absoluteString == "https://github.com/oneBusAway/onebusaway-ios")
        #expect(more.customLinks.isEmpty)
    }

    @Test func `More tab configuration reads nested MoreTab from OBAKitConfig`() throws {
        let bundle = try FeedbackConfigBundle.create(config: [
            "MoreTab": [
                "HeaderSupportText": "Powered by TestAgency",
                "ShowHelpOutSection": false,
                "TranslateURL": "https://example.com/translate",
                "DevelopURL": "https://example.com/develop",
                "TutorialURL": "https://example.com/tutorials",
                "PhoneURL": "tel:+1234567890",
                "TextURL": "sms:+1234567890",
                "CustomLinks": [
                    ["Title": "Agency Site", "URL": "https://example.com"]
                ]
            ]
        ])
        let more = bundle.moreTabConfiguration
        #expect(more.headerSupportText == "Powered by TestAgency")
        #expect(!more.showHelpOutSection)
        #expect(more.translateURL?.absoluteString == "https://example.com/translate")
        #expect(more.developURL?.absoluteString == "https://example.com/develop")
        #expect(more.tutorialURL?.absoluteString == "https://example.com/tutorials")
        #expect(more.phoneURL?.absoluteString == "tel:+1234567890")
        #expect(more.textURL?.absoluteString == "sms:+1234567890")
        #expect(more.customLinks.count == 1)
        #expect(more.customLinks[0].title == "Agency Site")
        #expect(more.customLinks[0].url.absoluteString == "https://example.com")
    }
    // MARK: - String.normalizedSearchQuery

    /// Nil means "match everything". `.searchable` hands a view the empty string
    /// the moment its field is focused, and whitespace is the same non-intent —
    /// treating either as a real query would blank the list the instant the user
    /// tapped the search field.
    @Test func `Normalized search query is nil for absent or blank input`() {
        #expect(String.normalizedSearchQuery(nil) == nil)
        #expect(String.normalizedSearchQuery("") == nil)
        #expect(String.normalizedSearchQuery("   ") == nil)
        #expect(String.normalizedSearchQuery("\n\t ") == nil)
    }

    /// Lowercased and trimmed, because `matchesQuery(_:)` compares against
    /// lowercased fields and users leave stray spaces when they paste.
    @Test func `Normalized search query lowercases and trims`() {
        #expect(String.normalizedSearchQuery("  Pike St  ") == "pike st")
        #expect(String.normalizedSearchQuery("3RD AVE") == "3rd ave")
    }

    /// Interior spacing is part of the query — only the ends are trimmed.
    @Test func `Normalized search query preserves interior spacing`() {
        #expect(String.normalizedSearchQuery(" 3rd  ave ") == "3rd  ave")
    }

    // MARK: - String.telephoneURL

    /// Shared by `Agency.callURL` and the on-demand booking line: feeds publish
    /// numbers in any punctuation, and a dialer takes digits and `+` only.
    @Test func `Telephone URL keeps digits and plus`() {
        #expect("(703) 746-5222".dialableDigits == "7037465222")
        #expect(" +1 206.553.3000 ".telephoneURL == URL(string: "tel://+12065533000"))
        #expect("n/a".dialableDigits == nil)
        #expect("call us".telephoneURL == nil)
    }
}
