//
//  AgenciesWithCoverageModelOperationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
import CoreLocation
import MapKit
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

class AgenciesWithCoverageModelOperationTests: OBATestCase {
    func testLoading_success() async throws {
        let dataLoader = (restService.dataLoader as! MockDataLoader)
        let data = Fixtures.loadData(file: "agencies_with_coverage.json")
        dataLoader.mock(URLString: "https://www.example.com/api/where/agencies-with-coverage.json", with: data)

        let response = try await restService.getAgenciesWithCoverage()

        let agencies = response.list
        let childrens = try XCTUnwrap(agencies.first)

        expect(agencies.count) == 11

        expect(childrens.region.center.latitude).to(beCloseTo(47.6470785))
        expect(childrens.region.center.longitude).to(beCloseTo(-122.296449))

        expect(childrens.region.span.latitudeDelta).to(beCloseTo(0.06330499999999972, within: 0.1))
        expect(childrens.region.span.longitudeDelta).to(beCloseTo(0.07930600000000254, within: 0.1))

        expect(childrens.agencyID) == "98"
        expect(childrens.agency.name) == "Seattle Children's Hospital"
        expect(childrens.agency.disclaimer).to(beNil())
        expect(childrens.agency.email).to(beNil())
        expect(childrens.agency.fareURL).to(beNil())
    }
}
