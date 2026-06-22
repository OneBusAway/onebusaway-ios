//
//  WeatherDisplay.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// View-ready data derived from a `WeatherForecast`. Consumed by both the UIKit
/// weather button on `MapViewController` and the SwiftUI card on
/// `MapPanelRootView`, so both render identical copy. Formatting is delegated
/// to `WeatherFormatter` (OBAKitCore) so the helpers are testable and reusable.
///
/// Fields are grouped into UI-section-shaped nested types: the SwiftUI card's
/// `HeaderRow` / `StatsRow` / hourly strip take exactly the slice they need,
/// not the whole bag.
struct WeatherDisplay: Equatable {
    /// Compact pill string shown on the floating weather button.
    let buttonTitle: String

    /// Top section of the card: icon, region, condition, chance of rain,
    /// current temperature, today's hi/lo.
    let header: Header

    /// Bottom strip: wind speed, precipitation %, feels-like temperature.
    let stats: Stats

    /// Horizontally scrolling 24-hour strip.
    let hourly: [HourlyEntry]

    /// Legacy alert content kept for the UIKit `MapViewController` path. Will
    /// retire once the `OBAUseMapPanelExperience` flag is removed.
    let legacyAlert: LegacyAlert

    init(forecast: WeatherForecast, locale: Locale) {
        self.buttonTitle = WeatherFormatter.formatTemp(
            forecast.currentForecast.temperature,
            locale: locale
        )
        self.header = Header(forecast: forecast, locale: locale)
        self.stats = Stats(forecast: forecast.currentForecast, locale: locale)
        self.hourly = HourlyEntry.list(from: forecast.hourlyForecasts, locale: locale)
        self.legacyAlert = LegacyAlert(forecast: forecast, header: header, stats: stats)
    }
}

// MARK: - Header

extension WeatherDisplay {
    struct Header: Equatable {
        let iconName: String
        let regionName: String
        let conditionSummary: String
        let chanceOfRainText: String
        let currentTemp: String
        let highLowText: String?

        init(forecast: WeatherForecast, locale: Locale) {
            let current = forecast.currentForecast
            let precipPercent = Int(current.precipProbability * 100)

            self.iconName = current.iconName
            self.regionName = forecast.regionName
            self.conditionSummary = WeatherFormatter.conditionText(for: current.iconName)
            self.currentTemp = WeatherFormatter.formatTemp(current.temperature, locale: locale)

            self.chanceOfRainText = String(
                format: OBALoc(
                    "weather.chance_of_rain_format",
                    value: "Chance of Rain: %d%%",
                    comment: "Format for the chance-of-rain percentage on the weather card header. %d is the integer percent."
                ),
                precipPercent
            )

            self.highLowText = WeatherFormatter.highLow(from: forecast.hourlyForecasts, locale: locale)
                .map { hilo in
                    String(
                        format: OBALoc(
                            "weather.high_low_format",
                            value: "H:%@  L:%@",
                            comment: "Format for the high/low temperature line on the weather card. %@ placeholders are temperature strings."
                        ),
                        hilo.high, hilo.low
                    )
                }
        }
    }
}

// MARK: - Stats

extension WeatherDisplay {
    struct Stats: Equatable {
        let windText: String
        let precipText: String
        let feelsLikeText: String

        init(forecast current: WeatherForecast.HourlyForecast, locale: Locale) {
            self.windText = WeatherFormatter.formatWindSpeed(current.windSpeed, locale: locale)
            self.precipText = "\(Int(current.precipProbability * 100))%"
            self.feelsLikeText = WeatherFormatter.formatTemp(current.temperatureFeelsLike, locale: locale)
        }
    }
}

// MARK: - Hourly

struct HourlyEntry: Equatable, Identifiable {
    /// Identity is the hour's timestamp so `ForEach` keeps cells stable across
    /// refreshes — using the array index would let a refreshed list reuse the
    /// same view for what is logically a different hour.
    let id: Date
    let timeLabel: String
    let iconName: String
    let temp: String
    let isNow: Bool

    /// Builds the 24-hour strip from a forecast's hourly array, labelling the
    /// first entry "Now" instead of its formatted time.
    ///
    /// Drops entries that fall before the current hour bucket — the Obaco API
    /// includes the previous full hour in `hourly_forecast` for context, which
    /// would otherwise misalign the "Now" cell with the next entry (showing
    /// the same hour twice, just with different labels).
    static func list(
        from hourlyForecasts: [WeatherForecast.HourlyForecast],
        locale: Locale,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [HourlyEntry] {
        let nowLabel = OBALoc(
            "weather.now",
            value: "Now",
            comment: "First column label in the hourly weather strip, indicating the current hour."
        )
        let currentHourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let upcoming = hourlyForecasts.filter { $0.time >= currentHourStart }
        let nowTimestamp = upcoming.first?.time

        return upcoming.prefix(24).map { hour in
            let isNow = hour.time == nowTimestamp
            return HourlyEntry(
                id: hour.time,
                timeLabel: isNow ? nowLabel : WeatherFormatter.formatTime(hour.time, locale: locale),
                iconName: hour.iconName,
                temp: WeatherFormatter.formatTemp(hour.temperature, locale: locale),
                isNow: isNow
            )
        }
    }
}

// MARK: - Legacy Alert

extension WeatherDisplay {
    /// Content for the `UIAlertController` shown by `MapViewController`'s
    /// non-panel-experience path. Pre-rendered from the same data so the legacy
    /// surface stays in lockstep with the SwiftUI card.
    struct LegacyAlert: Equatable {
        let title: String
        let message: String

        init(forecast: WeatherForecast, header: Header, stats: Stats) {
            self.title = forecast.todaySummary
            let tempLine = String(
                format: OBALoc(
                    "weather.alert.temp_line_format",
                    value: "Temp: %@ (Feels like %@)",
                    comment: "Legacy alert line. First %@ is current temperature, second is feels-like temperature."
                ),
                header.currentTemp, stats.feelsLikeText
            )
            let windLine = String(
                format: OBALoc(
                    "weather.alert.wind_line_format",
                    value: "Wind: %@",
                    comment: "Legacy alert line. %@ is the formatted wind speed."
                ),
                stats.windText
            )
            let precipLine = String(
                format: OBALoc(
                    "weather.alert.precip_line_format",
                    value: "Precipitation: %@ chance",
                    comment: "Legacy alert line. %@ is the chance-of-precipitation percentage."
                ),
                stats.precipText
            )
            self.message = "\(tempLine)\n\(windLine)\n\(precipLine)"
        }
    }
}
