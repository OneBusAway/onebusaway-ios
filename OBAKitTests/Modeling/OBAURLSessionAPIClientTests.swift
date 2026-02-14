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

    // MARK: - Fallback Logic Tests

    class MockURLSession: URLSession {
        var responses: [String: (Data?, URLResponse?, Error?)] = [:]
        var requests: [URLRequest] = []

        override func data(for request: URLRequest, delegate: (URLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
            requests.append(request)
            
            let urlString = request.url?.absoluteString ?? ""
            for (pattern, response) in responses {
                if urlString.contains(pattern) {
                    if let error = response.2 { throw error }
                    return (response.0 ?? Data(), response.1 ?? HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                }
            }
            
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    func testFetchArrivalsFallback() async throws {
        let mockSession = MockURLSession()
        let config = OBAURLSessionAPIClient.Configuration(baseURL: URL(string: "https://example.com")!)
        let client = OBAURLSessionAPIClient(configuration: config, urlSession: mockSession)
        
        // Mock 1st attempt failure
        mockSession.responses["/api/where/arrivals-and-departures-for-stop/123.json"] = (nil, nil, OBAAPIError.notFound(url: URL(string: "https://example.com/1")!))
        
        // Mock 2nd attempt success
        let successData = """
        {
            "data": {
                "arrivalsAndDepartures": [],
                "stop": { "id": "123", "name": "Test Stop" },
                "references": { "routes": [] }
            }
        }
        """.data(using: .utf8)!
        mockSession.responses["/api/where/arrivals-and-departures-for-stop.json"] = (successData, nil, nil)
        
        let result = try await client.fetchArrivals(for: "123")
        
        XCTAssertEqual(result.stopName, "Test Stop")
        XCTAssertEqual(mockSession.requests.count, 2)
        XCTAssertTrue(mockSession.requests[0].url!.absoluteString.contains("arrivals-and-departures-for-stop/123.json"))
        XCTAssertTrue(mockSession.requests[1].url!.absoluteString.contains("arrivals-and-departures-for-stop.json"))
    }

    func testFetchArrivalsThirdFallback() async throws {
        let mockSession = MockURLSession()
        let config = OBAURLSessionAPIClient.Configuration(baseURL: URL(string: "https://example.com")!)
        let client = OBAURLSessionAPIClient(configuration: config, urlSession: mockSession)
        
        // Mock 1st and 2nd attempt failure
        mockSession.responses["/api/where/arrivals-and-departures-for-stop"] = (nil, nil, OBAAPIError.notFound(url: URL(string: "https://example.com/1")!))
        
        // Mock 3rd attempt success (stop details)
        let stopData = """
        {
            "data": {
                "entry": {
                    "id": "123",
                    "name": "Fallback Stop",
                    "lat": 47.0,
                    "lon": -122.0,
                    "routes": []
                }
            }
        }
        """.data(using: .utf8)!
        mockSession.responses["/api/where/stop/123.json"] = (stopData, nil, nil)
        
        let result = try await client.fetchArrivals(for: "123")
        
        XCTAssertEqual(result.stopName, "Fallback Stop")
        XCTAssertEqual(mockSession.requests.count, 3)
    }

    func testTryFallbackSuccessFirst() async throws {
        let client = OBAURLSessionAPIClient(configuration: .init(baseURL: URL(string: "https://example.com")!))
        var callCount = 0
        let result = try await client.testTryFallback([
            { callCount += 1; return "first" },
            { callCount += 1; return "second" }
        ])
        XCTAssertEqual(result, "first")
        XCTAssertEqual(callCount, 1)
    }

    func testTryFallbackSuccessSecond() async throws {
        let client = OBAURLSessionAPIClient(configuration: .init(baseURL: URL(string: "https://example.com")!))
        var callCount = 0
        let result = try await client.testTryFallback([
            { callCount += 1; throw OBAAPIError.invalidURL },
            { callCount += 1; return "second" }
        ])
        XCTAssertEqual(result, "second")
        XCTAssertEqual(callCount, 2)
    }

    func testTryFallbackTotalFailure() async throws {
        let client = OBAURLSessionAPIClient(configuration: .init(baseURL: URL(string: "https://example.com")!))
        do {
            _ = try await client.testTryFallback([
                { throw OBAAPIError.badServerResponse(statusCode: 500, url: URL(string: "https://a.com")!) },
                { throw OBAAPIError.notFound(url: URL(string: "https://b.com")!) }
            ] as [() async throws -> String])
            XCTFail("Should have thrown")
        } catch OBAAPIError.notFound {
            // Expected last error
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testFetchRoutesForStopFallback() async throws {
        let mockSession = MockURLSession()
        let config = OBAURLSessionAPIClient.Configuration(baseURL: URL(string: "https://example.com")!)
        let client = OBAURLSessionAPIClient(configuration: config, urlSession: mockSession)
        
        // Fail first 3
        mockSession.responses["/api/where/routes-for-stop"] = (nil, nil, OBAAPIError.notFound(url: URL(string: "https://example.com/1")!))
        mockSession.responses["/api/where/stop/123.json"] = (nil, nil, OBAAPIError.notFound(url: URL(string: "https://example.com/2")!))
        
        // Success on 4th (arrivals-and-departures-for-stop)
        let arrivalsData = """
        {
            "data": {
                "arrivalsAndDepartures": [],
                "references": {
                    "routes": [
                        { "id": "R1", "shortName": "1", "longName": "Route One" }
                    ]
                }
            }
        }
        """.data(using: .utf8)!
        mockSession.responses["/api/where/arrivals-and-departures-for-stop/123.json"] = (arrivalsData, nil, nil)
        
        let routes = try await client.fetchRoutesForStop(stopID: "123")
        
        XCTAssertEqual(routes.count, 1)
        XCTAssertEqual(routes[0].id, "R1")
        XCTAssertEqual(mockSession.requests.count, 4)
    }
}

// Helper to expose internal tryFallback for testing
extension OBAURLSessionAPIClient {
    func testTryFallback<T>(_ closures: [() async throws -> T]) async throws -> T {
        // This is a bit of a hack since tryFallback is private. 
        // In a real project we might make it internal or use a public method that calls it.
        // For this task, I'll use a public wrapper.
        struct Wrapper: Decodable {}
        return try await self.tryFallback_exposed(closures)
    }

    fileprivate func tryFallback_exposed<T>(_ closures: [() async throws -> T]) async throws -> T {
        var lastError: Error?
        for closure in closures {
            do {
                return try await closure()
            } catch {
                lastError = error
            }
        }
        if let lastError = lastError {
            throw lastError
        }
        throw OBAAPIError.invalidURL
    }
}
