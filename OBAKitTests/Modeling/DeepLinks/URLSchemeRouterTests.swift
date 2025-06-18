//
//  URLSchemeRouterTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import XCTest
import Nimble
@testable import OBAKitCore

class URLSchemeRouterTests: XCTestCase {
    
    var router: URLSchemeRouter!
    
    override func setUp() {
        super.setUp()
        router = URLSchemeRouter(scheme: "onebusaway")
    }
    
    // MARK: - Initialization Tests
    
    func test_initialization_setsScheme() {
        let customRouter = URLSchemeRouter(scheme: "customscheme")
        // Test by trying to encode a URL and checking the scheme
        let url = customRouter.encodeViewStop(stopID: "123", regionID: 1)
        expect(url.scheme) == "customscheme"
    }
    
    // MARK: - View Stop URL Tests
    
    func test_encodeViewStop_createsValidURL() {
        let stopID = "12345"
        let regionID = 1
        
        let url = router.encodeViewStop(stopID: stopID, regionID: regionID)
        
        expect(url.scheme) == "onebusaway"
        expect(url.host) == "view-stop"
        
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        expect(components?.queryItems?.count) == 2
        expect(components?.queryItems?.contains { $0.name == "stopID" && $0.value == stopID }) == true
        expect(components?.queryItems?.contains { $0.name == "regionID" && $0.value == String(regionID) }) == true
    }
    
