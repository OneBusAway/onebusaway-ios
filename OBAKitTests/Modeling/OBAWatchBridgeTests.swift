import XCTest
import CoreLocation
@testable import OBAKitCore

final class OBAWatchBridgeTests: XCTestCase {

    // MARK: - OBARawVehicleStatus Tests

    func testOBARawVehicleStatus_nestedLocationDecoding() throws {
        let json = """
        {
            "vehicleId": "1234",
            "lastUpdateTime": 1600000000000,
            "location": {
                "lat": 47.6062,
                "lon": -122.3321
            },
            "tripId": "trip_1"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let status = try decoder.decode(OBARawVehicleStatus.self, from: json)

        XCTAssertEqual(status.vehicleID, "1234")
        XCTAssertEqual(status.latitude, 47.6062)
        XCTAssertEqual(status.longitude, -122.3321)
        XCTAssertEqual(status.tripID, "trip_1")
    }

    func testOBARawVehicleStatus_missingLocation() throws {
        let json = """
        {
            "vehicleId": "1234",
            "tripId": "trip_1"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let status = try decoder.decode(OBARawVehicleStatus.self, from: json)

        XCTAssertEqual(status.vehicleID, "1234")
        XCTAssertNil(status.latitude)
        XCTAssertNil(status.longitude)
    }

    // MARK: - OBARawStopsForRouteResponse Tests

    func testOBARawStopsForRouteResponse_multiStageFallback() throws {
        // Test case 1: Standard data structure
        let jsonStandard = """
        {
            "data": {
                "entry": {
                    "stopIds": ["stop_1", "stop_2"]
                },
                "references": {
                    "stops": [{"id": "stop_1", "name": "Stop 1", "lat": 47.0, "lon": -122.0}]
                }
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(OBARawStopsForRouteResponse.self, from: jsonStandard)
        XCTAssertEqual(response.data.stopIds.count, 2)
        XCTAssertEqual(response.data.references?.stops.count, 1)

        // Test case 2: Fallback (direct entry/references)
        let jsonFallback = """
        {
            "data": {
                "stopIds": ["stop_3"],
                "stops": [{"id": "stop_3", "name": "Stop 3", "lat": 48.0, "lon": -123.0}]
            }
        }
        """.data(using: .utf8)!

        let responseFallback = try decoder.decode(OBARawStopsForRouteResponse.self, from: jsonFallback)
        XCTAssertEqual(responseFallback.data.stopIds.count, 1)
        XCTAssertEqual(responseFallback.data.stopIds.first, "stop_3")
    }

    // MARK: - OBARawAgenciesWithCoverageResponse Tests

    func testOBARawAgenciesWithCoverageResponse_dualFormat() throws {
        // Format 1: Direct list in data
        let json1 = """
        {
            "data": {
                "list": [{"agencyId": "agency_1"}]
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response1 = try decoder.decode(OBARawAgenciesWithCoverageResponse.self, from: json1)
        XCTAssertEqual(response1.toDomainAgencies().count, 1)

        // Format 2: data is a direct array
        let json2 = """
        {
            "data": [{"agencyId": "agency_2"}]
        }
        """.data(using: .utf8)!

        let response2 = try decoder.decode(OBARawAgenciesWithCoverageResponse.self, from: json2)
        XCTAssertEqual(response2.toDomainAgencies().count, 1)
        XCTAssertEqual(response2.toDomainAgencies().first?.agencyID, "agency_2")
    }

    // MARK: - OBARawScheduleForStopResponse Tests

    func testOBARawScheduleForStopResponse_timestampConversion() throws {
        // 1600000000000 ms = 1600000000 s
        let json = """
        {
            "data": {
                "entry": {
                    "stopId": "stop_1",
                    "date": 1600000000000,
                    "stopRouteSchedules": [
                        {
                            "stopRouteDirectionSchedules": [
                                {
                                    "scheduleStopTimes": [
                                        { "tripId": "trip_1", "arrivalTime": 1600000000000, "departureTime": 1600000001000 }
                                    ]
                                }
                            ]
                        }
                    ]
                }
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(OBARawScheduleForStopResponse.self, from: json)
        let schedule = response.toDomainSchedule()
        XCTAssertEqual(schedule.date.timeIntervalSince1970, 1600000000.0)
        XCTAssertEqual(schedule.stopTimes.first?.arrivalTime.timeIntervalSince1970, 1600000000.0)
        XCTAssertEqual(schedule.stopTimes.first?.departureTime.timeIntervalSince1970, 1600000001.0)
    }

    // MARK: - OBARawStopResponse Tests

    func testOBARawStopResponse_fallbackPriority() throws {
        // Test case 1: Prefer 'entry' over 'stop' or root
        let json = """
        {
            "data": {
                "entry": { "id": "entry_id", "name": "Entry Stop", "lat": 1.0, "lon": 2.0 },
                "stop": { "id": "stop_id", "name": "Stop Name", "lat": 3.0, "lon": 4.0 },
                "id": "root_id", "name": "Root Stop", "lat": 5.0, "lon": 6.0
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(OBARawStopResponse.self, from: json)
        let stop = response.toDomainStop()
        XCTAssertEqual(stop.id, "entry_id")
        XCTAssertEqual(stop.name, "Entry Stop")

        // Test case 2: Fallback to 'stop' if 'entry' is missing
        let json2 = """
        {
            "data": {
                "stop": { "id": "stop_id", "name": "Stop Name", "lat": 3.0, "lon": 4.0 },
                "id": "root_id", "name": "Root Stop", "lat": 5.0, "lon": 6.0
            }
        }
        """.data(using: .utf8)!

        let response2 = try decoder.decode(OBARawStopResponse.self, from: json2)
        let stop2 = response2.toDomainStop()
        XCTAssertEqual(stop2.id, "stop_id")

        // Test case 3: Fallback to root if both 'entry' and 'stop' are missing
        let json3 = """
        {
            "data": {
                "id": "root_id", "name": "Root Stop", "lat": 5.0, "lon": 6.0
            }
        }
        """.data(using: .utf8)!

        let response3 = try decoder.decode(OBARawStopResponse.self, from: json3)
        let stop3 = response3.toDomainStop()
        XCTAssertEqual(stop3.id, "root_id")
    }

    // MARK: - OBAURLSessionAPIClient tryFallback Tests

    func testTryFallback_cancellationPropagation() async throws {
        let config = OBAURLSessionAPIClient.Configuration(baseURL: URL(string: "https://api.onebusaway.org/api/")!)
        let client = OBAURLSessionAPIClient(configuration: config)

        let task = Task {
            try await client.tryFallback([
                { throw CancellationError() },
                { return "success" }
            ])
        }

        do {
            _ = try await task.value
            XCTFail("Should have thrown CancellationError")
        } catch is CancellationError {
            // Success
        } catch {
            XCTFail("Threw unexpected error: \(error)")
        }
    }
}
