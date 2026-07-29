//
//  RegionSupportsScheduleForRouteTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class RegionSupportsScheduleForRouteTests: OBATestCase {

    /// Helper to create a Region with a specific `obaVersionInfo` value.
    private func regionWithVersionInfo(_ versionInfo: String) throws -> Region {
        let dict: [String: Any] = [
            "regionName": "Test Region",
            "id": 9999,
            "obaBaseUrl": "https://example.com/api/",
            "siriBaseUrl": "",
            "bounds": [
                ["lat": 47.0, "lon": -122.0, "latSpan": 0.5, "lonSpan": 0.5]
            ],
            "language": "en_US",
            "contactEmail": "test@example.com",
            "supportsObaDiscoveryApis": true,
            "supportsObaRealtimeApis": true,
            "supportsSiriRealtimeApis": false,
            "supportsEmbeddedSocial": false,
            "supportsOtpBikeshare": false,
            "active": true,
            "experimental": false,
            "obaVersionInfo": versionInfo
        ]
        return try Fixtures.dictionaryToModel(type: Region.self, dictionary: dict)
    }

    // MARK: - OBA 2.0.x should not support schedule-for-route

    @Test func `Supports schedule for route OBA 2 0 SNAPSHOT returns false`() throws {
        let region = try regionWithVersionInfo("2.0.0-SNAPSHOT|2|0|0|SNAPSHOT|abc")
        #expect(!region.supportsScheduleForRoute)
    }

    // MARK: - OBA 2.1+ should support schedule-for-route

    @Test func `Supports schedule for route tampa returns true`() throws {
        // Real Tampa fixture data
        let region = try regionWithVersionInfo("2.4.15-cs|2|4|15|cs|d41e1a8978da14e98a2e19d109a23018957db7cf")
        #expect(region.supportsScheduleForRoute)
    }

    // MARK: - Empty/unparseable version info should default to true

    @Test func `Supports schedule for route empty string returns true`() throws {
        let region = try regionWithVersionInfo("")
        #expect(region.supportsScheduleForRoute)
    }

    // MARK: - Custom region (hardcoded "x.y.z.custom" in init) should default to true

    @Test func `Supports schedule for route custom region returns true`() {
        let region = Fixtures.customMinneapolisRegion
        #expect(region.supportsScheduleForRoute)
    }

    // MARK: - No-pipe format (e.g. Mayaguez "2.1.0") should default to true

    @Test func `Supports schedule for route no pipe format returns true`() throws {
        let region = try regionWithVersionInfo("2.1.0")
        #expect(region.supportsScheduleForRoute)
    }
}
