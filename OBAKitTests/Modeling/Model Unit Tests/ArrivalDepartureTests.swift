//
//  ArrivalDepartureTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

class ArrivalDepartureTests: OBATestCase {
    
    func test_decodeValidArrivalDeparture() {
        let arrivalData: [String: Any] = [
            "arrivalEnabled": true,
            "blockTripSequence": 2,
            "departureEnabled": true,
            "distanceFromStop": 1200.5,
            "lastUpdateTime": 1234567890,
            "numberOfStopsAway": 3,
            "predicted": true,
            "predictedArrivalTime": 1234567920,
            "predictedDepartureTime": 1234567950,
            "routeId": "route_44",
            "routeLongName": "Route 44 Custom Name",
            "routeShortName": "44",
            "scheduledArrivalTime": 1234567900,
            "scheduledDepartureTime": 1234567930,
            "serviceDate": 1234512000,
            "situationIds": ["alert1", "alert2"],
            "status": "SCHEDULED",
            "stopId": "stop_12345",
            "stopSequence": 15,
            "totalStopsInTrip": 25,
            "tripHeadsign": "Downtown",
            "tripId": "trip_789",
            "vehicleId": "vehicle_001"
        ]
        
        let arrival = try! Fixtures.dictionaryToModel(type: ArrivalDeparture.self, dictionary: arrivalData)
        
        expect(arrival.arrivalEnabled) == true
        expect(arrival.blockTripSequence) == 2
        expect(arrival.departureEnabled) == true
        expect(arrival.distanceFromStop) == 1200.5
        expect(arrival.lastUpdated.timeIntervalSince1970) == 2212875090
        expect(arrival.numberOfStopsAway) == 3
        expect(arrival.predicted) == true
        expect(arrival.predictedArrival?.timeIntervalSince1970) == 2212875120
        expect(arrival.predictedDeparture?.timeIntervalSince1970) == 2212875150
        expect(arrival.routeID) == "route_44"
        expect(arrival.scheduledArrival.timeIntervalSince1970) == 2212875100
        expect(arrival.scheduledDeparture.timeIntervalSince1970) == 2212875130
        expect(arrival.serviceDate.timeIntervalSince1970) == 2212819200
        expect(arrival.situationIDs) == ["alert1", "alert2"]
        expect(arrival.status) == "SCHEDULED"
        expect(arrival.stopID) == "stop_12345"
        expect(arrival.stopSequence) == 15
        expect(arrival.totalStopsInTrip) == 25
        expect(arrival.tripID) == "trip_789"
        expect(arrival.vehicleID) == "vehicle_001"
        expect(arrival.frequency).to(beNil())
        expect(arrival.tripStatus).to(beNil())
    }
    
    func test_decodeMinimalArrivalDeparture() {
        let minimalData: [String: Any] = [
            "arrivalEnabled": false,
            "blockTripSequence": 1,
            "departureEnabled": false,
            "distanceFromStop": 0.0,
            "lastUpdateTime": 1000000000,
            "numberOfStopsAway": 0,
            "predicted": false,
            "routeId": "route_minimal",
            "scheduledArrivalTime": 1000000060,
            "scheduledDepartureTime": 1000000090,
            "serviceDate": 1000000000,
            "situationIds": [],
            "status": "UNKNOWN",
            "stopId": "stop_minimal",
            "stopSequence": 1,
            "tripId": "trip_minimal",
            "vehicleId": ""
        ]
        
        let arrival = try! Fixtures.dictionaryToModel(type: ArrivalDeparture.self, dictionary: minimalData)
        
        expect(arrival.arrivalEnabled) == false
        expect(arrival.blockTripSequence) == 1
        expect(arrival.departureEnabled) == false
        expect(arrival.distanceFromStop) == 0.0
        expect(arrival.numberOfStopsAway) == 0
        expect(arrival.predicted) == false
        expect(arrival.predictedArrival).to(beNil())
        expect(arrival.predictedDeparture).to(beNil())
        expect(arrival.routeID) == "route_minimal"
        expect(arrival.situationIDs) == []
        expect(arrival.status) == "UNKNOWN"
        expect(arrival.stopID) == "stop_minimal"
        expect(arrival.stopSequence) == 1
        expect(arrival.totalStopsInTrip).to(beNil())
        expect(arrival.tripID) == "trip_minimal"
        expect(arrival.vehicleID).to(beNil())
    }
    
