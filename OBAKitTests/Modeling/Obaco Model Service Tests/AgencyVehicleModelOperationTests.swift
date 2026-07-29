//
//  AgencyVehicleModelOperationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

@Suite(.serialized)
final class AgencyVehicleModelOperationTests: OBATestCase {
    @Test func `Succesful vehicle request`() async throws {
        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        let apiPath = String(format: "https://alerts.example.com/api/v1/regions/%d/vehicles", obacoRegionID)
        dataLoader.mock(URLString: apiPath, with: Fixtures.loadData(file: "vehicles-query-1_1.json"))

        let vehicles = try await obacoService.getVehicles(matching: "1_1")
        #expect(vehicles.count == 29)
        #expect(vehicles.first?.agencyName == "Metro Transit")
        #expect(vehicles.first?.vehicleID == "1_1156")
    }
}
