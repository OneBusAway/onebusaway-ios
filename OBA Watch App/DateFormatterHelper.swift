//
//  DateFormatterHelper.swift
//  OBAWatch Watch App
//
//  Created to match iOS app date formatting
//

import Foundation

/// Helper for formatting dates in watchOS to match iOS app behavior
struct DateFormatterHelper {
    private static let calendar = Calendar.autoupdatingCurrent
    private static let locale = Locale.autoupdatingCurrent
    
    /// Returns a representation of `date` that varies depending on whether `date` happens to be from today or another day.
    /// For instance, if `date` is from today, the `String` returned will simply be the time. If `date` is from any other day, then
    /// the `String` returned will look something like "Formatted short date, 9:41".
    static func contextualDateTimeString(_ date: Date) -> String {
        if calendar.isDateInToday(date) {
            return timeFormatter.string(from: date)
        } else {
            return shortDateTimeFormatter.string(from: date)
        }
    }
    
    /// Converts a date into a human-readable date/time string that conforms to the user's locale.
    private static let shortDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = locale
        return formatter
    }()
    
    /// Converts a date into a human-readable time string that conforms to the user's locale.
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = locale
        return formatter
    }()
    
    /// Formats a date range from start to end date
    static func formattedDateRange(from: Date, to: Date) -> String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = locale
        return formatter.string(from: from, to: to)
    }
}
