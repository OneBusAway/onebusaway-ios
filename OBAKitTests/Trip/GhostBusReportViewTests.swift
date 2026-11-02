//
//  GhostBusReportViewTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import Testing
import OBAKitCore
@testable import OBAKit

@MainActor
@Suite(.serialized)
final class GhostBusReportViewTests {

    @Test func testGhostBusReportConstants() {
        #expect(GhostBusReportView.waitChoices == [5, 10, 15, 20, 30])
        #expect(GhostBusReportView.commentMaxLength == 1_000)
    }

    @Test func testGhostBusReportContextInitialization() {
        let date = Date(timeIntervalSince1970: 1700000000)
        let context = GhostBusReportContext(
            routeAndHeadsign: "10 - Downtown",
            stopName: "Pine St & 4th Ave",
            scheduledTime: date,
            vehicleID: "4102"
        )

        #expect(context.routeAndHeadsign == "10 - Downtown")
        #expect(context.stopName == "Pine St & 4th Ave")
        #expect(context.scheduledTime == date)
        #expect(context.vehicleID == "4102")
    }

    @Test func testGhostBusReportContextWithNilOptionals() {
        let context = GhostBusReportContext(
            routeAndHeadsign: "44 - Ballard",
            stopName: nil,
            scheduledTime: nil,
            vehicleID: nil
        )

        #expect(context.routeAndHeadsign == "44 - Ballard")
        #expect(context.stopName == nil)
        #expect(context.scheduledTime == nil)
        #expect(context.vehicleID == nil)
    }
}
