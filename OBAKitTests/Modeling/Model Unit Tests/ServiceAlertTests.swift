//
//  ServiceAlertTests.swift
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

class ServiceAlertTests: OBATestCase {
    
    func test_decodeValidServiceAlert() {
        let alertData: [String: Any] = [
            "id": "test_alert_123",
            "creationTime": 1234567890,
            "reason": "CONSTRUCTION",
            "severity": "SEVERE",
            "summary": [
                "lang": "en",
                "value": "Route 44 detour"
            ],
            "description": [
                "lang": "en", 
                "value": "Route 44 is detoured due to construction on Pine Street"
            ],
            "url": [
                "lang": "en",
                "value": "https://example.com/alerts/123"
            ],
            "activeWindows": [
                [
                    "from": 1234567890,
                    "to": 1234567999
                ]
            ],
            "publicationWindows": [
                [
                    "from": 1234567880,
                    "to": 1234568000
                ]
            ],
            "allAffects": [
                [
                    "agencyId": "agency_1",
                    "applicationId": "test_app",
                    "directionId": "1",
                    "routeId": "route_44",
                    "stopId": "stop_123",
                    "tripId": ""
                ]
            ],
            "consequences": [
                [
                    "condition": "DETOUR"
                ]
            ]
        ]
        
        let alert = try! Fixtures.dictionaryToModel(type: ServiceAlert.self, dictionary: alertData)
        
        expect(alert.id) == "test_alert_123"
        expect(alert.createdAt.timeIntervalSince1970) == 2212875090
        expect(alert.reason) == "CONSTRUCTION"
        expect(alert.severity) == "SEVERE"
        expect(alert.summary?.value) == "Route 44 detour"
        expect(alert.situationDescription?.value) == "Route 44 is detoured due to construction on Pine Street"
        expect(alert.urlString?.value) == "https://example.com/alerts/123"
        expect(alert.activeWindows.count) == 1
        expect(alert.publicationWindows.count) == 1
        expect(alert.affectedEntities.count) == 1
        expect(alert.consequences.count) == 1
        expect(alert.regionIdentifier).to(beNil())
    }
    
    func test_decodeMinimalServiceAlert() {
        let minimalData: [String: Any] = [
            "id": "minimal_alert",
            "creationTime": 1000000000,
            "reason": "OTHER",
            "severity": "INFO",
            "activeWindows": [],
            "publicationWindows": [],
            "allAffects": [],
            "consequences": []
        ]
        
        let alert = try! Fixtures.dictionaryToModel(type: ServiceAlert.self, dictionary: minimalData)
        
        expect(alert.id) == "minimal_alert"
        expect(alert.createdAt.timeIntervalSince1970) == 1978307200
        expect(alert.reason) == "OTHER"
        expect(alert.severity) == "INFO"
        expect(alert.summary).to(beNil())
        expect(alert.situationDescription).to(beNil())
        expect(alert.urlString).to(beNil())
        expect(alert.activeWindows.count) == 0
        expect(alert.publicationWindows.count) == 0
        expect(alert.affectedEntities.count) == 0
        expect(alert.consequences.count) == 0
    }
    
    func test_timeWindowDecoding() {
        let timeWindowData: [String: Any] = [
            "from": 1234567890,
            "to": 1234567999
        ]
        
        let timeWindow = try! Fixtures.dictionaryToModel(type: ServiceAlert.TimeWindow.self, dictionary: timeWindowData)
        
        expect(timeWindow.from.timeIntervalSince1970) == 1234567890
        expect(timeWindow.to.timeIntervalSince1970) == 1234567999
        expect(timeWindow.interval.start) == timeWindow.from
        expect(timeWindow.interval.end) == timeWindow.to
    }

    func test_timeWindowDecodingWithMilliseconds() {
        let millisecondsData: [String: Any] = [
            "from": 1539781200000,
            "to": 1539826200000
        ]
        
        let timeWindow = try! Fixtures.dictionaryToModel(type: ServiceAlert.TimeWindow.self, dictionary: millisecondsData)
        
        expect(timeWindow.from.timeIntervalSince1970) == 1539781200
        expect(timeWindow.to.timeIntervalSince1970) == 1539826200
    }