    func test_decodeArrivalDepartureWithBlankValues() {
        let dataWithBlanks: [String: Any] = [
            "arrivalEnabled": true,
            "blockTripSequence": 1,
            "departureEnabled": true,
            "distanceFromStop": 100.0,
            "lastUpdateTime": 1234567890,
            "numberOfStopsAway": 1,
            "predicted": true,
            "routeId": "route_blank",
            "routeLongName": "",
            "routeShortName": "",
            "scheduledArrivalTime": 1234567900,
            "scheduledDepartureTime": 1234567930,
            "serviceDate": 1234512000,
            "situationIds": [],
            "status": "SCHEDULED",
            "stopId": "stop_blank",
            "stopSequence": 1,
            "tripHeadsign": "",
            "tripId": "trip_blank",
            "vehicleId": ""
        ]
        
        let arrival = try! Fixtures.dictionaryToModel(type: ArrivalDeparture.self, dictionary: dataWithBlanks)
        
        // String.nilifyBlankValue should convert empty strings to nil
        expect(arrival.vehicleID).to(beNil())
        // Private properties are not directly testable, but their effects should be seen in computed properties
    }
    
    func test_decodeArrivalDepartureWithInvalidPredictedTimes() {
        // Test with very early predicted times that should be nullified
        let dataWithInvalidTimes: [String: Any] = [
            "arrivalEnabled": true,
            "blockTripSequence": 1,
            "departureEnabled": true,
            "distanceFromStop": 100.0,
            "lastUpdateTime": 1234567890,
            "numberOfStopsAway": 1,
            "predicted": true,
            "predictedArrivalTime": 0, // Very early time, should be nullified
            "predictedDepartureTime": 0, // Very early time, should be nullified
            "routeId": "route_invalid",
            "scheduledArrivalTime": 1234567900,
            "scheduledDepartureTime": 1234567930,
            "serviceDate": 1234512000,
            "situationIds": [],
            "status": "SCHEDULED",
            "stopId": "stop_invalid",
            "stopSequence": 1,
            "tripId": "trip_invalid",
            "vehicleId": "vehicle_invalid"
        ]
        
        let arrival = try! Fixtures.dictionaryToModel(type: ArrivalDeparture.self, dictionary: dataWithInvalidTimes)
        
        // ModelHelpers.nilifyDate should have converted very early dates to nil
        expect(arrival.predictedArrival).to(beNil())
        expect(arrival.predictedDeparture).to(beNil())
    }
    
    func test_hasReferencesLoadReferences() {
        let arrivalData: [String: Any] = [
            "arrivalEnabled": true,
            "blockTripSequence": 1,
            "departureEnabled": true,
            "distanceFromStop": 100.0,
            "lastUpdateTime": 1234567890,
            "numberOfStopsAway": 1,
            "predicted": true,
            "routeId": "route_ref",
            "scheduledArrivalTime": 1234567900,
            "scheduledDepartureTime": 1234567930,
            "serviceDate": 1234512000,
            "situationIds": ["alert_ref_1", "alert_ref_2"],
            "status": "SCHEDULED",
            "stopId": "stop_ref",
            "stopSequence": 1,
            "tripId": "trip_ref",
            "vehicleId": "vehicle_ref"
        ]
        
        let arrival = try! Fixtures.dictionaryToModel(type: ArrivalDeparture.self, dictionary: arrivalData)
        
        let referencesData: [String: Any] = [
            "agencies": [[
                "id": "agency_ref",
                "name": "Test Agency",
                "url": "https://example.com",
                "timezone": "UTC",
                "lang": "en",
                "phone": "555-0123",
                "privateService": false
            ]],
            "routes": [[
                "id": "route_ref",
                "agencyId": "agency_ref",
                "shortName": "Test Route",
                "type": 3
            ]],
            "stops": [[
                "id": "stop_ref",
                "lat": 47.6097,
                "lon": -122.3331,
                "name": "Test Stop",
                "code": "12345",
                "direction": "N",
                "locationType": 0,
                "routeIds": ["route_ref"],
                "staticRouteIds": ["route_ref"],
                "wheelchairBoarding": "UNKNOWN"
            ]],
            "trips": [[
                "id": "trip_ref",
                "blockId": "block_ref",
                "routeId": "route_ref",
                "serviceId": "service_ref",
                "shapeId": "shape_ref",
                "routeShortName": "Test",
                "tripShortName": "Trip",
                "timeZone": "UTC"
            ]],
            "situations": [[
                "id": "alert_ref_1",
                "creationTime": 1234567890,
                "reason": "CONSTRUCTION",
                "severity": "MODERATE",
                "activeWindows": [],
                "publicationWindows": [],
                "allAffects": [],
                "consequences": []
            ], [
                "id": "alert_ref_2",
                "creationTime": 1234567890,
                "reason": "MAINTENANCE",
                "severity": "INFO",
                "activeWindows": [],
                "publicationWindows": [],
                "allAffects": [],
                "consequences": []
            ]]
        ]
        
        let references = try! Fixtures.dictionaryToModel(type: References.self, dictionary: referencesData)
        
        arrival.loadReferences(references, regionIdentifier: 777)
        
        expect(arrival.regionIdentifier) == 777
        expect(arrival.route).toNot(beNil())
        expect(arrival.route.id) == "route_ref"
        expect(arrival.stop).toNot(beNil())
        expect(arrival.stop.id) == "stop_ref"
        expect(arrival.trip).toNot(beNil())
        expect(arrival.trip.id) == "trip_ref"
        expect(arrival.serviceAlerts.count) == 2
        expect(arrival.serviceAlerts.map { $0.id }.sorted()) == ["alert_ref_1", "alert_ref_2"]
    }
    
