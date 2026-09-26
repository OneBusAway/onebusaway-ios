//
//  DepartureTimeDisplayTests.swift
//  OBAKitTests
//
//  Copyright Â© Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class DepartureTimeDisplayTests {

    private func createFormatters() -> Formatters {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        // ThemeColors requires main actor, but this test class can be @MainActor if needed.
        // Actually, Formatters doesn't inherently need ThemeColors except for color mappings.
        // But we will use the shared one or just initialize.
        return Formatters(locale: Locale(identifier: "en_US"), calendar: calendar, themeColors: ThemeColors.shared)
    }
    
    private func date(byAddingMinutes minutes: Int, to date: Date = Date()) -> Date {
        Calendar(identifier: .gregorian).date(byAdding: .minute, value: minutes, to: date)!
    }

    @MainActor
    @Test func testNonRealtimeDeparture() {
        let formatters = createFormatters()
        let now = Date()
        let scheduled = date(byAddingMinutes: 5, to: now)
        
        // expectedDate differs but isRealTime is false, so it should fallback to scheduledDate
        let display = DepartureTimeDisplay(
            scheduledDate: scheduled,
            expectedDate: date(byAddingMinutes: 10, to: now),
            isRealTime: false,
            formatters: formatters
        )
        
        let formattedScheduled = formatters.formattedClockTime(scheduled)
        
        #expect(display.expectedTimeText == formattedScheduled)
        #expect(display.scheduledTimeText == nil)
        
        let a11yDesc = display.accessibilityTimeDescription
        #expect(a11yDesc.contains("at "))
        #expect(a11yDesc.contains(formattedScheduled))
    }

    @MainActor
    @Test func testRealtimeDepartureWithNoDeviation() {
        let formatters = createFormatters()
        let now = Date()
        let scheduled = date(byAddingMinutes: 5, to: now)
        
        // Both dates are exactly the same
        let display = DepartureTimeDisplay(
            scheduledDate: scheduled,
            expectedDate: scheduled,
            isRealTime: true,
            formatters: formatters
        )
        
        let formattedScheduled = formatters.formattedClockTime(scheduled)
        
        #expect(display.expectedTimeText == formattedScheduled)
        #expect(display.scheduledTimeText == nil)
    }

    @MainActor
    @Test func testRealtimeDepartureWithDeviation() {
        let formatters = createFormatters()
        let now = Date()
        
        // Use fixed dates so that time strings are predictable
        // 2026-09-01 10:00:00 AM
        let scheduled = Date(timeIntervalSince1970: 1788256800) 
        // 2026-09-01 10:15:00 AM
        let expected = Date(timeIntervalSince1970: 1788257700)
        
        let display = DepartureTimeDisplay(
            scheduledDate: scheduled,
            expectedDate: expected,
            isRealTime: true,
            formatters: formatters
        )
        
        let scheduledClock = formatters.timeFormatter.string(from: scheduled)
        let expectedClock = formatters.timeFormatter.string(from: expected)
        
        #expect(display.expectedTimeText == formatters.appendingScheduleBadge(to: expectedClock, at: expected))
        #expect(display.scheduledTimeText == scheduledClock)
        
        let a11yDesc = display.accessibilityTimeDescription
        #expect(a11yDesc.contains("scheduled \(scheduledClock)"))
        #expect(a11yDesc.contains("now expected"))
    }
}
