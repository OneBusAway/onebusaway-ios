//
//  FormattersTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
final class FormattersTests {

    let formatters: Formatters
    let calendar: Calendar

    init() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = cal
        let locale = Locale(identifier: "en_US")
        let themeColors = ThemeColors()
        
        formatters = Formatters(locale: locale, calendar: cal, themeColors: themeColors)
        formatters.timeFormatter.timeZone = TimeZone(secondsFromGMT: 0)!
        formatters.shortDateTimeFormatter.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    @Test func `Time formatting outputs correct time`() {
        let date = Date(timeIntervalSince1970: 1672531200) // 2023-01-01 00:00:00 UTC
        let timeString = formatters.timeFormatter.string(from: date)
        
        // Since iOS 15, DateFormatter might use a narrow no-break space "\u{202F}" instead of a regular space.
        // We'll normalize spaces to test it robustly.
        let normalizedString = timeString.replacingOccurrences(of: "\u{202F}", with: " ")
        #expect(normalizedString == "12:00 AM")
    }

    @Test func `Contextual date time string for today returns just time`() {
        let date = Date()
        let contextualString = formatters.contextualDateTimeString(date)
        let timeString = formatters.timeFormatter.string(from: date)
        #expect(contextualString == timeString)
    }

    @Test func `Contextual date time string for other day returns date and time`() {
        let date = calendar.date(byAdding: .day, value: -2, to: Date())!
        let contextualString = formatters.contextualDateTimeString(date)
        let expectedString = formatters.shortDateTimeFormatter.string(from: date)
        #expect(contextualString == expectedString)
    }

    @Test func `Accessibility value for future arrival on time`() {
        let date = Date(timeIntervalSince1970: 1672531200) // 12:00 AM
        let result = formatters.accessibilityValueForArrivalDeparture(
            arrivalDepartureDate: date, 
            arrivalDepartureMinutes: 5, 
            arrivalDepartureStatus: .arriving, 
            temporalState: .future, 
            scheduleStatus: .onTime
        )
        let timeStr = formatters.timeFormatter.string(from: date)
        #expect(result == "arriving in 5 minutes at \(timeStr).")
    }

    @Test func `Accessibility value for present departure`() {
        let date = Date()
        let result = formatters.accessibilityValueForArrivalDeparture(
            arrivalDepartureDate: date, 
            arrivalDepartureMinutes: 0, 
            arrivalDepartureStatus: .departing, 
            temporalState: .present, 
            scheduleStatus: .onTime
        )
        #expect(result == "departing now!")
    }

    @Test func `Accessibility value for past arrival`() {
        let date = Date(timeIntervalSince1970: 1672531200)
        let result = formatters.accessibilityValueForArrivalDeparture(
            arrivalDepartureDate: date, 
            arrivalDepartureMinutes: -3, 
            arrivalDepartureStatus: .arriving, 
            temporalState: .past, 
            scheduleStatus: .late
        )
        let timeStr = formatters.timeFormatter.string(from: date)
        #expect(result == "arrived 3 minutes ago at \(timeStr).")
    }
}