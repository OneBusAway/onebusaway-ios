//
//  CurrentTimeModelOperationTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 10/30/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

class CurrentTimeModelOperationTests: OBATestCase {

    func testCurrentTime_success() {
        let dataLoader = (restService.dataLoader as! MockDataLoader)
        let data = Fixtures.loadData(file: "current_time.json")
        dataLoader.mock(URLString: "https://www.example.com/api/where/current-time.json", with: data)

        let op = restService.getCurrentTime()
        waitUntil { done in
            op.complete { result in
                switch result {
                case .failure:
                    fatalError()
                case .success(let response):
                    expect(response.currentTime) == 1343587068277
                    done()
                }
            }
        }
    }
}
