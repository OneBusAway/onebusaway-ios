//
//  OBAWatchDTOsTests.swift
//  OBAKitTests
//
//  Created by Prince Yadav on 01/01/26.
//

import XCTest
@testable import OBAKitCore
import CoreLocation

class OBAWatchDTOsTests: XCTestCase {
    
    // MARK: - OBARawArrival.toDomainArrival Tests
    
    func testToDomainArrivalScheduleStatus() {
        // Reference time: 10:00 AM
        let now = Date(timeIntervalSince1970: 1672567200) // 2023-01-01 10:00:00 UTC
        
        // Base arrival with scheduled time at 10:00 AM
        let baseArrival = OBARawArrival(
            stopID: "1",
            routeID: "10",
            tripID: "100",
            routeShortName: "10",
            tripHeadsign: "Downtown",
            vehicleID: "V1",
            predicted: true,
            predictedArrivalTime: nil,
            predictedDepartureTime: nil,
            scheduledArrivalTime: now,
            scheduledDepartureTime: now
        )
        
        // Test Case 1: On Time (deviation 0 minutes)
        // predicted = scheduled = 10:00
        var arrival = baseArrival
        var domainArrival = arrival.toDomainArrival(referenceDate: now)
        XCTAssertEqual(domainArrival.scheduleStatus, .onTime, "Status should be onTime for 0 deviation")
        
        // Test Case 2: Early (deviation < -1.5 minutes)
        // scheduled = 10:00, predicted = 09:58 (2 minutes early)
        let earlyDate = now.addingTimeInterval(-120)
        arrival = OBARawArrival(
            stopID: "1",
            routeID: "10",
            tripID: "100",
            routeShortName: "10",
            tripHeadsign: "Downtown",
            vehicleID: "V1",
            predicted: true,
            predictedArrivalTime: earlyDate,
            predictedDepartureTime: earlyDate,
            scheduledArrivalTime: now,
            scheduledDepartureTime: now
        )
        domainArrival = arrival.toDomainArrival(referenceDate: now)
        XCTAssertEqual(domainArrival.scheduleStatus, .early, "Status should be early for -2 min deviation")
        
        // Test Case 3: Late (deviation > 1.5 minutes)
        // scheduled = 10:00, predicted = 10:02 (2 minutes late)
        let lateDate = now.addingTimeInterval(120)
        arrival = OBARawArrival(
            stopID: "1",
            routeID: "10",
            tripID: "100",
            routeShortName: "10",
            tripHeadsign: "Downtown",
            vehicleID: "V1",
            predicted: true,
            predictedArrivalTime: lateDate,
            predictedDepartureTime: lateDate,
            scheduledArrivalTime: now,
            scheduledDepartureTime: now
        )
        domainArrival = arrival.toDomainArrival(referenceDate: now)
        XCTAssertEqual(domainArrival.scheduleStatus, .delayed, "Status should be delayed for +2 min deviation")
        
        // Test Case 4: Slightly Early but still On Time (deviation -1.0 minute)
        // scheduled = 10:00, predicted = 09:59
        let slightlyEarlyDate = now.addingTimeInterval(-60)
        arrival = OBARawArrival(
            stopID: "1",
            routeID: "10",
            tripID: "100",
            routeShortName: "10",
            tripHeadsign: "Downtown",
            vehicleID: "V1",
            predicted: true,
            predictedArrivalTime: slightlyEarlyDate,
            predictedDepartureTime: slightlyEarlyDate,
            scheduledArrivalTime: now,
            scheduledDepartureTime: now
        )
        domainArrival = arrival.toDomainArrival(referenceDate: now)
        XCTAssertEqual(domainArrival.scheduleStatus, .onTime, "Status should be onTime for -1 min deviation")
        
        // Test Case 5: Slightly Late but still On Time (deviation +1.0 minute)
        // scheduled = 10:00, predicted = 10:01
        let slightlyLateDate = now.addingTimeInterval(60)
        arrival = OBARawArrival(
            stopID: "1",
            routeID: "10",
            tripID: "100",
            routeShortName: "10",
            tripHeadsign: "Downtown",
            vehicleID: "V1",
            predicted: true,
            predictedArrivalTime: slightlyLateDate,
            predictedDepartureTime: slightlyLateDate,
            scheduledArrivalTime: now,
            scheduledDepartureTime: now
        )
        domainArrival = arrival.toDomainArrival(referenceDate: now)
        XCTAssertEqual(domainArrival.scheduleStatus, .onTime, "Status should be onTime for +1 min deviation")
        
        // Test Case 6: Not Predicted (Unknown status)
        arrival = OBARawArrival(
            stopID: "1",
            routeID: "10",
            tripID: "100",
            routeShortName: "10",
            tripHeadsign: "Downtown",
            vehicleID: "V1",
            predicted: false,
            predictedArrivalTime: nil,
            predictedDepartureTime: nil,
            scheduledArrivalTime: now,
            scheduledDepartureTime: now
        )
        domainArrival = arrival.toDomainArrival(referenceDate: now)
        XCTAssertEqual(domainArrival.scheduleStatus, .unknown, "Status should be unknown when not predicted")
    }
    