    func test_timeWindowThresholdBoundary() {
        // Just at threshold (10_000_000_000) -> Treated as seconds
        let atThresholdData: [String: Any] = ["from": 10_000_000_000, "to": 10_000_003_600]
        let atThresholdWindow = try! Fixtures.dictionaryToModel(type: ServiceAlert.TimeWindow.self, dictionary: atThresholdData)
        
        expect(atThresholdWindow.from.timeIntervalSince1970) == 10_000_000_000
        
        // Just above threshold (10_000_000_001) -> Treated as milliseconds
        let aboveThresholdData: [String: Any] = ["from": 10_000_000_001, "to": 10_000_000_002]
        let aboveThresholdWindow = try! Fixtures.dictionaryToModel(type: ServiceAlert.TimeWindow.self, dictionary: aboveThresholdData)
        
        // Use beCloseTo to fix floating point error
        expect(aboveThresholdWindow.from.timeIntervalSince1970).to(beCloseTo(10_000_000.001, within: 0.0001))
    }
    
    func test_timeWindowWithMissingTo() {
        let timeWindowData: [String: Any] = [
            "from": 1234567890
        ]
        
        let timeWindow = try! Fixtures.dictionaryToModel(type: ServiceAlert.TimeWindow.self, dictionary: timeWindowData)
        
        expect(timeWindow.from.timeIntervalSince1970) == 1234567890
        expect(timeWindow.to) == Date.distantFuture
        expect(timeWindow.interval.start) == timeWindow.from
    }
    
    func test_timeWindowWithInvalidTo() {
        let timeWindowData: [String: Any] = [
            "from": 1234567890,
            "to": 100  // Earlier than 'from', simulating 1970 timestamp
        ]
        
        let timeWindow = try! Fixtures.dictionaryToModel(type: ServiceAlert.TimeWindow.self, dictionary: timeWindowData)
        
        expect(timeWindow.from.timeIntervalSince1970) == 1234567890
        expect(timeWindow.to.timeIntervalSince1970) == 100
        // When 'to' is before 'from', interval should be from start to start
        expect(timeWindow.interval.start) == timeWindow.from
        expect(timeWindow.interval.end) == timeWindow.from
    }
    
    func test_timeWindowComparison() {
        let earlyData: [String: Any] = ["from": 1000, "to": 2000]
        let lateData: [String: Any] = ["from": 3000, "to": 4000]
        
        let earlyWindow = try! Fixtures.dictionaryToModel(type: ServiceAlert.TimeWindow.self, dictionary: earlyData)
        let lateWindow = try! Fixtures.dictionaryToModel(type: ServiceAlert.TimeWindow.self, dictionary: lateData)
        
        expect(earlyWindow < lateWindow) == true
        expect(lateWindow < earlyWindow) == false
    }
    
    func test_timeWindowEquality() {
        let data1: [String: Any] = ["from": 1000, "to": 2000]
        let data2: [String: Any] = ["from": 1000, "to": 2000]
        let data3: [String: Any] = ["from": 1000, "to": 3000]
        
        let window1 = try! Fixtures.dictionaryToModel(type: ServiceAlert.TimeWindow.self, dictionary: data1)
        let window2 = try! Fixtures.dictionaryToModel(type: ServiceAlert.TimeWindow.self, dictionary: data2)
        let window3 = try! Fixtures.dictionaryToModel(type: ServiceAlert.TimeWindow.self, dictionary: data3)
        
        expect(window1.isEqual(window2)) == true
        expect(window1.isEqual(window3)) == false
        expect(window1.hash) == window2.hash
        expect(window1.hash) != window3.hash
    }
    
    func test_affectedEntityDecoding() {
        let entityData: [String: Any] = [
            "agencyId": "test_agency",
            "applicationId": "test_app",
            "directionId": "0",
            "routeId": "test_route",
            "stopId": "test_stop",
            "tripId": "test_trip"
        ]
        
        let entity = try! Fixtures.dictionaryToModel(type: ServiceAlert.AffectedEntity.self, dictionary: entityData)
        
        expect(entity.agencyID) == "test_agency"
        expect(entity.applicationID) == "test_app"
        expect(entity.directionID) == "0"
        expect(entity.routeID) == "test_route"
        expect(entity.stopID) == "test_stop"
        expect(entity.tripID) == "test_trip"
    }
    
