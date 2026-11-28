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
final class GhostBusReportViewTests: OBATestCase {

    @Test func testGhostBusReportConstants() {
        #expect(GhostBusReportView.waitChoices == [5, 10, 15, 20, 30])
        #expect(GhostBusReportView.commentMaxLength == 1_000)
    }

    @Test func testScheduledTimeTextUsesRegionTimeZone() {
        // The region zone here (UTC+14) is far from any realistic device zone,
        // so the region-formatted string genuinely differs from Date.formatted.
        let formatters = Formatters(locale: .current, calendar: .current, themeColors: .shared)
        formatters.timeZone = TimeZone(identifier: "Pacific/Kiritimati")!
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let text = GhostBusReportContext.scheduledTimeText(from: date, formatters: formatters)

        // The region-zone string, matching the trip page…
        #expect(text == formatters.timeFormatter.string(from: date))
        // …not the device-zone string Date.formatted would produce.
        if formatters.timeZone.secondsFromGMT(for: date) != TimeZone.autoupdatingCurrent.secondsFromGMT(for: date) {
            #expect(text != date.formatted(date: .omitted, time: .shortened))
        }
        #expect(GhostBusReportContext.scheduledTimeText(from: nil, formatters: formatters) == nil)
    }
}
