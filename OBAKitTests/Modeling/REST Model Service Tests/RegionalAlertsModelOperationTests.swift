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
}
