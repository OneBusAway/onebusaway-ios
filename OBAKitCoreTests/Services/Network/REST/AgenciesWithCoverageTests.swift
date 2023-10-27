//
//  AgenciesWithCoverageTests.swift
//  OBAKitCoreTests
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import OBAKitCore

final class AgenciesWithCoverageTests: OBAKitCoreTestCase {
    func testLoading() async throws {
        let data = try Fixtures.loadData(file: "agencies_with_coverage.json")
        dataLoader.mock(URLString: "https://www.example.com/api/where/agencies-with-coverage.json", with: data)

        let response = try await restAPIService.getAgenciesWithCoverage().list
        XCTAssertEqual(response.count, 11)

        let agency = try XCTUnwrap(response.first)

        XCTAssertEqual(agency.region.center.latitude, 47.6470785, accuracy: 0.00001)
        XCTAssertEqual(agency.region.center.longitude, -122.296449, accuracy: 0.00001)

        XCTAssertEqual(agency.region.span.latitudeDelta, 0.06330499999999972, accuracy: 0.00001)
        XCTAssertEqual(agency.region.span.longitudeDelta, 0.07930600000000254, accuracy: 0.00001)

        XCTAssertEqual(agency.id, "98")
    }
}
