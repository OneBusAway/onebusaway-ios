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
    func testSuccesfulVehicleRequest() {
        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        let apiPath = String(format: "https://alerts.example.com/api/v1/regions/%d/vehicles", obacoRegionID)
        dataLoader.mock(URLString: apiPath, with: Fixtures.loadData(file: "vehicles-query-1_1.json"))

        let op = obacoService.getVehicles(matching: "1_1")

        waitUntil { done in
            op.complete { result in
                switch result {
                case .failure(let error):
                    print("TODO FIXME handle error! \(error)")
                case .success(let response):
                    let matches = response
                    expect(matches.count) == 29
                    expect(matches.first!.agencyName) == "Metro Transit"
                    expect(matches.first!.vehicleID) == "1_1156"
                    done()
                }
            }
        }
    }
}
