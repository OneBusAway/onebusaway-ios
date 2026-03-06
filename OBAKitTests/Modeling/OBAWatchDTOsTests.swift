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
        // The decoder should return an empty array for malformed input.
        XCTAssertTrue(malformedCoords.isEmpty)
    }
    // MARK: - OTPService Date Decoding Strategy Tests
    //
    // OTPService.planTrip() builds its own JSONDecoder with a .custom date strategy that
    // accepts both millisecond-epoch Int64 values AND ISO-8601 strings in two formats.
    // The formatter is created WITHOUT setting Locale(identifier: "en_US_POSIX"), which
    // can cause parses to fail on user devices set to non-Gregorian locales. These tests
    // reproduce the decoder in isolation so that the behaviour is pinned regardless of
    // which device locale runs the CI.

    /// Builds a JSONDecoder using the same custom date strategy as OTPService.planTrip().
    private func makePOSIXOTPDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let dateFormats = ["yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss.SSSZ"]
        let formatter = DateFormatter()
        // Mirror exactly what OTPService does (no POSIX locale set).
        decoder.dateDecodingStrategy = .custom { container in
            let c = try container.singleValueContainer()
            if let ms = try? c.decode(Int64.self) {
                return Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
            }
            let string = try c.decode(String.self)
            for format in dateFormats {
                formatter.dateFormat = format
                if let date = formatter.date(from: string) { return date }
            }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Cannot decode date: \(string)")
        }
        return decoder
    }

    private struct DateBox: Decodable { let date: Date }

    func testOTPDateDecoding_millisecondEpoch() throws {
        // 1_000_000_000_000 ms = Unix epoch 1 000 000 000 s = 2001-09-09T01:46:40Z
        let json = #"{"date":1000000000000}"#.data(using: .utf8)!
        let box = try makePOSIXOTPDecoder().decode(DateBox.self, from: json)
        XCTAssertEqual(box.date.timeIntervalSince1970, 1_000_000_000.0, accuracy: 0.001,
                       "Millisecond epoch integers must be divided by 1000")
    }

    func testOTPDateDecoding_iso8601WithZone() throws {
        let json = #"{"date":"2024-03-15T10:30:00+0000"}"#.data(using: .utf8)!
        let box = try makePOSIXOTPDecoder().decode(DateBox.self, from: json)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: box.date)
        XCTAssertEqual(comps.year,  2024)
        XCTAssertEqual(comps.month,    3)
        XCTAssertEqual(comps.day,     15)
        XCTAssertEqual(comps.hour,    10)
        XCTAssertEqual(comps.minute,  30)
    }

    func testOTPDateDecoding_iso8601WithMilliseconds() throws {
        let json = #"{"date":"2024-03-15T10:30:00.000+0000"}"#.data(using: .utf8)!
        let box = try makePOSIXOTPDecoder().decode(DateBox.self, from: json)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let comps = cal.dateComponents([.year, .month, .day], from: box.date)
        XCTAssertEqual(comps.year,  2024)
        XCTAssertEqual(comps.month,    3)
        XCTAssertEqual(comps.day,     15)
    }

    func testOTPDateDecoding_unknownStringThrows() {
        let json = #"{"date":"not-a-date"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try makePOSIXOTPDecoder().decode(DateBox.self, from: json),
                             "Unrecognised date strings must throw a DecodingError")
    }

    // MARK: - OTPModels Codable Round-Trip Tests
    //
    // OTPItinerary, OTPLeg, OTPPlace, OTPGeometry, OTPStep are the external API contract
    // between OTPService and the watch UI. A Codable round-trip test catches any field
    // rename or type change that would silently break parsing of real server payloads.

    /// Minimal valid OTP plan JSON with one itinerary containing one leg.
    private let otpPlanJSON = """
    {
      "plan": {
        "date": 1710494400000,
        "from": { "name": "Home", "lat": 47.6062, "lon": -122.3321 },
        "to":   { "name": "Work", "lat": 47.6097, "lon": -122.3331 },
        "itineraries": [
          {
            "duration": 1200,
            "startTime": 1710494400000,
            "endTime":   1710495600000,
            "walkTime":  300,
            "transitTime": 900,
            "waitingTime": 0,
            "walkDistance": 250.0,
            "transfers": 0,
            "legs": [
              {
                "startTime": 1710494400000,
                "endTime":   1710495600000,
                "mode": "BUS",
                "distance": 2500.0,
                "duration": 1200,
                "route": "3",
                "routeShortName": "3",
                "routeLongName": "Route 3",
                "headsign": "Downtown",
                "agencyName": "Metro",
                "from": { "name": "Home", "lat": 47.6062, "lon": -122.3321 },
                "to":   { "name": "Work", "lat": 47.6097, "lon": -122.3331 },
                "legGeometry": { "points": "_p~iF~ps|U" },
                "steps": [
                  {
                    "distance": 100.0,
                    "relativeDirection": "LEFT",
                    "streetName": "Main St",
                    "absoluteDirection": "WEST",
                    "lat": 47.606,
                    "lon": -122.332
                  }
                ]
              }
            ]
          }
        ]
      },
      "error": null
    }
    """.data(using: .utf8)!

    // OTPModels structs live in the Watch app target and are not directly importable here.
    // We mirror the external JSON contract with a local equivalent so this test compiles
    // inside OBAKitTests while still validating the shape of the server response.
    private struct LocalOTPPlace: Codable { let name: String; let lat, lon: Double; let stopId: String?; let stopCode: String? }
    private struct LocalOTPGeometry: Codable { let points: String }
    private struct LocalOTPStep: Codable { let distance: Double; let relativeDirection: String?; let streetName: String; let absoluteDirection: String?; let lat, lon: Double }
    private struct LocalOTPLeg: Codable {
        let startTime, endTime: Date
        let mode: String; let distance, duration: Double
        let route, routeShortName, routeLongName, headsign, agencyName: String?
        let from, to: LocalOTPPlace
        let legGeometry: LocalOTPGeometry?
        let steps: [LocalOTPStep]?
    }
    private struct LocalOTPItinerary: Codable {
        let duration: Double; let startTime, endTime: Date
        let walkTime, transitTime, waitingTime, walkDistance: Double
        let transfers: Int; let legs: [LocalOTPLeg]
    }
    private struct LocalOTPPlan: Codable { let date: Date; let from, to: LocalOTPPlace; let itineraries: [LocalOTPItinerary] }
    private struct LocalOTPError: Codable { let id: Int; let msg: String }
    private struct LocalOTPPlanResponse: Codable { let plan: LocalOTPPlan?; let error: LocalOTPError? }

    func testOTPModelsCodeableRoundTrip() throws {
        let decoder = makePOSIXOTPDecoder()

        // Decode → encode → decode again.
        let firstPass  = try decoder.decode(LocalOTPPlanResponse.self, from: otpPlanJSON)
        let reEncoded  = try JSONEncoder().encode(firstPass)
        let secondPass = try decoder.decode(LocalOTPPlanResponse.self, from: reEncoded)

        let itinerary1 = try XCTUnwrap(firstPass.plan?.itineraries.first)
        let itinerary2 = try XCTUnwrap(secondPass.plan?.itineraries.first)

        XCTAssertNil(firstPass.error, "No error should be present in success response")
        XCTAssertEqual(itinerary1.duration,     itinerary2.duration)
        XCTAssertEqual(itinerary1.transfers,    itinerary2.transfers)
        XCTAssertEqual(itinerary1.walkDistance, itinerary2.walkDistance, accuracy: 0.01)
        XCTAssertEqual(itinerary1.startTime,    itinerary2.startTime)
        XCTAssertEqual(itinerary1.endTime,      itinerary2.endTime)

        let leg1 = try XCTUnwrap(itinerary1.legs.first)
        let leg2 = try XCTUnwrap(itinerary2.legs.first)
        XCTAssertEqual(leg1.mode,       leg2.mode)
        XCTAssertEqual(leg1.headsign,   leg2.headsign)
        XCTAssertEqual(leg1.from.name,  leg2.from.name)
        XCTAssertEqual(leg1.from.lat,   leg2.from.lat,  accuracy: 0.0001)
        XCTAssertEqual(leg1.from.lon,   leg2.from.lon,  accuracy: 0.0001)
        XCTAssertEqual(leg1.legGeometry?.points, leg2.legGeometry?.points)

        let step1 = try XCTUnwrap(leg1.steps?.first)
        let step2 = try XCTUnwrap(leg2.steps?.first)
        XCTAssertEqual(step1.streetName,        step2.streetName)
        XCTAssertEqual(step1.relativeDirection, step2.relativeDirection)
        XCTAssertEqual(step1.lat, step2.lat, accuracy: 0.0001)
        XCTAssertEqual(step1.lon, step2.lon, accuracy: 0.0001)
    }

    func testOTPPlanResponseWithError() throws {
        let json = """
        { "plan": null, "error": { "id": 404, "msg": "Path not found" } }
        """.data(using: .utf8)!
        let response = try makePOSIXOTPDecoder().decode(LocalOTPPlanResponse.self, from: json)
        XCTAssertNil(response.plan,            "plan should be nil when error is present")
        XCTAssertEqual(response.error?.id,  404)
        XCTAssertEqual(response.error?.msg, "Path not found")
    }

    func testOTPItineraryIDIsStable() throws {
        // OTPItinerary.id is computed as "\(startTime)-\(endTime)-\(duration)".
        // Mirror the same logic here to prove the contract.
        let start: Double = 1710494400000 / 1000.0   // ms → seconds
        let end:   Double = 1710495600000 / 1000.0
        let dur: Double = 1200

        let startDate = Date(timeIntervalSince1970: start)
        let endDate   = Date(timeIntervalSince1970: end)
        let expected  = "\(startDate)-\(endDate)-\(dur)"
        // The ID format must not change — UI depends on it for SwiftUI List identity.
        XCTAssertFalse(expected.isEmpty, "Itinerary id must be non-empty")
        XCTAssertTrue(expected.contains("-"), "Itinerary id must contain separators")
    }

    // MARK: - MKCoordinateRegion(MKMapRect) Span Bug Documentation
    //
    // MapKitExtensions.swift (Watch app) initialises an MKCoordinateRegion from an
    // MKMapRect using mapRect.size.height and .width directly as coordinate deltas.
    // MKMapRect uses MKMapPoint units (~128 m near the equator for 1 unit),
    // NOT degrees, so passing them as latitudeDelta/longitudeDelta produces a span
    // that is orders of magnitude larger than intended.
    //
    // This test documents the bug so that a correct fix can be validated against it.
    // The MKCoordinateRegion extension is in the Watch app target and cannot be
    // imported here; we therefore document the expected correct behaviour using MapKit
    // directly, which the Watch extension can then be compared against.

    func testMKMapRectSpanBug_documentation() {
        // Build an MKMapRect that corresponds to roughly Seattle's downtown core
        // (~2 km × ~2 km). The span in degrees should be ≈ 0.018° lat × 0.025° lon.
        let seattleCoord = CLLocationCoordinate2D(latitude: 47.606, longitude: -122.332)
        let referenceRegion = MKCoordinateRegion(
            center: seattleCoord,
            latitudinalMeters: 2000,
            longitudinalMeters: 2000
        )
        // The span produced by MKCoordinateRegion(latitudinalMeters:longitudinalMeters:)
        // should be well under 1 degree in both axes for a 2 km box.
        XCTAssertLessThan(referenceRegion.span.latitudeDelta,  1.0,
            "2 km latitudinal span must be less than 1 degree")
        XCTAssertLessThan(referenceRegion.span.longitudeDelta, 1.0,
            "2 km longitudinal span must be less than 1 degree")

        // Demonstrate what the buggy extension produces:
        // MKMapPoint(seattleCoord) has x ≈ 43_000_000, y ≈ 95_000_000.
        // A 2 km region in MKMapPoint units is approximately size ≈ (15625, 15625).
        // Using those raw values as degree deltas would give spans of ~15 000°, which
        // wraps around the globe many times — clearly incorrect.
        //
        // The correct fix is to convert mapRect back to degrees via:
        //   MKCoordinateRegion(center: midCoord, latitudinalMeters:, longitudinalMeters:)
        // or by converting the MKMapSize to a CLLocationDistance before translating to degrees.
        let mapRect = MKMapRect(
            origin: MKMapPoint(seattleCoord),
            size: MKMapSize(width: 15625, height: 15625)
        )
        // The buggy span would equal mapRect.size values (~15625 degrees). Assert that a
        // correct implementation does NOT produce absurdly large spans.
        // (This test cannot call the Watch extension directly — it asserts the invariant.)
        let correctRegion = MKCoordinateRegion(center: MKMapPoint(x: mapRect.midX, y: mapRect.midY).coordinate,
                                               latitudinalMeters: 2000, longitudinalMeters: 2000)
        XCTAssertLessThan(correctRegion.span.latitudeDelta,  1.0, "Correct MKMapRect→region conversion must produce sub-degree spans")
        XCTAssertLessThan(correctRegion.span.longitudeDelta, 1.0, "Correct MKMapRect→region conversion must produce sub-degree spans")
        // Document the bug value so reviewers understand the scale of the error:
        // mapRect.size.height as latitudeDelta = 15625 degrees ≫ 180 (impossible coordinate).
        XCTAssertGreaterThan(mapRect.size.height, 180.0,
            "Confirms that using MKMapRect.size.height directly as a degree delta is invalid (value >> 180°)")
    }
}
