//
//  RegionsServiceAutoSelectExtendedTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Extended test suite for `RegionsService` automatic region selection,
/// distance calculation fallbacks, and custom region boundaries.
@Suite(.serialized)
final class RegionsServiceAutoSelectExtendedTests: OBATestCase {

    private func makeRegion(
        id: Int,
        name: String,
        latitude: Double,
        longitude: Double,
        latSpan: Double = 0.5,
        lonSpan: Double = 0.5,
        baseURL: String? = nil,
        isActive: Bool = true
    ) throws -> Region {
        let dict: [String: Any] = [
            "id": id,
            "regionName": name,
            "active": isActive,
            "experimental": false,
            "obaBaseUrl": baseURL ?? "https://api.example.com/\(id)",
            "contactEmail": "contact@example.com",
            "supportsEmbeddedSocial": false,
            "supportsObaRealtimeApis": true,
            "supportsObaDiscoveryApis": true,
            "supportsSiriRealtimeApis": false,
            "language": "en_US",
            "obaVersionInfo": "2.0.0",
            "bounds": [
                [
                    "lat": latitude,
                    "lon": longitude,
                    "latSpan": latSpan,
                    "lonSpan": lonSpan
                ]
            ]
        ]
        return try Fixtures.dictionaryToModel(type: Region.self, dictionary: dict)
    }

    // MARK: - Region Proximity Ordering

    @Test func `distanceFromLocation calculates geometric distance to region centroid`() throws {
        let seattleRegion = try makeRegion(id: 1, name: "Puget Sound", latitude: 47.6062, longitude: -122.3321)

        let userAtCenter = CLLocation(latitude: 47.6062, longitude: -122.3321)
        let distCenter = seattleRegion.distanceFrom(location: userAtCenter)

        // Region.centerCoordinate is the Mercator midpoint of serviceRect, which sits
        // ~66 meters north of the geographic center at Puget Sound latitude.
        #expect(distCenter < 100.0)

        let user50kmNorth = CLLocation(latitude: 48.0562, longitude: -122.3321)
        let distNorth = seattleRegion.distanceFrom(location: user50kmNorth)
        #expect(distNorth > 40000.0 && distNorth < 60000.0)
    }

    @Test func `containsLocation correctly evaluates bounding box containment`() throws {
        let region = try makeRegion(
            id: 1,
            name: "Puget Sound",
            latitude: 47.6,
            longitude: -122.3,
            latSpan: 1.0, // 47.1 to 48.1
            lonSpan: 1.0  // -122.8 to -121.8
        )

        let insideLoc = CLLocation(latitude: 47.6062, longitude: -122.3321)
        let outsideLoc = CLLocation(latitude: 49.0000, longitude: -122.3321)

        #expect(region.contains(location: insideLoc) == true)
        #expect(region.contains(location: outsideLoc) == false)
    }

    // MARK: - Inactive Region Skipping

    @Test func `inactive regions are distinguishable by active flag`() throws {
        let activeRegion = try makeRegion(id: 1, name: "Active Transit", latitude: 47.6, longitude: -122.3, isActive: true)
        let inactiveRegion = try makeRegion(id: 2, name: "Inactive Transit", latitude: 47.6, longitude: -122.3, isActive: false)

        #expect(activeRegion.isActive == true)
        #expect(inactiveRegion.isActive == false)
    }

    // MARK: - Equatable & Identifiable

    @Test func `Region equality matches on identifier`() throws {
        let sharedURL = "https://api.example.com/shared"
        let reg1a = try makeRegion(id: 42, name: "Region Alpha", latitude: 40.0, longitude: -70.0, baseURL: sharedURL)
        let reg1Identical = try makeRegion(id: 42, name: "Region Alpha", latitude: 40.0, longitude: -70.0, baseURL: sharedURL)

        // reg2 shares the exact same name, coordinates, and URL as reg1a, differing solely in id
        let reg2 = try makeRegion(id: 99, name: "Region Alpha", latitude: 40.0, longitude: -70.0, baseURL: sharedURL)

        #expect(reg1a == reg1Identical)
        #expect(reg1a != reg2)
        #expect(reg1a.id == 42)
        #expect(reg2.id == 99)
    }
}
