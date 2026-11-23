//
//  RegionalAlertsModelOperationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try force_cast

@Suite(.serialized)
final class RegionalAlertsModelOperationTests: OBATestCase {
    @Test func `Successful request`() async throws {
        let dataLoader = (restService.dataLoader as! MockDataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let agencies = try! Fixtures.loadRESTAPIPayload(type: [AgencyWithCoverage].self, fileName: "agencies_with_coverage.json")
        let alerts = await restService.getAlerts(agencies: agencies)
        #expect(alerts.count == 20)
    }

    @Test func `getAlerts keeps cached alerts when agency fetch fails`() async throws {
        let dataLoader = (restService.dataLoader as! MockDataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let agencies = try! Fixtures.loadRESTAPIPayload(type: [AgencyWithCoverage].self, fileName: "agencies_with_coverage.json")
        let agency = agencies.first(where: { $0.agencyID == "1" })!

        let initialAlerts = await restService.getAlerts(agency: agency)
        #expect(!initialAlerts.isEmpty)

        // Second fetch fails with network error
        dataLoader.removeMappedResponses()
        dataLoader.mock(response: MockDataResponse(data: nil, urlResponse: nil, error: URLError(.notConnectedToInternet)) { $0.url?.path.contains("/alerts-for-agency/") ?? false })

        let cachedAlerts = await restService.getAlerts(agency: agency)
        #expect(cachedAlerts.count == initialAlerts.count)
        #expect(cachedAlerts.map(\.id) == initialAlerts.map(\.id))
    }
}
