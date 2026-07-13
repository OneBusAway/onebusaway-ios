//
//  WeatherFormatter.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Pure-Foundation formatting helpers for `WeatherForecast` data. Both the UIKit
/// button path and the SwiftUI card path call into these so display strings stay
/// in lockstep across the app.
public enum WeatherFormatter {

    // MARK: - Icon Mapping

    /// A single icon "condition family" — day/night variants share one case
    /// because the SF Symbol already conveys time-of-day and the localized
    /// word is the same either way.
    private enum ConditionKey {
        case clear, partlyCloudy, cloudy, rain, sleet, snow, wind, fog

        var localizedText: String {
            switch self {
            case .clear:
                return OBALoc("weather.condition.clear", value: "Clear", comment: "Weather condition label for clear skies.")
            case .partlyCloudy:
                return OBALoc("weather.condition.partly_cloudy", value: "Partly Cloudy", comment: "Weather condition label for partly cloudy skies.")
            case .cloudy:
                return OBALoc("weather.condition.cloudy", value: "Cloudy", comment: "Weather condition label for cloudy skies.")
            case .rain:
                return OBALoc("weather.condition.rain", value: "Rain", comment: "Weather condition label for rain.")
            case .sleet:
                return OBALoc("weather.condition.sleet", value: "Sleet", comment: "Weather condition label for sleet.")
            case .snow:
                return OBALoc("weather.condition.snow", value: "Snow", comment: "Weather condition label for snow.")
            case .wind:
                return OBALoc("weather.condition.wind", value: "Windy", comment: "Weather condition label for windy conditions.")
            case .fog:
                return OBALoc("weather.condition.fog", value: "Fog", comment: "Weather condition label for foggy conditions.")
            }
        }
    }

    /// Metadata for a single Obaco icon key. Bundling the SF Symbol and the
    /// condition-text key here means adding a new condition is a single edit
    /// (one new entry in `iconMetadata`) and the drift-warning gate
    /// (`isKnownIconKey`) automatically covers both fallbacks.
    private struct IconMetadata {
        let symbol: String
        let conditionKey: ConditionKey
    }

    /// Single source of truth for Obaco icon keys the app renders. Every
    /// public helper below reads from this table — no parallel lookup tables.
    private static let iconMetadata: [String: IconMetadata] = [
        "clear-day": IconMetadata(symbol: "sun.max.fill", conditionKey: .clear),
        "clear-night": IconMetadata(symbol: "moon.stars.fill", conditionKey: .clear),
        "partly-cloudy-day": IconMetadata(symbol: "cloud.sun.fill", conditionKey: .partlyCloudy),
        "partly-cloudy-night": IconMetadata(symbol: "cloud.moon.fill", conditionKey: .partlyCloudy),
        "cloudy": IconMetadata(symbol: "cloud.fill", conditionKey: .cloudy),
        "rain": IconMetadata(symbol: "cloud.rain.fill", conditionKey: .rain),
        "sleet": IconMetadata(symbol: "cloud.sleet.fill", conditionKey: .sleet),
        "snow": IconMetadata(symbol: "cloud.snow.fill", conditionKey: .snow),
        "wind": IconMetadata(symbol: "wind", conditionKey: .wind),
        "fog": IconMetadata(symbol: "cloud.fog.fill", conditionKey: .fog)
    ]

    /// Maps an Obaco icon key (Dark Sky-style) to an SF Symbol name.
    /// Returns a generic cloud symbol for unknown keys so the UI never goes blank.
    public static func systemImageName(for iconKey: String) -> String {
        iconMetadata[iconKey]?.symbol ?? "cloud.fill"
    }

    /// Whether the given Obaco icon key is modeled by the app. Callers
    /// (e.g. `WeatherDisplay.Header`) use this to log a single warning when
    /// Obaco starts shipping a new condition we don't render — the fallbacks
    /// keep the UI usable, but without this signal the drift is silent.
    public static func isKnownIconKey(_ iconKey: String) -> Bool {
        iconMetadata[iconKey] != nil
    }

