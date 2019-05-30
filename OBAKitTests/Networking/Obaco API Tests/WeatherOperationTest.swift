//
//  WeatherOperationTest.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 10/17/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import OHHTTPStubs
@testable import OBAKit

// swiftlint:disable force_cast force_try

class WeatherOperationTest: OBATestCase {
    func testSuccessfulWeatherRequest() {
        let regionID = "1"
        let apiPath = WeatherOperation.buildAPIPath(regionID: regionID)

        stub(condition: isHost(self.obacoHost) && isPath(apiPath)) { _ in
            return self.JSONFile(named: "pugetsound-weather.json")
        }

        waitUntil { done in
            let op = self.obacoService.getWeather(regionID: regionID)
            op.completionBlock = {
                let data = op.data!
                expect(data).toNot(beNil())

                let json = try! JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
                let todaySummary = json["today_summary"] as! String
                expect(todaySummary) == "Partly cloudy starting tonight."

                done()
            }
        }
    }
}
