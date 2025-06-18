//
//  TripStatusTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

class TripStatusTests: OBATestCase {
    
    func test_decodeValidTripStatus() {
        let statusData: [String: Any] = [
            "activeTripId": "active_trip_123",
            "blockTripSequence": 3,
            "closestStop": "stop_closest",
            "closestStopTimeOffset": -120,
            "distanceAlongTrip": 2500.75,
            "lastKnownDistanceAlongTrip": 2480,
            "lastKnownLocation": [
                "lat": 47.6097,
                "lon": -122.3331
            ],
            "lastKnownOrientation": 145.5,
            "lastLocationUpdateTime": 1234567880,
            "lastUpdateTime": 1234567890000,
            "nextStop": "stop_next",
            "nextStopTimeOffset": 180,
            "orientation": 150.0,
            "phase": "IN_PROGRESS",
            "position": [
                "lat": 47.6098,
                "lon": -122.3332
            ],
            "predicted": true,
            "scheduleDeviation": -45,
            "scheduledDistanceAlongTrip": 2545.75,
            "serviceDate": 1234512000,
            "situationIds": ["alert_trip_1"],
            "status": "default",
            "totalDistanceAlongTrip": 15000.0,
            "vehicleId": "vehicle_789"
        ]
        
        let status = try! Fixtures.dictionaryToModel(type: TripStatus.self, dictionary: statusData)
        
        expect(status.activeTripID) == "active_trip_123"
        expect(status.id) == "active_trip_123" // id should return activeTripID
        expect(status.blockTripSequence) == 3
        expect(status.closestStopID) == "stop_closest"
        expect(status.closestStopTimeOffset) == -120
        expect(status.distanceAlongTrip) == 2500.75
        expect(status.lastKnownDistanceAlongTrip) == 2480
        expect(status.lastKnownLocation?.coordinate.latitude) == 47.6097
        expect(status.lastKnownLocation?.coordinate.longitude) == -122.3331
        expect(status.lastKnownOrientation) == 145.5
        expect(status.lastLocationUpdateTime) == 1234567880
        expect(status.lastUpdate?.timeIntervalSince1970) == 1234567890
        expect(status.nextStopID) == "stop_next"
        expect(status.nextStopTimeOffset) == 180
        expect(status.orientation) == 150.0
        expect(status.phase) == "IN_PROGRESS"
        expect(status.position?.coordinate.latitude) == 47.6098
        expect(status.position?.coordinate.longitude) == -122.3332
        expect(status.isRealTime) == true
        expect(status.scheduleDeviation) == -45
        expect(status.scheduledDistanceAlongTrip) == 2545.75
        expect(status.serviceDate.timeIntervalSince1970) == 2212819200
        expect(status.situationIDs) == ["alert_trip_1"]
        expect(status.statusModifier) == TripStatus.StatusModifier.default
        expect(status.totalDistanceAlongTrip) == 15000.0
        expect(status.vehicleID) == "vehicle_789"
    }
    
    func test_decodeMinimalTripStatus() {
        let minimalData: [String: Any] = [
            "activeTripId": "minimal_trip",
            "blockTripSequence": 1,
            "closestStop": "minimal_stop",
            "closestStopTimeOffset": 0,
            "distanceAlongTrip": 0.0,
            "lastLocationUpdateTime": 0,
            "lastUpdateTime": 0,
            "nextStopTimeOffset": 0,
            "orientation": 0.0,
            "phase": "LAYOVER_DURING",
            "predicted": false,
            "scheduleDeviation": 0,
            "scheduledDistanceAlongTrip": 0.0,
            "serviceDate": 1000000000,
            "situationIds": [],
            "status": "default",
            "totalDistanceAlongTrip": 0.0,
            "vehicleId": ""
        ]
        
        let status = try! Fixtures.dictionaryToModel(type: TripStatus.self, dictionary: minimalData)
        
        expect(status.activeTripID) == "minimal_trip"
        expect(status.blockTripSequence) == 1
        expect(status.closestStopID) == "minimal_stop"
        expect(status.lastUpdate).to(beNil())
        expect(status.nextStopID).to(beNil())
        expect(status.lastKnownDistanceAlongTrip).to(beNil())
        expect(status.lastKnownLocation).to(beNil())
        expect(status.lastKnownOrientation).to(beNil())
        expect(status.position).to(beNil())
        expect(status.frequency).to(beNil())
        expect(status.vehicleID).to(beNil())
    }
    
