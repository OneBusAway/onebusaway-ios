//
//  OBAURLSessionAPIClientTests.swift
//  OBAKitTests
//
//  Created by Prince Yadav on 01/01/26.
//

import XCTest
@testable import OBAKitCore
import CoreLocation

class OBAURLSessionAPIClientTests: XCTestCase {
    
    var client: OBAURLSessionAPIClient!
    
    override func setUp() {
        super.setUp()
        let config = OBAURLSessionAPIClient.Configuration(baseURL: URL(string: "https://example.com/api")!)
        client = OBAURLSessionAPIClient(configuration: config)
    }
    
    // MARK: - buildURL Tests
    
    func testBuildURLPathJoining() throws {
        let queryItems = [URLQueryItem(name: "foo", value: "bar")]
        
        // Case 1: Base URL has trailing slash, path has leading slash
        let config1 = OBAURLSessionAPIClient.Configuration(baseURL: URL(string: "https://example.com/api/")!)
        let client1 = OBAURLSessionAPIClient(configuration: config1)
        let url1 = try client1.buildURL(path: "/test.json", queryItems: queryItems)
        XCTAssertEqual(url1.absoluteString, "https://example.com/api/test.json?foo=bar")
        
        // Case 2: Base URL no trailing slash, path no leading slash
        let config2 = OBAURLSessionAPIClient.Configuration(baseURL: URL(string: "https://example.com/api")!)
        let client2 = OBAURLSessionAPIClient(configuration: config2)
        let url2 = try client2.buildURL(path: "test.json", queryItems: queryItems)
        XCTAssertEqual(url2.absoluteString, "https://example.com/api/test.json?foo=bar")
        
        // Case 3: Base URL has trailing slash, path no leading slash
        let config3 = OBAURLSessionAPIClient.Configuration(baseURL: URL(string: "https://example.com/api/")!)
        let client3 = OBAURLSessionAPIClient(configuration: config3)
        let url3 = try client3.buildURL(path: "test.json", queryItems: queryItems)
        XCTAssertEqual(url3.absoluteString, "https://example.com/api/test.json?foo=bar")
        
        // Case 4: Base URL no trailing slash, path has leading slash
        let config4 = OBAURLSessionAPIClient.Configuration(baseURL: URL(string: "https://example.com/api")!)
        let client4 = OBAURLSessionAPIClient(configuration: config4)
        let url4 = try client4.buildURL(path: "/test.json", queryItems: queryItems)
        XCTAssertEqual(url4.absoluteString, "https://example.com/api/test.json?foo=bar")
    }
    
    // MARK: - decodePolyline Tests
    
    func testDecodePolylineValid() {
        // Simple polyline for (38.5, -120.2), (40.7, -120.95), (43.252, -126.453)
        let encoded = "_p~iF~ps|U_ulLnnqC_mqNvxq`@"
        let coords = OBAURLSessionAPIClient.decodePolyline(encoded)
        
        XCTAssertEqual(coords.count, 3)
        XCTAssertEqual(coords[0].latitude, 38.5, accuracy: 0.0001)
        XCTAssertEqual(coords[0].longitude, -120.2, accuracy: 0.0001)
        XCTAssertEqual(coords[1].latitude, 40.7, accuracy: 0.0001)
        XCTAssertEqual(coords[1].longitude, -120.95, accuracy: 0.0001)
        XCTAssertEqual(coords[2].latitude, 43.252, accuracy: 0.0001)
        XCTAssertEqual(coords[2].longitude, -126.453, accuracy: 0.0001)
    }
    
    func testDecodePolylineEmpty() {
        let coords = OBAURLSessionAPIClient.decodePolyline("")
        XCTAssertTrue(coords.isEmpty)
    }
    
    func testDecodePolylineMalformed() {
        // Ends abruptly
        let encoded = "_p~iF"
        let coords = OBAURLSessionAPIClient.decodePolyline(encoded)
        XCTAssertTrue(coords.isEmpty, "Should return empty if it can't decode a full pair")
    }
    
    func testDecodePolylineInvalidCharacters() {
        // Contains non-ASCII or invalid polyline chars
        let encoded = "_p~iF\u{1F600}"
        let coords = OBAURLSessionAPIClient.decodePolyline(encoded)
        // Should stop decoding at the emoji
        XCTAssertTrue(coords.isEmpty)
    }
}
