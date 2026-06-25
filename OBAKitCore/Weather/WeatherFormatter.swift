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

    /// Maps an Obaco icon key (Dark Sky-style) to an SF Symbol name.
    /// Returns a generic cloud symbol for unknown keys so the UI never goes blank.
    public static func systemImageName(for iconKey: String) -> String {
        iconToSymbol[iconKey] ?? "cloud.fill"
    }

    private static let iconToSymbol: [String: String] = [
        "clear-day": "sun.max.fill",
        "clear-night": "moon.stars.fill",
        "partly-cloudy-day": "cloud.sun.fill",
        "partly-cloudy-night": "cloud.moon.fill",
        "cloudy": "cloud.fill",
        "rain": "cloud.rain.fill",
        "sleet": "cloud.sleet.fill",
        "snow": "cloud.snow.fill",
        "wind": "wind",
        "fog": "cloud.fog.fill"
    ]

    // MARK: - Condition Text

    /// Localized human-readable condition (e.g. "Clear", "Cloudy"). Day/night
    /// variants collapse to the same word since the icon already conveys time-of-day.
    public static func conditionText(for iconKey: String) -> String {
        switch iconKey {
        case "clear-day", "clear-night":
            return OBALoc("weather.condition.clear", value: "Clear", comment: "Weather condition label for clear skies.")
        case "partly-cloudy-day", "partly-cloudy-night":
            return OBALoc("weather.condition.partly_cloudy", value: "Partly Cloudy", comment: "Weather condition label for partly cloudy skies.")
        case "cloudy":
            return OBALoc("weather.condition.cloudy", value: "Cloudy", comment: "Weather condition label for cloudy skies.")
        case "rain":
            return OBALoc("weather.condition.rain", value: "Rain", comment: "Weather condition label for rain.")
        case "sleet":
            return OBALoc("weather.condition.sleet", value: "Sleet", comment: "Weather condition label for sleet.")
        case "snow":
            return OBALoc("weather.condition.snow", value: "Snow", comment: "Weather condition label for snow.")
        case "wind":
            return OBALoc("weather.condition.wind", value: "Windy", comment: "Weather condition label for windy conditions.")
        case "fog":
            return OBALoc("weather.condition.fog", value: "Fog", comment: "Weather condition label for foggy conditions.")
        default:
            return OBALoc("weather.condition.unknown", value: "—", comment: "Weather condition placeholder when the icon key is unknown.")
        }
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

    // MARK: - High/Low

    /// Hi/Lo over the next 24 hourly entries (or fewer if the server returns less),
    /// each returned as a locale-formatted temperature string. Joining (e.g.
    /// `"H:%@  L:%@"`) is the caller's responsibility.
    public static func highLow(from hourly: [WeatherForecast.HourlyForecast], locale: Locale) -> (high: String, low: String)? {
        let window = hourly.prefix(24)
        guard let high = window.map(\.temperature).max(),
              let low = window.map(\.temperature).min() else { return nil }
        return (formatTemp(high, locale: locale), formatTemp(low, locale: locale))
    }
}
