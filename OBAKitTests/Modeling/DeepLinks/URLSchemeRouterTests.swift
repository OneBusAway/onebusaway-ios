//
//  URLSchemeRouterTests.swift
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
final class URLSchemeRouterTests {
    
    var router: URLSchemeRouter!
    
    init() {
        router = URLSchemeRouter(scheme: "onebusaway")
    }
    
    // MARK: - Initialization Tests
    
    @Test func `Initialization sets scheme`() {
        let customRouter = URLSchemeRouter(scheme: "customscheme")
        // Test by trying to encode a URL and checking the scheme
        let url = customRouter.encodeViewStop(stopID: "123", regionID: 1)
        #expect(url.scheme == "customscheme")
    }
    
    // MARK: - View Stop URL Tests
    
    @Test func `Encode view stop creates valid URL`() {
        let stopID = "12345"
        let regionID = 1
        
        let url = router.encodeViewStop(stopID: stopID, regionID: regionID)
        
        #expect(url.scheme == "onebusaway")
        #expect(url.host == "view-stop")
        
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.queryItems?.count == 2)
        #expect(components?.queryItems?.contains { $0.name == "stopID" && $0.value == stopID } == true)
        #expect(components?.queryItems?.contains { $0.name == "regionID" && $0.value == String(regionID) } == true)
    }
    
    @Test func `Decode URL type view stop decodes valid URL`() {
        // First encode a URL
        let stopID = "67890"
        let regionID = 2
        let url = router.encodeViewStop(stopID: stopID, regionID: regionID)
        
        // Then decode it
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .viewStop(let data):
            #expect(data.stopID == stopID)
            #expect(data.regionID == regionID)
        default:
            Issue.record("Expected viewStop URLType")
        }
    }
    
    @Test func `Decode URL type view stop returns nil for missing stop ID`() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "view-stop"
        components.queryItems = [URLQueryItem(name: "regionID", value: "1")]
        
        guard let url = components.url else {
            Issue.record("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        #expect(result == nil)
    }
    
    @Test func `Decode URL type view stop returns nil for missing region ID`() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "view-stop"
        components.queryItems = [URLQueryItem(name: "stopID", value: "12345")]
        
        guard let url = components.url else {
            Issue.record("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        #expect(result == nil)
    }
    
    @Test func `Decode URL type view stop returns nil for invalid region ID`() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "view-stop"
        components.queryItems = [
            URLQueryItem(name: "stopID", value: "12345"),
            URLQueryItem(name: "regionID", value: "not-a-number")
        ]
        
        guard let url = components.url else {
            Issue.record("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        #expect(result == nil)
    }
    
    // MARK: - Add Region URL Tests

    @Test func `Decode URL type add region decodes region ID`() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "region-id", value: "19"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com")
        ]

        guard let url = components.url else {
            Issue.record("Failed to create URL")
            return
        }

        switch router.decodeURLType(from: url) {
        case .addRegion(let data):
            #expect(data?.regionID == 19)
        default:
            Issue.record("Expected addRegion URLType")
        }
    }

    // Links generated before region-id was emitted must still add the region.
    @Test func `Decode URL type add region region ID is nil when absent`() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com")
        ]

        guard let url = components.url else {
            Issue.record("Failed to create URL")
            return
        }

        switch router.decodeURLType(from: url) {
        case .addRegion(let data):
            #expect(data != nil)
            #expect(data?.regionID == nil)
        default:
            Issue.record("Expected addRegion URLType")
        }
    }

    // A junk region-id costs sidecar features, but the region is still worth
    // adding — so it degrades to nil rather than rejecting the whole link.
    @Test func `Decode URL type add region malformed region ID degrades to nil`() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "region-id", value: "not-a-number"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com")
        ]

        guard let url = components.url else {
            Issue.record("Failed to create URL")
            return
        }

        switch router.decodeURLType(from: url) {
        case .addRegion(let data):
            #expect(data != nil)
            #expect(data?.name == "Test Region")
            #expect(data?.regionID == nil)
        default:
            Issue.record("Expected addRegion URLType")
        }
    }

    @Test func `Decode URL type add region decodes valid URL with OTPURL`() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com"),
            URLQueryItem(name: "otp-url", value: "https://otp.example.com")
        ]
        
        guard let url = components.url else {
            Issue.record("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .addRegion(let data):
            #expect(data != nil)
            #expect(data?.name == "Test Region")
            #expect(data?.obaURL.absoluteString == "https://oba.example.com")
            #expect(data?.otpURL?.absoluteString == "https://otp.example.com")
        default:
            Issue.record("Expected addRegion URLType")
        }
    }
    
    @Test func `Decode URL type add region decodes GraphQL URL and bikeshare flag`() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com"),
            URLQueryItem(name: "otp-graphql-url", value: "https://otp.example.com/otp/"),
            URLQueryItem(name: "otp-graphql-bikeshare", value: "true")
        ]

        guard let url = components.url else {
            Issue.record("Failed to create URL")
            return
        }

        switch router.decodeURLType(from: url) {
        case .addRegion(let data):
            #expect(data?.otpGraphQLURL?.absoluteString == "https://otp.example.com/otp/")
            #expect(data?.supportsOTPGraphQLBikeshare == true)
        default:
            Issue.record("Expected addRegion URLType")
        }
    }

    @Test func `Add region GraphQL fields default to absent`() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com")
        ]

        guard let url = components.url else {
            Issue.record("Failed to create URL")
            return
        }

        switch router.decodeURLType(from: url) {
        case .addRegion(let data):
            #expect(data?.otpGraphQLURL == nil)
            #expect(data?.supportsOTPGraphQLBikeshare == false)
        default:
            Issue.record("Expected addRegion URLType")
        }
    }

    @Test func `Decode URL type add region decodes valid URL without OTPURL`() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com")
        ]
        
        guard let url = components.url else {
            Issue.record("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .addRegion(let data):
            #expect(data != nil)
            #expect(data?.name == "Test Region")
            #expect(data?.obaURL.absoluteString == "https://oba.example.com")
            #expect(data?.otpURL == nil)
        default:
            Issue.record("Expected addRegion URLType")
        }
    }
    
    @Test func `Decode URL type add region returns nil data for missing name`() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "oba-url", value: "https://oba.example.com")
        ]
        
        guard let url = components.url else {
            Issue.record("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .addRegion(let data):
            #expect(data == nil)
        default:
            Issue.record("Expected addRegion URLType with nil data")
        }
    }
    
    @Test func `Decode URL type add region returns nil data for missing OBAURL`() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region")
        ]
        
        guard let url = components.url else {
            Issue.record("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .addRegion(let data):
            #expect(data == nil)
        default:
            Issue.record("Expected addRegion URLType with nil data")
        }
    }
    
    @Test func `Decode URL type add region returns nil data for empty OBAURL`() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "")
        ]
        
        guard let url = components.url else {
            Issue.record("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .addRegion(let data):
            #expect(data == nil)
        default:
            Issue.record("Expected addRegion URLType with nil data")
        }
    }
    
    @Test func `Decode URL type add region handles empty OTPURL`() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com"),
            URLQueryItem(name: "otp-url", value: "")
        ]
        
        guard let url = components.url else {
            Issue.record("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .addRegion(let data):
            #expect(data != nil)
            #expect(data?.name == "Test Region")
            #expect(data?.obaURL.absoluteString == "https://oba.example.com")
            #expect(data?.otpURL == nil)
        default:
            Issue.record("Expected addRegion URLType")
        }
    }
    
    // MARK: - General URL Decoding Tests
    
    @Test func `Decode URL type returns nil for unknown host`() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "unknown-host"
        components.queryItems = [URLQueryItem(name: "test", value: "value")]
        
        guard let url = components.url else {
            Issue.record("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        #expect(result == nil)
    }
    
    @Test func `Decode URL type returns nil for invalid URL`() {
        let url = URL(string: "not://a/valid/url")!
        let result = router.decodeURLType(from: url)
        #expect(result == nil)
    }
    
    @Test func `Decode URL type returns nil for URL without host`() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.path = "/some/path"
        
        guard let url = components.url else {
            Issue.record("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        #expect(result == nil)
    }
    
    // MARK: - Edge Cases
    
    @Test func `Encode view stop handles special characters in stop ID`() {
        let stopID = "stop+with/special&chars=123"
        let regionID = 1
        
        let url = router.encodeViewStop(stopID: stopID, regionID: regionID)
        
        // Decode and verify
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .viewStop(let data):
            #expect(data.stopID == stopID)
            #expect(data.regionID == regionID)
        default:
            Issue.record("Expected viewStop URLType")
        }
    }
    
    @Test func `Decode URL type add region handles encoded URL values`() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region with Spaces"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com/api?param=value&other=123")
        ]
        
        guard let url = components.url else {
            Issue.record("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .addRegion(let data):
            #expect(data != nil)
            #expect(data?.name == "Test Region with Spaces")
            #expect(data?.obaURL.absoluteString == "https://oba.example.com/api?param=value&other=123")
        default:
            Issue.record("Expected addRegion URLType")
        }
    }
    
    @Test func `Decode URL type handles empty query values`() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "view-stop"
        components.queryItems = [
            URLQueryItem(name: "stopID", value: ""),
            URLQueryItem(name: "regionID", value: "1")
        ]
        
        guard let url = components.url else {
            Issue.record("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .viewStop(let data):
            #expect(data.stopID == "")
            #expect(data.regionID == 1)
        default:
            Issue.record("Expected viewStop URLType")
        }
    }
    
    // MARK: - URL Validation Tests
    
    @Test func `Decode URL type add region rejects invalid OBAURL`() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "not a valid url")
        ]
        
        guard let url = components.url else {
            Issue.record("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .addRegion(let data):
            #expect(data == nil)
        default:
            Issue.record("Expected addRegion URLType with nil data")
        }
    }
    
    @Test func `Decode URL type add region rejects whitespace only OBAURL`() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "   ")
        ]
        
        guard let url = components.url else {
            Issue.record("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .addRegion(let data):
            #expect(data == nil)
        default:
            Issue.record("Expected addRegion URLType with nil data")
        }
    }
    
    @Test func `Decode URL type add region rejects invalid OTPURL`() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com"),
            URLQueryItem(name: "otp-url", value: "not a valid url")
        ]
        
        guard let url = components.url else {
            Issue.record("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .addRegion(let data):
            #expect(data != nil)
            #expect(data?.name == "Test Region")
            #expect(data?.obaURL.absoluteString == "https://oba.example.com")
            #expect(data?.otpURL == nil)  // Invalid OTP URL should result in nil
        default:
            Issue.record("Expected addRegion URLType")
        }
    }
    
    @Test func `Decode URL type add region accepts valid path OBAURL`() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "/api/oba")
        ]
        
        guard let url = components.url else {
            Issue.record("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .addRegion(let data):
            #expect(data != nil)
            #expect(data?.name == "Test Region")
            #expect(data?.obaURL.absoluteString == "/api/oba")
            #expect(data?.otpURL == nil)
        default:
            Issue.record("Expected addRegion URLType")
        }
    }
    
    @Test func `Decode URL type add region accepts valid path OTPURL`() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com"),
            URLQueryItem(name: "otp-url", value: "/api/otp")
        ]
        
        guard let url = components.url else {
            Issue.record("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .addRegion(let data):
            #expect(data != nil)
            #expect(data?.name == "Test Region")
            #expect(data?.obaURL.absoluteString == "https://oba.example.com")
            #expect(data?.otpURL?.absoluteString == "/api/otp")
        default:
            Issue.record("Expected addRegion URLType")
        }
    }
    
    @Test func `Decode URL type add region accepts complex valid URLs`() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://api.example.com:8080/oba/api?key=abc123&format=json"),
            URLQueryItem(name: "otp-url", value: "https://otp.example.com/otp/routers/default")
        ]
        
        guard let url = components.url else {
            Issue.record("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .addRegion(let data):
            #expect(data != nil)
            #expect(data?.name == "Test Region")
            #expect(data?.obaURL.absoluteString == "https://api.example.com:8080/oba/api?key=abc123&format=json")
            #expect(data?.otpURL?.absoluteString == "https://otp.example.com/otp/routers/default")
        default:
            Issue.record("Expected addRegion URLType")
        }
    }

    // MARK: - Sidecar & Umami Parameters

    private func decodeAddRegion(_ queryItems: [URLQueryItem]) -> AddRegionURLData? {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = queryItems
        guard let url = components.url, case .addRegion(let data)? = router.decodeURLType(from: url) else {
            Issue.record("Expected addRegion URLType")
            return nil
        }
        return data
    }

    @Test func `Decode URL type add region decodes all new parameters`() {
        let data = decodeAddRegion([
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com"),
            URLQueryItem(name: "sidecar-url", value: "https://obaco.example.com"),
            URLQueryItem(name: "umami-url", value: "https://analytics.example.com"),
            URLQueryItem(name: "umami-id", value: "site-uuid-123")
        ])

        #expect(data?.sidecarURL?.absoluteString == "https://obaco.example.com")
        #expect(data?.umamiURL?.absoluteString == "https://analytics.example.com")
        #expect(data?.umamiID == "site-uuid-123")
        #expect(data?.umamiAnalytics?.url.absoluteString == "https://analytics.example.com")
        #expect(data?.umamiAnalytics?.id == "site-uuid-123")
    }

    @Test func `Decode URL type add region new parameters default to nil`() {
        let data = decodeAddRegion([
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com")
        ])

        #expect(data?.sidecarURL == nil)
        #expect(data?.umamiURL == nil)
        #expect(data?.umamiID == nil)
        #expect(data?.umamiAnalytics == nil)
    }

    @Test func `Decode URL type add region partial umami pair collapses to nil config`() {
        // URL without ID.
        let urlOnly = decodeAddRegion([
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com"),
            URLQueryItem(name: "umami-url", value: "https://analytics.example.com")
        ])
        #expect(urlOnly?.umamiURL != nil)
        #expect(urlOnly?.umamiAnalytics == nil)

        // ID without URL — the region still decodes; the dangling ID never becomes a config.
        let idOnly = decodeAddRegion([
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com"),
            URLQueryItem(name: "umami-id", value: "site-uuid-123")
        ])
        #expect(idOnly?.umamiID == "site-uuid-123")
        #expect(idOnly?.umamiAnalytics == nil)

        // Invalid umami URL + valid ID — dangling ID, nil config.
        let invalidURL = decodeAddRegion([
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com"),
            URLQueryItem(name: "umami-url", value: "not a valid url"),
            URLQueryItem(name: "umami-id", value: "site-uuid-123")
        ])
        #expect(invalidURL?.umamiURL == nil)
        #expect(invalidURL?.umamiAnalytics == nil)
    }

    @Test func `Decode URL type add region blank umami ID becomes nil`() {
        let data = decodeAddRegion([
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com"),
            URLQueryItem(name: "umami-url", value: "https://analytics.example.com"),
            URLQueryItem(name: "umami-id", value: "   ")
        ])
        #expect(data?.umamiID == nil)
        #expect(data?.umamiAnalytics == nil)
    }

    @Test func `Decode URL type add region invalid sidecar URL degrades to nil`() {
        let data = decodeAddRegion([
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com"),
            URLQueryItem(name: "sidecar-url", value: "not a valid url")
        ])
        #expect(data != nil)
        #expect(data?.sidecarURL == nil)
    }

    // MARK: - Raw-String Decoding (percent-encoding behavior)

    // The queryItems-based tests above auto-encode values on the way out, so they
    // can never exercise encoding bugs. These two lock in the documented contract:
    // nested URLs MUST be percent-encoded; an unencoded `&` truncates.

    @Test func `Decode URL type add region raw string percent encoded nested URL`() {
        let url = URL(string: "onebusaway://add-region?name=Raw%20Region&oba-url=https%3A%2F%2Foba.example.com&sidecar-url=https%3A%2F%2Fobaco.example.com%2Fapi%3Fa%3D1%26b%3D2&umami-url=https%3A%2F%2Fanalytics.example.com&umami-id=site-uuid-123")!

        guard case .addRegion(let data)? = router.decodeURLType(from: url) else {
            Issue.record("Expected addRegion URLType")
            return
        }

        #expect(data?.name == "Raw Region")
        #expect(data?.obaURL.absoluteString == "https://oba.example.com")
        #expect(data?.sidecarURL?.absoluteString == "https://obaco.example.com/api?a=1&b=2")
        #expect(data?.umamiAnalytics?.id == "site-uuid-123")
    }

    @Test func `Decode URL type add region raw string unencoded ampersand truncates`() {
        let url = URL(string: "onebusaway://add-region?name=Raw&oba-url=https://oba.example.com&sidecar-url=https://obaco.example.com/api?a=1&b=2")!

        guard case .addRegion(let data)? = router.decodeURLType(from: url) else {
            Issue.record("Expected addRegion URLType")
            return
        }

        // The unencoded `&` ends the sidecar-url value; `b=2` parses as a separate
        // (ignored) query item. This is documented behavior, not a bug.
        #expect(data?.sidecarURL?.absoluteString == "https://obaco.example.com/api?a=1")
    }
}

// MARK: - Helper Extensions

private extension URLComponents {
    func queryItem(named name: String) -> URLQueryItem? {
        return queryItems?.first { $0.name == name }
    }
}