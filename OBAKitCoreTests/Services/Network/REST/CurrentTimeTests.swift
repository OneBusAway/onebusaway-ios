//
//  CurrentTimeTests.swift
//  OBAKitCoreTests
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
@testable import OBAKitCore

/// Serves as a canary test for `CoreRESTAPIResponse`.
final class CurrentTimeTests: OBAKitCoreTestCase {
    func testGetTime() async throws {
        dataLoader.mock(
            URLString: "https://www.example.com/api/where/current-time.json",
            with: try Fixtures.loadData(file: "current_time.json")
        )

        let response = try await restAPIService.getCurrentTime()
        XCTAssertEqual(response.currentTime, 1343587068277)
    }
}
