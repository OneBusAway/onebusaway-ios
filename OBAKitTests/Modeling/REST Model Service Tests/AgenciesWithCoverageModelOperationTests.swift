//
//  AgenciesWithCoverageModelOperationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

@Suite(.serialized)
final class AgenciesWithCoverageModelOperationTests: OBATestCase {
    @Test func `Loading success`() async throws {
        let dataLoader = (restService.dataLoader as! MockDataLoader)
        let data = Fixtures.loadData(file: "agencies_with_coverage.json")
        dataLoader.mock(URLString: "https://www.example.com/api/where/agencies-with-coverage.json", with: data)

        let response = try await restService.getAgenciesWithCoverage()

        let agencies = response.list
        let childrens = try #require(agencies.first)

        #expect(agencies.count == 11)

        expectClose(childrens.region.center.latitude, 47.6470785)
        expectClose(childrens.region.center.longitude, -122.296449)

        expectClose(childrens.region.span.latitudeDelta, 0.06330499999999972, within: 1e-6)
        expectClose(childrens.region.span.longitudeDelta, 0.07930600000000254, within: 1e-6)

        #expect(childrens.agencyID == "98")
        #expect(childrens.agency.name == "Seattle Children's Hospital")
        #expect(childrens.agency.disclaimer == nil)
        #expect(childrens.agency.email == nil)
        #expect(childrens.agency.fareURL == nil)
    }

    @Test func `Region span preserves API degrees rather than converting from meters`() throws {
        let model = try Fixtures.dictionaryToModel(
            type: AgencyWithCoverage.self,
            dictionary: [
                "agencyId": "1",
                "lat": 47.560728,
                "latSpan": 0.743228000000002,
                "lon": -122.09015249999999,
                "lonSpan": 0.8329389999999961
            ]
        )

        expectClose(model.region.center.latitude, 47.560728, within: 1e-9)
        expectClose(model.region.center.longitude, -122.09015249999999, within: 1e-9)
        expectClose(model.region.span.latitudeDelta, 0.743228000000002, within: 1e-9)
        expectClose(model.region.span.longitudeDelta, 0.8329389999999961, within: 1e-9)
    }
}