    func test_decodeURLType_viewStop_decodesValidURL() {
        // First encode a URL
        let stopID = "67890"
        let regionID = 2
        let url = router.encodeViewStop(stopID: stopID, regionID: regionID)
        
        // Then decode it
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .viewStop(let data):
            expect(data.stopID) == stopID
            expect(data.regionID) == regionID
        default:
            fail("Expected viewStop URLType")
        }
    }
    
    func test_decodeURLType_viewStop_returnsNilForMissingStopID() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "view-stop"
        components.queryItems = [URLQueryItem(name: "regionID", value: "1")]
        
        guard let url = components.url else {
            fail("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        expect(result).to(beNil())
    }
    
    func test_decodeURLType_viewStop_returnsNilForMissingRegionID() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "view-stop"
        components.queryItems = [URLQueryItem(name: "stopID", value: "12345")]
        
        guard let url = components.url else {
            fail("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        expect(result).to(beNil())
    }
    
    func test_decodeURLType_viewStop_returnsNilForInvalidRegionID() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "view-stop"
        components.queryItems = [
            URLQueryItem(name: "stopID", value: "12345"),
            URLQueryItem(name: "regionID", value: "not-a-number")
        ]
        
        guard let url = components.url else {
            fail("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        expect(result).to(beNil())
    }
    
    // MARK: - Add Region URL Tests
    
    func test_decodeURLType_addRegion_decodesValidURLWithOTPURL() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com"),
            URLQueryItem(name: "otp-url", value: "https://otp.example.com")
        ]
        
        guard let url = components.url else {
            fail("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .addRegion(let data):
            expect(data).toNot(beNil())
            expect(data?.name) == "Test Region"
            expect(data?.obaURL.absoluteString) == "https://oba.example.com"
            expect(data?.otpURL?.absoluteString) == "https://otp.example.com"
        default:
            fail("Expected addRegion URLType")
        }
    }
    
    func test_decodeURLType_addRegion_decodesValidURLWithoutOTPURL() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com")
        ]
        
        guard let url = components.url else {
            fail("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .addRegion(let data):
            expect(data).toNot(beNil())
            expect(data?.name) == "Test Region"
            expect(data?.obaURL.absoluteString) == "https://oba.example.com"
            expect(data?.otpURL).to(beNil())
        default:
            fail("Expected addRegion URLType")
        }
    }
    
    func test_decodeURLType_addRegion_returnsNilDataForMissingName() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "oba-url", value: "https://oba.example.com")
        ]
        
        guard let url = components.url else {
            fail("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .addRegion(let data):
            expect(data).to(beNil())
        default:
            fail("Expected addRegion URLType with nil data")
        }
    }
    
    func test_decodeURLType_addRegion_returnsNilDataForMissingOBAURL() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region")
        ]
        
        guard let url = components.url else {
            fail("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .addRegion(let data):
            expect(data).to(beNil())
        default:
            fail("Expected addRegion URLType with nil data")
        }
    }
    
    func test_decodeURLType_addRegion_returnsNilDataForEmptyOBAURL() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "")
        ]
        
        guard let url = components.url else {
            fail("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .addRegion(let data):
            expect(data).to(beNil())
        default:
            fail("Expected addRegion URLType with nil data")
        }
    }
    
    func test_decodeURLType_addRegion_handlesEmptyOTPURL() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com"),
            URLQueryItem(name: "otp-url", value: "")
        ]
        
        guard let url = components.url else {
            fail("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .addRegion(let data):
            expect(data).toNot(beNil())
            expect(data?.name) == "Test Region"
            expect(data?.obaURL.absoluteString) == "https://oba.example.com"
            expect(data?.otpURL).to(beNil())
        default:
            fail("Expected addRegion URLType")
        }
    }
    
    // MARK: - General URL Decoding Tests
    
    func test_decodeURLType_returnsNilForUnknownHost() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "unknown-host"
        components.queryItems = [URLQueryItem(name: "test", value: "value")]
        
        guard let url = components.url else {
            fail("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        expect(result).to(beNil())
    }
    
    func test_decodeURLType_returnsNilForInvalidURL() {
        let url = URL(string: "not://a/valid/url")!
        let result = router.decodeURLType(from: url)
        expect(result).to(beNil())
    }
    
    func test_decodeURLType_returnsNilForURLWithoutHost() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.path = "/some/path"
        
        guard let url = components.url else {
            fail("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        expect(result).to(beNil())
    }
    
    // MARK: - Edge Cases
    
    func test_encodeViewStop_handlesSpecialCharactersInStopID() {
        let stopID = "stop+with/special&chars=123"
        let regionID = 1
        
        let url = router.encodeViewStop(stopID: stopID, regionID: regionID)
        
        // Decode and verify
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .viewStop(let data):
            expect(data.stopID) == stopID
            expect(data.regionID) == regionID
        default:
            fail("Expected viewStop URLType")
        }
    }
    
    func test_decodeURLType_addRegion_handlesEncodedURLValues() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region with Spaces"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com/api?param=value&other=123")
        ]
        
        guard let url = components.url else {
            fail("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .addRegion(let data):
            expect(data).toNot(beNil())
            expect(data?.name) == "Test Region with Spaces"
            expect(data?.obaURL.absoluteString) == "https://oba.example.com/api?param=value&other=123"
        default:
            fail("Expected addRegion URLType")
        }
    }
    
    func test_decodeURLType_handlesEmptyQueryValues() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "view-stop"
        components.queryItems = [
            URLQueryItem(name: "stopID", value: ""),
            URLQueryItem(name: "regionID", value: "1")
        ]
        
        guard let url = components.url else {
            fail("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .viewStop(let data):
            expect(data.stopID) == ""
            expect(data.regionID) == 1
        default:
            fail("Expected viewStop URLType")
        }
    }
    
    // MARK: - URL Validation Tests
    
    func test_decodeURLType_addRegion_rejectsInvalidOBAURL() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "not a valid url")
        ]
        
        guard let url = components.url else {
            fail("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .addRegion(let data):
            expect(data).to(beNil())
        default:
            fail("Expected addRegion URLType with nil data")
        }
    }
    
    func test_decodeURLType_addRegion_rejectsWhitespaceOnlyOBAURL() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "   ")
        ]
        
        guard let url = components.url else {
            fail("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .addRegion(let data):
            expect(data).to(beNil())
        default:
            fail("Expected addRegion URLType with nil data")
        }
    }
    
    func test_decodeURLType_addRegion_rejectsInvalidOTPURL() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com"),
            URLQueryItem(name: "otp-url", value: "not a valid url")
        ]
        
        guard let url = components.url else {
            fail("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .addRegion(let data):
            expect(data).toNot(beNil())
            expect(data?.name) == "Test Region"
            expect(data?.obaURL.absoluteString) == "https://oba.example.com"
            expect(data?.otpURL).to(beNil()) // Invalid OTP URL should result in nil
        default:
            fail("Expected addRegion URLType")
        }
    }
    
    func test_decodeURLType_addRegion_acceptsValidPathOBAURL() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "/api/oba")
        ]
        
        guard let url = components.url else {
            fail("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .addRegion(let data):
            expect(data).toNot(beNil())
            expect(data?.name) == "Test Region"
            expect(data?.obaURL.absoluteString) == "/api/oba"
            expect(data?.otpURL).to(beNil())
        default:
            fail("Expected addRegion URLType")
        }
    }
    
    func test_decodeURLType_addRegion_acceptsValidPathOTPURL() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://oba.example.com"),
            URLQueryItem(name: "otp-url", value: "/api/otp")
        ]
        
        guard let url = components.url else {
            fail("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .addRegion(let data):
            expect(data).toNot(beNil())
            expect(data?.name) == "Test Region"
            expect(data?.obaURL.absoluteString) == "https://oba.example.com"
            expect(data?.otpURL?.absoluteString) == "/api/otp"
        default:
            fail("Expected addRegion URLType")
        }
    }
    
    func test_decodeURLType_addRegion_acceptsComplexValidURLs() {
        var components = URLComponents()
        components.scheme = "onebusaway"
        components.host = "add-region"
        components.queryItems = [
            URLQueryItem(name: "name", value: "Test Region"),
            URLQueryItem(name: "oba-url", value: "https://api.example.com:8080/oba/api?key=abc123&format=json"),
            URLQueryItem(name: "otp-url", value: "https://otp.example.com/otp/routers/default")
        ]
        
        guard let url = components.url else {
            fail("Failed to create URL")
            return
        }
        
        let result = router.decodeURLType(from: url)
        
        switch result {
        case .addRegion(let data):
            expect(data).toNot(beNil())
            expect(data?.name) == "Test Region"
            expect(data?.obaURL.absoluteString) == "https://api.example.com:8080/oba/api?key=abc123&format=json"
            expect(data?.otpURL?.absoluteString) == "https://otp.example.com/otp/routers/default"
        default:
            fail("Expected addRegion URLType")
        }
    }
}

// MARK: - Helper Extensions

private extension URLComponents {
    func queryItem(named name: String) -> URLQueryItem? {
        return queryItems?.first { $0.name == name }
    }
}