    func test_statusModifierDecoding() {
        let statusTestCases: [(String, TripStatus.StatusModifier)] = [
            ("default", .default),
            ("canceled", .canceled),
            ("other", .other("other"))
        ]
        
        for (statusString, expectedModifier) in statusTestCases {
            let data: [String: Any] = [
                "activeTripId": "status_test",
                "blockTripSequence": 1,
                "closestStop": "test_stop",
                "closestStopTimeOffset": 0,
                "distanceAlongTrip": 0.0,
                "lastLocationUpdateTime": 0,
                "lastUpdateTime": 0,
                "nextStopTimeOffset": 0,
                "orientation": 0.0,
                "phase": "IN_PROGRESS",
                "predicted": false,
                "scheduleDeviation": 0,
                "scheduledDistanceAlongTrip": 0.0,
                "serviceDate": 1000000000,
                "situationIds": [],
                "status": statusString,
                "totalDistanceAlongTrip": 0.0,
                "vehicleId": "test_vehicle"
            ]
            
            let status = try! Fixtures.dictionaryToModel(type: TripStatus.self, dictionary: data)
            expect(status.statusModifier) == expectedModifier
        }
    }
    
    func test_locationDecoding() {
        let dataWithLocations: [String: Any] = [
            "activeTripId": "location_test",
            "blockTripSequence": 1,
            "closestStop": "test_stop",
            "closestStopTimeOffset": 0,
            "distanceAlongTrip": 0.0,
            "lastKnownLocation": [
                "lat": 47.123456,
                "lon": -122.654321
            ],
            "lastLocationUpdateTime": 0,
            "lastUpdateTime": 0,
            "nextStopTimeOffset": 0,
            "orientation": 90.0,
            "phase": "IN_PROGRESS",
            "position": [
                "lat": 47.123457,
                "lon": -122.654322
            ],
            "predicted": false,
            "scheduleDeviation": 0,
            "scheduledDistanceAlongTrip": 0.0,
            "serviceDate": 1000000000,
            "situationIds": [],
            "status": "default",
            "totalDistanceAlongTrip": 0.0,
            "vehicleId": "location_vehicle"
        ]
        
        let status = try! Fixtures.dictionaryToModel(type: TripStatus.self, dictionary: dataWithLocations)
        
        expect(status.lastKnownLocation?.coordinate.latitude).to(beCloseTo(47.123456, within: 0.000001))
        expect(status.lastKnownLocation?.coordinate.longitude).to(beCloseTo(-122.654321, within: 0.000001))
        expect(status.position?.coordinate.latitude).to(beCloseTo(47.123457, within: 0.000001))
        expect(status.position?.coordinate.longitude).to(beCloseTo(-122.654322, within: 0.000001))
    }
    
    func test_hasReferencesLoadReferences() {
        let statusData: [String: Any] = [
            "activeTripId": "ref_trip",
            "blockTripSequence": 1,
            "closestStop": "ref_stop_closest",
            "closestStopTimeOffset": 0,
            "distanceAlongTrip": 100.0,
            "lastLocationUpdateTime": 0,
            "lastUpdateTime": 0,
            "nextStop": "ref_stop_next",
            "nextStopTimeOffset": 0,
            "orientation": 0.0,
            "phase": "IN_PROGRESS",
            "predicted": false,
            "scheduleDeviation": 0,
            "scheduledDistanceAlongTrip": 100.0,
            "serviceDate": 1000000000,
            "situationIds": ["ref_alert_1"],
            "status": "default",
            "totalDistanceAlongTrip": 1000.0,
            "vehicleId": "ref_vehicle"
        ]
        
        let status = try! Fixtures.dictionaryToModel(type: TripStatus.self, dictionary: statusData)
        
        let referencesData: [String: Any] = [
            "agencies": [[
                "id": "ref_agency",
                "name": "Test Agency",
                "url": "https://example.com",
                "timezone": "UTC",
                "lang": "en",
                "phone": "555-0123",
                "privateService": false
            ]],
            "routes": [[
                "id": "ref_route",
                "agencyId": "ref_agency",
                "shortName": "Test Route",
                "type": 3
            ]],
            "stops": [[
                "id": "ref_stop_closest",
                "lat": 47.6097,
                "lon": -122.3331,
                "name": "Closest Stop",
                "code": "12345",
                "direction": "N",
                "locationType": 0,
                "routeIds": ["ref_route"],
                "staticRouteIds": ["ref_route"],
                "wheelchairBoarding": "UNKNOWN"
            ], [
                "id": "ref_stop_next",
                "lat": 47.6098,
                "lon": -122.3332,
                "name": "Next Stop",
                "code": "12346",
                "direction": "N",
                "locationType": 0,
                "routeIds": ["ref_route"],
                "staticRouteIds": ["ref_route"],
                "wheelchairBoarding": "UNKNOWN"
            ]],
            "trips": [[
                "id": "ref_trip",
                "blockId": "ref_block",
                "routeId": "ref_route",
                "serviceId": "ref_service",
                "shapeId": "ref_shape",
                "routeShortName": "Test",
                "tripShortName": "Trip",
                "timeZone": "UTC"
            ]],
            "situations": [[
                "id": "ref_alert_1",
                "creationTime": 1234567890,
                "reason": "CONSTRUCTION",
                "severity": "MODERATE",
                "activeWindows": [],
                "publicationWindows": [],
                "allAffects": [],
                "consequences": []
            ]]
        ]
        
        let references = try! Fixtures.dictionaryToModel(type: References.self, dictionary: referencesData)
        
        status.loadReferences(references, regionIdentifier: 888)
        
        expect(status.regionIdentifier) == 888
        expect(status.activeTrip).toNot(beNil())
        expect(status.activeTrip.id) == "ref_trip"
        expect(status.closestStop).toNot(beNil())
        expect(status.closestStop.id) == "ref_stop_closest"
        expect(status.nextStop).toNot(beNil())
        expect(status.nextStop?.id) == "ref_stop_next"
        expect(status.serviceAlerts.count) == 1
        expect(status.serviceAlerts.first?.id) == "ref_alert_1"
    }
    