    // MARK: - OBAStop Decoding Tests
    
    struct TestStopContainer: Decodable {
        let stop: OBARawStopResponse.StopEntry
    }
    
    func testStopDecodingWithPolymorphicCode() throws {
        // Test Case 1: Code is a String
        let jsonString = """
        {
            "stop": {
                "id": "1",
                "name": "Test Stop",
                "lat": 47.6,
                "lon": -122.3,
                "code": "12345",
                "direction": "N"
            }
        }
        """
        let jsonData = jsonString.data(using: .utf8)!
        let container = try JSONDecoder().decode(TestStopContainer.self, from: jsonData)
        XCTAssertEqual(container.stop.code, "12345", "Should decode string code correctly")
        
        // Test Case 2: Code is an Int
        let jsonInt = """
        {
            "stop": {
                "id": "1",
                "name": "Test Stop",
                "lat": 47.6,
                "lon": -122.3,
                "code": 67890,
                "direction": "S"
            }
        }
        """
        let jsonIntData = jsonInt.data(using: .utf8)!
        let containerInt = try JSONDecoder().decode(TestStopContainer.self, from: jsonIntData)
        XCTAssertEqual(containerInt.stop.code, "67890", "Should decode int code as string correctly")
        
        // Test Case 3: Code is missing
        let jsonMissing = """
        {
            "stop": {
                "id": "1",
                "name": "Test Stop",
                "lat": 47.6,
                "lon": -122.3,
                "direction": "E"
            }
        }
        """
        let jsonMissingData = jsonMissing.data(using: .utf8)!
        let containerMissing = try JSONDecoder().decode(TestStopContainer.self, from: jsonMissingData)
        XCTAssertNil(containerMissing.stop.code, "Should handle missing code gracefully")
    }
    
    // MARK: - OBARawListResponse Tests
    
    struct MockElement: Decodable, Sendable, Equatable {
        let value: String
    }
    
    func testListResponseHandling() throws {
        // Test Case 1: Standard Envelope with 'list' key
        let jsonEnvelopeList = """
        {
            "code": 200,
            "version": 2,
            "data": {
                "list": { "value": "test_list" },
                "references": { "routes": [] }
            }
        }
        """
        let dataList = jsonEnvelopeList.data(using: .utf8)!
        let responseList = try JSONDecoder().decode(OBARawListResponse<MockElement>.self, from: dataList)
        XCTAssertEqual(responseList.list.value, "test_list", "Should decode standard envelope with list key")
        
        // Test Case 2: Standard Envelope with 'entry' key
        let jsonEnvelopeEntry = """
        {
            "code": 200,
            "version": 2,
            "data": {
                "entry": { "value": "test_entry" }
            }
        }
        """
        let dataEntry = jsonEnvelopeEntry.data(using: .utf8)!
        let responseEntry = try JSONDecoder().decode(OBARawListResponse<MockElement>.self, from: dataEntry)
        XCTAssertEqual(responseEntry.list.value, "test_entry", "Should decode standard envelope with entry key")
        
        // Test Case 3: Bare Element (No Envelope)
        let jsonBare = """
        {
            "value": "test_bare"
        }
        """
        let dataBare = jsonBare.data(using: .utf8)!
        let responseBare = try JSONDecoder().decode(OBARawListResponse<MockElement>.self, from: dataBare)
        XCTAssertEqual(responseBare.list.value, "test_bare", "Should decode bare element without envelope")
    }
    
