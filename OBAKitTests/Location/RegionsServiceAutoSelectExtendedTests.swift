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
        isActive: Bool = true
    ) throws -> Region {
        let dict: [String: Any] = [
            "id": id,
            "name": name,
            "obaBaseUrl": "https://api.example.com/\(id)",
            "active": isActive,
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
        let seattleCenter = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
        let seattleRegion = try makeRegion(id: 1, name: "Puget Sound", latitude: 47.6062, longitude: -122.3321)

        let userAtCenter = CLLocation(latitude: 47.6062, longitude: -122.3321)
        let distCenter = seattleRegion.distance(from: userAtCenter)

        #expect(distCenter < 1.0) // Right at centroid

        let user50kmNorth = CLLocation(latitude: 48.0562, longitude: -122.3321)
        let distNorth = seattleRegion.distance(from: user50kmNorth)
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

        #expect(region.contains(insideLoc) == true)
        #expect(region.contains(outsideLoc) == false)
    }

    // MARK: - Inactive Region Skipping

    @Test func `inactive regions are distinguishable by active flag`() throws {
        let activeRegion = try makeRegion(id: 1, name: "Active Transit", latitude: 47.6, longitude: -122.3, isActive: true)
        let inactiveRegion = try makeRegion(id: 2, name: "Retired Transit", latitude: 47.6, longitude: -122.3, isActive: false)

        #expect(activeRegion.active == true)
        #expect(inactiveRegion.active == false)
    }

    // MARK: - Equatable & Identifiable

    @Test func `Region equality matches on identifier`() throws {
        let reg1a = try makeRegion(id: 42, name: "Region Alpha", latitude: 40.0, longitude: -70.0)
        let reg1b = try makeRegion(id: 42, name: "Region Alpha Updated", latitude: 40.1, longitude: -70.1)
        let reg2 = try makeRegion(id: 99, name: "Region Beta", latitude: 40.0, longitude: -70.0)

        #expect(reg1a == reg1b)
        #expect(reg1a != reg2)
        #expect(reg1a.id == 42)
    }
}
