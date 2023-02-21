//
//  CurrentTimeModelOperationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

class CurrentTimeModelOperationTests: OBATestCase {

    func testCurrentTime_success() async throws {
        let dataLoader = (restService.dataLoader as! MockDataLoader)

        dataLoader.mock(
            URLString: "https://www.example.com/api/where/current-time.json",
            with: Fixtures.loadData(file: "current_time.json"))

        let response = try await restService.getCurrentTime()
        expect(response.currentTime) == 1343587068277
    }
}
