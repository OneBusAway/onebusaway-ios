//
//  TimeZone.swift
//  OBAKit
//
//  Created by Mohamed Sliem on 11/03/2026.
//

import Foundation

public extension TimeZone {
    /// A short, English abbreviation for this time zone when it differs from the user's current time zone.
    ///
    /// Returns the time zone's localized "short generic" name (for example, "PT" or "ET") using the `en_US` locale.
    /// If this time zone has the same GMT offset as the device's current time zone, `nil` is returned so callers
    /// can omit redundant information.
    var timeZoneAbbreviation: String? {
        guard TimeZone.current.secondsFromGMT(for: Date.now) != self.secondsFromGMT(for: Date.now) else { return nil }
        return self.localizedName(for: .shortGeneric, locale: Locale(identifier: "en_US"))
    }
}

