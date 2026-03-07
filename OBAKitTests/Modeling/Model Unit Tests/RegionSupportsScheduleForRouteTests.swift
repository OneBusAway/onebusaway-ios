//
//  RegionSupportsScheduleForRouteTests.swift
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

class RegionSupportsScheduleForRouteTests: OBATestCase {

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

    func test_supportsScheduleForRoute_OBA2_0_SNAPSHOT_returnsFalse() throws {
        let region = try regionWithVersionInfo("2.0.0-SNAPSHOT|2|0|0|SNAPSHOT|abc")
        expect(region.supportsScheduleForRoute).to(beFalse())
    }

    // MARK: - OBA 2.1+ should support schedule-for-route

    func test_supportsScheduleForRoute_Tampa_returnsTrue() throws {
        // Real Tampa fixture data
        let region = try regionWithVersionInfo("2.4.15-cs|2|4|15|cs|d41e1a8978da14e98a2e19d109a23018957db7cf")
        expect(region.supportsScheduleForRoute).to(beTrue())
    }

    // MARK: - Empty/unparseable version info should default to true

    func test_supportsScheduleForRoute_emptyString_returnsTrue() throws {
        let region = try regionWithVersionInfo("")
        expect(region.supportsScheduleForRoute).to(beTrue())
    }

    // MARK: - Custom region (hardcoded "x.y.z.custom" in init) should default to true

    func test_supportsScheduleForRoute_customRegion_returnsTrue() {
        let region = Fixtures.customMinneapolisRegion
        expect(region.supportsScheduleForRoute).to(beTrue())
    }

    // MARK: - No-pipe format (e.g. Mayaguez "2.1.0") should default to true

    func test_supportsScheduleForRoute_noPipeFormat_returnsTrue() throws {
        let region = try regionWithVersionInfo("2.1.0")
        expect(region.supportsScheduleForRoute).to(beTrue())
    }
}
