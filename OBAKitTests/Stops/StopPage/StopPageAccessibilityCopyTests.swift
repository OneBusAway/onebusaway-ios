//
//  StopPageAccessibilityCopyTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
struct StopPageAccessibilityCopyTests {

    @Test func `First stop VoiceOver says departs not arrives`() {
        let text = StopPageAccessibilityCopy.upcomingIdentity(
            routeShortName: "8",
            headsign: "Seattle Center",
            minutes: 5,
            arrivalDepartureStatus: .departing,
            adherence: "on time"
        )
        #expect(text.contains("departs"))
        #expect(!text.contains("arrives"))
    }

    @Test func `Mid route VoiceOver says arrives not departs`() {
        let text = StopPageAccessibilityCopy.upcomingIdentity(
            routeShortName: "8",
            headsign: "Seattle Center",
            minutes: 5,
            arrivalDepartureStatus: .arriving,
            adherence: "on time"
        )
        #expect(text.contains("arrives"))
        #expect(!text.contains("departs"))
    }

    @Test func `Grouped card VoiceOver says next arrival when the vehicle is arriving`() {
        let text = StopPageAccessibilityCopy.groupedCardIdentity(
            routeShortName: "8",
            headsign: "Seattle Center",
            minutes: 5,
            arrivalDepartureStatus: .arriving,
            adherence: "on time",
            moreCount: 3
        )
        #expect(text.contains("next arrival"))
        #expect(!text.contains("next departure"))
    }

    @Test func `Grouped card VoiceOver says next departure when the vehicle is leaving`() {
        let text = StopPageAccessibilityCopy.groupedCardIdentity(
            routeShortName: "8",
            headsign: "Seattle Center",
            minutes: 5,
            arrivalDepartureStatus: .departing,
            adherence: "on time",
            moreCount: 3
        )
        #expect(text.contains("next departure"))
        #expect(!text.contains("next arrival"))
    }
}