    func test_affectedEntityWithBlankValues() {
        let entityData: [String: Any] = [
            "agencyId": "",
            "applicationId": "",
            "directionId": "",
            "routeId": "test_route",
            "stopId": "",
            "tripId": ""
        ]
        
        let entity = try! Fixtures.dictionaryToModel(type: ServiceAlert.AffectedEntity.self, dictionary: entityData)
        
        expect(entity.agencyID).to(beNil())
        expect(entity.applicationID).to(beNil())
        expect(entity.directionID).to(beNil())
        expect(entity.routeID) == "test_route"
        expect(entity.stopID).to(beNil())
        expect(entity.tripID).to(beNil())
    }
    
    func test_affectedEntityEquality() {
        let data1: [String: Any] = ["agencyId": "a1", "routeId": "r1", "applicationId": "", "directionId": "", "stopId": "", "tripId": ""]
        let data2: [String: Any] = ["agencyId": "a1", "routeId": "r1", "applicationId": "", "directionId": "", "stopId": "", "tripId": ""]
        let data3: [String: Any] = ["agencyId": "a1", "routeId": "r2", "applicationId": "", "directionId": "", "stopId": "", "tripId": ""]

        let entity1 = try! Fixtures.dictionaryToModel(type: ServiceAlert.AffectedEntity.self, dictionary: data1)
        let entity2 = try! Fixtures.dictionaryToModel(type: ServiceAlert.AffectedEntity.self, dictionary: data2)
        let entity3 = try! Fixtures.dictionaryToModel(type: ServiceAlert.AffectedEntity.self, dictionary: data3)
        
        expect(entity1.isEqual(entity2)) == true
        expect(entity1.isEqual(entity3)) == false
        expect(entity1.hash) == entity2.hash
        expect(entity1.hash) != entity3.hash
    }
    
    func test_consequenceDecoding() {
        let consequenceData: [String: Any] = [
            "condition": "DETOUR",
            "conditionDetails": [
                "diversionPath": [
                    "points": "test_polyline_string"
                ],
                "diversionStopIds": ["stop1", "stop2", "stop3"]
            ]
        ]
        
        let consequence = try! Fixtures.dictionaryToModel(type: ServiceAlert.Consequence.self, dictionary: consequenceData)
        
        expect(consequence.condition) == "DETOUR"
        expect(consequence.conditionDetails).toNot(beNil())
        expect(consequence.conditionDetails?.diversionPath) == "test_polyline_string"
        expect(consequence.conditionDetails?.stopIDs) == ["stop1", "stop2", "stop3"]
    }
    
    func test_consequenceWithoutDetails() {
        let consequenceData: [String: Any] = [
            "condition": "NO_SERVICE"
        ]
        
        let consequence = try! Fixtures.dictionaryToModel(type: ServiceAlert.Consequence.self, dictionary: consequenceData)
        
        expect(consequence.condition) == "NO_SERVICE"
        expect(consequence.conditionDetails).to(beNil())
    }
    
    func test_consequenceEquality() {
        let data1: [String: Any] = ["condition": "DETOUR"]
        let data2: [String: Any] = ["condition": "DETOUR"]
        let data3: [String: Any] = ["condition": "NO_SERVICE"]
        
        let consequence1 = try! Fixtures.dictionaryToModel(type: ServiceAlert.Consequence.self, dictionary: data1)
        let consequence2 = try! Fixtures.dictionaryToModel(type: ServiceAlert.Consequence.self, dictionary: data2)
        let consequence3 = try! Fixtures.dictionaryToModel(type: ServiceAlert.Consequence.self, dictionary: data3)
        
        expect(consequence1.isEqual(consequence2)) == true
        expect(consequence1.isEqual(consequence3)) == false
        expect(consequence1.hash) == consequence2.hash
        expect(consequence1.hash) != consequence3.hash
    }
    
    func test_conditionDetailsEquality() {
        let data1: [String: Any] = [
            "diversionPath": ["points": "path1"],
            "diversionStopIds": ["stop1"]
        ]
        let data2: [String: Any] = [
            "diversionPath": ["points": "path1"],
            "diversionStopIds": ["stop1"]
        ]
        let data3: [String: Any] = [
            "diversionPath": ["points": "path2"],
            "diversionStopIds": ["stop1"]
        ]
        
        let details1 = try! Fixtures.dictionaryToModel(type: ServiceAlert.ConditionDetails.self, dictionary: data1)
        let details2 = try! Fixtures.dictionaryToModel(type: ServiceAlert.ConditionDetails.self, dictionary: data2)
        let details3 = try! Fixtures.dictionaryToModel(type: ServiceAlert.ConditionDetails.self, dictionary: data3)
        
        expect(details1.isEqual(details2)) == true
        expect(details1.isEqual(details3)) == false
        expect(details1.hash) == details2.hash
        expect(details1.hash) != details3.hash
    }
    
