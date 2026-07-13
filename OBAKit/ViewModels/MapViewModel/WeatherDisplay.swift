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
    /// current temperature, and the rolling next-24-hour hi/lo (not the
    /// calendar-day high/low — see `WeatherFormatter.highLow`).
    let header: Header

    /// Bottom strip: wind speed, precipitation %, feels-like temperature.
    let stats: Stats

    /// Horizontally scrolling 24-hour strip.
    let hourly: [HourlyEntry]

    init(forecast: WeatherForecast, locale: Locale, now: Date = .now, calendar: Calendar = .current) {
        // Compute the "next 24 hours" window once so the hourly strip and the
        // header's hi/lo are guaranteed to be summarising the same hours —
        // previously `highLow` saw the raw (unfiltered, unsorted) array while
        // the hourly strip saw a filtered+sorted view, and the two could drift
        // by a sample at the past-hour boundary.
        let upcoming = WeatherFormatter.upcomingHourly(from: forecast.hourlyForecasts, now: now, calendar: calendar)

        self.buttonTitle = WeatherFormatter.formatTemp(
            forecast.currentForecast.temperature,
            locale: locale
        )
        self.header = Header(forecast: forecast, upcoming: upcoming, locale: locale)
        self.stats = Stats(forecast: forecast.currentForecast, locale: locale)
        self.hourly = HourlyEntry.list(from: upcoming, locale: locale)
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

        init(forecast: WeatherForecast, upcoming: [WeatherForecast.HourlyForecast], locale: Locale) {
            let current = forecast.currentForecast
            let precipPercent = Int(current.precipProbability * 100)

            self.iconName = current.iconName
            self.regionName = forecast.regionName
            self.conditionSummary = WeatherFormatter.conditionText(for: current.iconName)
            self.currentTemp = WeatherFormatter.formatTemp(current.temperature, locale: locale)

            // The header is the once-per-popup-open entry point for icon
            // rendering, so emit a single breadcrumb here when Obaco ships a
            // condition we don't recognise. Putting this inside `WeatherFormatter`
            // would fire ~24× per open (once per hourly cell) and drown the
            // signal; the `cloud.fill` / "—" fallbacks keep the card usable.
            if !WeatherFormatter.isKnownIconKey(current.iconName) {
                Logger.warn("Unknown weather icon key: \(current.iconName)")
            }

            self.chanceOfRainText = String(
                format: OBALoc(
                    "weather.chance_of_rain_format",
                    value: "Chance of Rain: %d%%",
                    comment: "Format for the chance-of-rain percentage on the weather card header. %d is the integer percent."
                ),
                precipPercent
            )

            self.highLowText = WeatherFormatter.highLow(from: upcoming, locale: locale)
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
            self.precipText = String(
                format: OBALoc(
                    "weather.percent_format",
                    value: "%d%%",
                    comment: "Bare percentage shown in the precipitation stat on the weather card. %d is the integer percent."
                ),
                Int(current.precipProbability * 100)
            )
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

    /// Builds the hourly strip from a pre-windowed forecast slice (typically
    /// the output of `WeatherFormatter.upcomingHourly`), labelling the first
    /// entry "Now" instead of its formatted time.
    ///
    /// Filtering, sorting, and de-duplication are the upstream window's job;
    /// this helper only handles the "Now" label and the projection to a
    /// SwiftUI-friendly shape so the hourly strip and the header's hi/lo can't
    /// disagree on which hours they're describing.
    static func list(
        from upcoming: [WeatherForecast.HourlyForecast],
        locale: Locale
    ) -> [HourlyEntry] {
        let nowLabel = OBALoc(
            "weather.now",
            value: "Now",
            comment: "First column label in the hourly weather strip, indicating the current hour."
        )
        let nowTimestamp = upcoming.first?.time

        return upcoming.map { hour in
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