    // MARK: - OBAURLSessionAPIClient Tests
    
    func testBuildURL() throws {
        let config = OBAURLSessionAPIClient.Configuration(baseURL: URL(string: "https://api.onebusaway.org/api")!)
        let client = OBAURLSessionAPIClient(configuration: config)
        
        // Test Case 1: Base URL without trailing slash, path without leading slash
        // (Expected: https://api.onebusaway.org/api/where/stop/1.json)
        var url = try client.buildURL(path: "where/stop/1.json", queryItems: [])
        XCTAssertEqual(url.absoluteString, "https://api.onebusaway.org/api/where/stop/1.json")
        
        // Test Case 2: Base URL with trailing slash, path with leading slash
        // (Expected: https://api.onebusaway.org/api/where/stop/1.json - no double slash)
        let configSlash = OBAURLSessionAPIClient.Configuration(baseURL: URL(string: "https://api.onebusaway.org/api/")!)
        let clientSlash = OBAURLSessionAPIClient(configuration: configSlash)
        url = try clientSlash.buildURL(path: "/where/stop/1.json", queryItems: [])
        XCTAssertEqual(url.absoluteString, "https://api.onebusaway.org/api/where/stop/1.json")
        
        // Test Case 3: Empty path
        url = try client.buildURL(path: "", queryItems: [])
        XCTAssertEqual(url.absoluteString, "https://api.onebusaway.org/api/")
        
        // Test Case 4: Query items
        let queryItems = [URLQueryItem(name: "key", value: "test_key"), URLQueryItem(name: "foo", value: "bar")]
        url = try client.buildURL(path: "test.json", queryItems: queryItems)
        XCTAssertTrue(url.absoluteString.contains("key=test_key"))
        XCTAssertTrue(url.absoluteString.contains("foo=bar"))
    }
    
    func testDecodePolyline() {
        // Test Case 1: Empty string
        let emptyCoords = OBAURLSessionAPIClient.decodePolyline("")
        XCTAssertTrue(emptyCoords.isEmpty)
        
        // Test Case 2: Single point (0,0) -> "???"
        // Encoded (0,0) is usually just "??"
        let zeroCoords = OBAURLSessionAPIClient.decodePolyline("??")
        XCTAssertEqual(zeroCoords.count, 1)
        XCTAssertEqual(zeroCoords[0].latitude, 0.0, accuracy: 0.00001)
        XCTAssertEqual(zeroCoords[0].longitude, 0.0, accuracy: 0.00001)
        
        // Test Case 3: Known polyline (example from Google docs: (38.5, -120.2) -> "_p~iF~ps|U")
        let coords = OBAURLSessionAPIClient.decodePolyline("_p~iF~ps|U")
        XCTAssertEqual(coords.count, 1)
        XCTAssertEqual(coords[0].latitude, 38.5, accuracy: 0.00001)
        XCTAssertEqual(coords[0].longitude, -120.2, accuracy: 0.00001)
        
        // Test Case 4: Malformed input (should not crash)
        let malformedCoords = OBAURLSessionAPIClient.decodePolyline("!!! malformed !!!")
        // The decoder should just stop when it hits invalid data
        XCTAssert(malformedCoords.count >= 0)
    }
}
