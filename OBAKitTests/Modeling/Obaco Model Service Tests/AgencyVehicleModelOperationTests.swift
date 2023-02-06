//
//  AgencyVehicleModelOperationTests.swift
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

// swiftlint:disable force_cast

class AgencyVehicleModelOperationTests: OBATestCase {
    func testSuccesfulVehicleRequest() async throws {
        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        let apiPath = String(format: "https://alerts.example.com/api/v1/regions/%d/vehicles", obacoRegionID)
        dataLoader.mock(URLString: apiPath, with: Fixtures.loadData(file: "vehicles-query-1_1.json"))

        let vehicles = try await obacoService.getVehicles(matching: "1_1")
        XCTAssertEqual(vehicles.count, 29)
        XCTAssertEqual(vehicles.first?.agencyName, "Metro Transit")
        XCTAssertEqual(vehicles.first?.vehicleID, "1_1156")
    }
}