    /// Snapshot of every Obaco icon key the app currently models. Exposed so
    /// downstream tables (e.g. the SwiftUI color palette in `WeatherIcon`)
    /// can be asserted complete against this source of truth in tests.
    public static var knownIconKeys: Set<String> {
        Set(iconMetadata.keys)
    }

    // MARK: - Condition Text

    /// Localized human-readable condition (e.g. "Clear", "Cloudy"). Day/night
    /// variants collapse to the same word since the icon already conveys time-of-day.
    public static func conditionText(for iconKey: String) -> String {
        iconMetadata[iconKey]?.conditionKey.localizedText
            ?? OBALoc("weather.condition.unknown", value: "—", comment: "Weather condition placeholder when the icon key is unknown.")
    }

    // MARK: - Temperature

    /// API delivers Fahrenheit; convert to °C for non-US/UK locales.
    public static func formatTemp(_ fahrenheit: Double, locale: Locale) -> String {
        MeasurementFormatter.unitlessConversion(temperature: fahrenheit, unit: .fahrenheit, to: locale)
    }

    // MARK: - Wind

    /// API delivers km/h; convert to mph for US/UK locales.
    public static func formatWindSpeed(_ kmh: Double, locale: Locale) -> String {
        switch locale.measurementSystem {
        case .us, .uk:
            let mph = kmh / 1.60934
            return "\(Int(mph)) mph"
        default:
            return "\(Int(kmh)) km/h"
        }
    }

    // MARK: - Time

    /// Hour-only, localized: e.g. `9 AM` for `en_US`, `09` for many 24-hour
    /// locales. The `"j"` template asks the locale for its preferred hour
    /// field (12- vs. 24-hour), and the missing minutes field keeps the
    /// hourly-strip cells narrow. Allocates a fresh `DateFormatter` per call
    /// so the helper stays nonisolated and free of shared-state races; at
    /// ~24 hourly cells per popup open the cost is negligible.
    public static func formatTime(_ date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("j")
        return formatter.string(from: date)
    }

    // MARK: - Hourly Window

    /// The rolling "next 24 hours" slice of an Obaco hourly forecast, suitable
    /// for both the hourly strip and the hi/lo computation so the two surfaces
    /// can't disagree on which hours they're summarising.
    ///
    /// Obaco's `hourly_forecast` array includes the previous full hour for
    /// context and is not guaranteed to be sorted, and in theory could repeat
    /// an hour on a server-side glitch. This helper:
    ///
    ///   1. Drops anything before the current hour bucket.
    ///   2. Sorts ascending so "first entry" really is the upcoming hour.
    ///   3. De-duplicates by timestamp (keeps the first occurrence) so
    ///      `HourlyEntry.id` stays unique even if Obaco repeats an hour.
    ///   4. Caps at 24 entries.
    public static func upcomingHourly(
        from hourly: [WeatherForecast.HourlyForecast],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [WeatherForecast.HourlyForecast] {
        let currentHourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let sorted = hourly
            .filter { $0.time >= currentHourStart }
            .sorted { $0.time < $1.time }
        var seen = Set<Date>()
        let deduped = sorted.filter { seen.insert($0.time).inserted }
        return Array(deduped.prefix(24))
    }

    // MARK: - High/Low

    /// Hi/Lo over the supplied hourly window (typically the output of
    /// `upcomingHourly`), each returned as a locale-formatted temperature
    /// string. Joining (e.g. `"H:%@  L:%@"`) is the caller's responsibility.
    ///
    /// Callers are responsible for passing a pre-windowed array so the hourly
    /// strip and the hi/lo summary stay in lockstep — this helper does not
    /// re-filter or re-sort.
    public static func highLow(from hourly: [WeatherForecast.HourlyForecast], locale: Locale) -> (high: String, low: String)? {
        guard let high = hourly.map(\.temperature).max(),
              let low = hourly.map(\.temperature).min() else { return nil }
        return (formatTemp(high, locale: locale), formatTemp(low, locale: locale))
    }
}