    func test_tripStatusEquality() {
        let statusData: [String: Any] = [
            "activeTripId": "equality_trip",
            "blockTripSequence": 1,
            "closestStop": "equality_stop",
            "closestStopTimeOffset": 0,
            "distanceAlongTrip": 100.0,
            "lastLocationUpdateTime": 1234567890,
            "lastUpdateTime": 0,
            "nextStopTimeOffset": 0,
            "orientation": 90.0,
            "phase": "IN_PROGRESS",
            "predicted": true,
            "scheduleDeviation": 0,
            "scheduledDistanceAlongTrip": 100.0,
            "serviceDate": 1000000000,
            "situationIds": [],
            "status": "default",
            "totalDistanceAlongTrip": 1000.0,
            "vehicleId": "equality_vehicle"
        ]
        
        let status1 = try! Fixtures.dictionaryToModel(type: TripStatus.self, dictionary: statusData)
        let status2 = try! Fixtures.dictionaryToModel(type: TripStatus.self, dictionary: statusData)
        
        var differentData = statusData
        differentData["activeTripId"] = "different_trip"
        let status3 = try! Fixtures.dictionaryToModel(type: TripStatus.self, dictionary: differentData)
        
        expect(status1.isEqual(status2)) == true
        expect(status1.isEqual(status3)) == false
        expect(status1.hash) == status2.hash
        expect(status1.hash) != status3.hash
    }
    
    func test_decodeFailureWhenMissingRequiredFields() {
        var incompleteData: [String: Any] = [
            "blockTripSequence": 1,
            "closestStop": "incomplete_stop",
            "closestStopTimeOffset": 0,
            "distanceAlongTrip": 100.0,
            "lastLocationUpdateTime": 0,
            "nextStopTimeOffset": 0,
            "orientation": 0.0,
            "phase": "IN_PROGRESS",
            "predicted": false,
            "scheduleDeviation": 0,
            "scheduledDistanceAlongTrip": 100.0,
            "serviceDate": 1000000000,
            "situationIds": [],
            "status": "default",
            "totalDistanceAlongTrip": 1000.0,
            "vehicleId": "incomplete_vehicle"
        ]
        // Missing activeTripId
        
        expect {
            try Fixtures.dictionaryToModel(type: TripStatus.self, dictionary: incompleteData)
        }.to(throwError())
        
        incompleteData = [
            "activeTripId": "incomplete_trip",
            "closestStop": "incomplete_stop",
            "closestStopTimeOffset": 0,
            "distanceAlongTrip": 100.0,
            "lastLocationUpdateTime": 0,
            "nextStopTimeOffset": 0,
            "orientation": 0.0,
            "phase": "IN_PROGRESS",
            "predicted": false,
            "scheduleDeviation": 0,
            "scheduledDistanceAlongTrip": 100.0,
            "serviceDate": 1000000000,
            "situationIds": [],
            "status": "default",
            "totalDistanceAlongTrip": 1000.0,
            "vehicleId": "incomplete_vehicle"
        ]
        // Missing blockTripSequence
        
        expect {
            try Fixtures.dictionaryToModel(type: TripStatus.self, dictionary: incompleteData)
        }.to(throwError())
    }
}