    func test_occupancyStatusDecoding() {
        let occupancyData: [String: Any] = [
            "arrivalEnabled": true,
            "blockTripSequence": 1,
            "departureEnabled": true,
            "distanceFromStop": 100.0,
            "lastUpdateTime": 1234567890,
            "numberOfStopsAway": 1,
            "predicted": true,
            "routeId": "route_occupancy",
            "scheduledArrivalTime": 1234567900,
            "scheduledDepartureTime": 1234567930,
            "serviceDate": 1234512000,
            "situationIds": [],
            "status": "SCHEDULED",
            "stopId": "stop_occupancy",
            "stopSequence": 1,
            "tripId": "trip_occupancy",
            "vehicleId": "vehicle_occupancy",
            "occupancyStatus": "FULL",
            "historicalOccupancy": "MANY_SEATS_AVAILABLE"
        ]
        
        let arrival = try! Fixtures.dictionaryToModel(type: ArrivalDeparture.self, dictionary: occupancyData)
        
        expect(arrival.occupancyStatus?.rawValue) == "FULL"
        expect(arrival.historicalOccupancyStatus?.rawValue) == "MANY_SEATS_AVAILABLE"
    }
    
    func test_arrivalDepartureEquality() {
        let arrivalData: [String: Any] = [
            "arrivalEnabled": true,
            "blockTripSequence": 1,
            "departureEnabled": true,
            "distanceFromStop": 100.0,
            "lastUpdateTime": 1234567890,
            "numberOfStopsAway": 1,
            "predicted": true,
            "routeId": "route_equality",
            "scheduledArrivalTime": 1234567900,
            "scheduledDepartureTime": 1234567930,
            "serviceDate": 1234512000,
            "situationIds": [],
            "status": "SCHEDULED",
            "stopId": "stop_equality",
            "stopSequence": 1,
            "tripId": "trip_equality",
            "vehicleId": "vehicle_equality"
        ]
        
        let arrival1 = try! Fixtures.dictionaryToModel(type: ArrivalDeparture.self, dictionary: arrivalData)
        let arrival2 = try! Fixtures.dictionaryToModel(type: ArrivalDeparture.self, dictionary: arrivalData)
        
        var differentData = arrivalData
        differentData["tripId"] = "different_trip"
        let arrival3 = try! Fixtures.dictionaryToModel(type: ArrivalDeparture.self, dictionary: differentData)
        
        expect(arrival1.isEqual(arrival2)) == true
        expect(arrival1.isEqual(arrival3)) == false
        expect(arrival1.hash) == arrival2.hash
        expect(arrival1.hash) != arrival3.hash
    }
    
    func test_decodeFailureWhenMissingRequiredFields() {
        var incompleteData: [String: Any] = [
            "blockTripSequence": 1,
            "departureEnabled": true,
            "distanceFromStop": 100.0,
            "lastUpdateTime": 1234567890,
            "numberOfStopsAway": 1,
            "predicted": true,
            "routeId": "route_incomplete",
            "scheduledArrivalTime": 1234567900,
            "scheduledDepartureTime": 1234567930,
            "serviceDate": 1234512000,
            "situationIds": [],
            "status": "SCHEDULED",
            "stopId": "stop_incomplete",
            "stopSequence": 1,
            "tripId": "trip_incomplete",
            "vehicleId": "vehicle_incomplete"
        ]
        // Missing arrivalEnabled
        
        expect {
            try Fixtures.dictionaryToModel(type: ArrivalDeparture.self, dictionary: incompleteData)
        }.to(throwError())
        
        incompleteData = [
            "arrivalEnabled": true,
            "blockTripSequence": 1,
            "departureEnabled": true,
            "distanceFromStop": 100.0,
            "lastUpdateTime": 1234567890,
            "numberOfStopsAway": 1,
            "predicted": true,
            "scheduledArrivalTime": 1234567900,
            "scheduledDepartureTime": 1234567930,
            "serviceDate": 1234512000,
            "situationIds": [],
            "status": "SCHEDULED",
            "stopId": "stop_incomplete",
            "stopSequence": 1,
            "tripId": "trip_incomplete",
            "vehicleId": "vehicle_incomplete"
        ]
        // Missing routeId
        
        expect {
            try Fixtures.dictionaryToModel(type: ArrivalDeparture.self, dictionary: incompleteData)
        }.to(throwError())
    }
}