    func test_translatedStringEquality() {
        let str1 = ServiceAlert.TranslatedString(lang: "en", value: "Hello")
        let str2 = ServiceAlert.TranslatedString(lang: "en", value: "Hello")
        let str3 = ServiceAlert.TranslatedString(lang: "es", value: "Hola")
        
        expect(str1.isEqual(str2)) == true
        expect(str1.isEqual(str3)) == false
        expect(str1.hash) == str2.hash
        expect(str1.hash) != str3.hash
    }
    
    func test_serviceAlertEquality() {
        let alertData: [String: Any] = [
            "id": "alert_equality_test",
            "creationTime": 1234567890,
            "reason": "CONSTRUCTION",
            "severity": "MODERATE",
            "activeWindows": [],
            "publicationWindows": [],
            "allAffects": [],
            "consequences": []
        ]
        
        let alert1 = try! Fixtures.dictionaryToModel(type: ServiceAlert.self, dictionary: alertData)
        let alert2 = try! Fixtures.dictionaryToModel(type: ServiceAlert.self, dictionary: alertData)
        
        var differentData = alertData
        differentData["id"] = "different_alert"
        let alert3 = try! Fixtures.dictionaryToModel(type: ServiceAlert.self, dictionary: differentData)
        
        expect(alert1.isEqual(alert2)) == true
        expect(alert1.isEqual(alert3)) == false
        expect(alert1.hash) == alert2.hash
        expect(alert1.hash) != alert3.hash
    }
    
    func test_hasReferencesLoadReferences() {
        let alertData: [String: Any] = [
            "id": "test_alert_references",
            "creationTime": 1234567890,
            "reason": "CONSTRUCTION",
            "severity": "MODERATE",
            "activeWindows": [],
            "publicationWindows": [],
            "allAffects": [
                [
                    "agencyId": "agency_1",
                    "applicationId": "test_app",
                    "directionId": "1",
                    "routeId": "route_1",
                    "stopId": "stop_1",
                    "tripId": "trip_1"
                ]
            ],
            "consequences": []
        ]
        
        let alert = try! Fixtures.dictionaryToModel(type: ServiceAlert.self, dictionary: alertData)
        
        let referencesData: [String: Any] = [
            "agencies": [[
                "id": "agency_1",
                "name": "Test Agency",
                "url": "https://example.com",
                "timezone": "UTC",
                "lang": "en",
                "phone": "555-0123",
                "privateService": false
            ]],
            "routes": [[
                "id": "route_1",
                "agencyId": "agency_1",
                "shortName": "Test Route",
                "type": 3
            ]],
            "stops": [[
                "id": "stop_1",
                "lat": 47.6097,
                "lon": -122.3331,
                "name": "Test Stop",
                "code": "12345",
                "direction": "N",
                "locationType": 0,
                "routeIds": ["route_1"],
                "staticRouteIds": ["route_1"],
                "wheelchairBoarding": "UNKNOWN"
            ]],
            "trips": [[
                "id": "trip_1",
                "blockId": "block_1",
                "routeId": "route_1",
                "serviceId": "service_1",
                "shapeId": "shape_1",
                "routeShortName": "Test",
                "tripShortName": "Trip",
                "timeZone": "UTC"
            ]]
        ]
        
        let references = try! Fixtures.dictionaryToModel(type: References.self, dictionary: referencesData)
        
        alert.loadReferences(references, regionIdentifier: 999)
        
        expect(alert.regionIdentifier) == 999
        expect(alert.affectedAgencies.count) == 1
        expect(alert.affectedRoutes.count) == 1
        expect(alert.affectedStops.count) == 1
        expect(alert.affectedTrips.count) == 1
        
        expect(alert.affectedAgencies.first?.id) == "agency_1"
        expect(alert.affectedRoutes.first?.id) == "route_1"
        expect(alert.affectedStops.first?.id) == "stop_1"
        expect(alert.affectedTrips.first?.id) == "trip_1"
    }
}
