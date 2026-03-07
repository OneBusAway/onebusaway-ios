//
//  WeatherCardView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

struct WeatherCardView: View {
    let forecast: WeatherForecast
    let locale: Locale
    let onDismiss: () -> Void

    private var hourlyHigh: Double {
        let maxHourly = forecast.hourlyForecasts.map(\.temperature).max() ?? forecast.currentForecast.temperature
        return max(maxHourly, forecast.currentForecast.temperature)
    }

    private var hourlyLow: Double {
        let minHourly = forecast.hourlyForecasts.map(\.temperature).min() ?? forecast.currentForecast.temperature
        return min(minHourly, forecast.currentForecast.temperature)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            hourlyRow
            Divider()
            detailRow
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            String(
                format: OBALoc(
                    "weather_card.accessibility_label",
                    value: "Weather forecast for %@",
                    comment: "Accessibility label for the weather forecast card. e.g. Weather forecast for Tampa Bay"
                ),
                forecast.regionName
            )
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            closeButton
        }
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 14) {
            styledWeatherIcon(for: forecast.currentForecast.iconName)
                .font(.system(size: 52))
                .frame(width: 60)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(forecast.regionName)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .accessibilityAddTraits(.isHeader)

                Text(WeatherFormatter.conditionText(for: forecast.currentForecast.iconName))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(
                    String(
                        format: OBALoc(
                            "weather_card.chance_of_rain_fmt",
                            value: "Chance of Rain: %@",
                            comment: "Chance of rain percentage label in weather card. e.g. Chance of Rain: 20%"
                        ),
                        "\(Int(forecast.currentForecast.precipProbability * 100))%"
                    )
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(WeatherFormatter.formatTemp(forecast.currentForecast.temperature, locale: locale))
                    .font(.system(size: 48, weight: .thin))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel(
                        String(
                            format: OBALoc(
                                "weather_card.current_temperature_fmt",
                                value: "Current temperature: %@",
                                comment: "Accessibility label for current temperature. e.g. Current temperature: 21°"
                            ),
                            WeatherFormatter.formatTemp(forecast.currentForecast.temperature, locale: locale)
                        )
                    )

                Text(
                    String(
                        format: OBALoc(
                            "weather_card.high_low_fmt",
                            value: "H:%@  L:%@",
                            comment: "High and low temperature label in weather card. e.g. H:24°  L:17°"
                        ),
                        WeatherFormatter.formatTemp(hourlyHigh, locale: locale),
                        WeatherFormatter.formatTemp(hourlyLow, locale: locale)
                    )
                )
                .font(.footnote)
                .foregroundColor(.secondary)
                .accessibilityLabel(
                    String(
                        format: OBALoc(
                            "weather_card.high_low.accessibility_fmt",
                            value: "High %@, Low %@",
                            comment: "Accessibility label for high and low temperatures. e.g. High 24°, Low 17°"
                        ),
                        WeatherFormatter.formatTemp(hourlyHigh, locale: locale),
                        WeatherFormatter.formatTemp(hourlyLow, locale: locale)
                    )
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(
                format: OBALoc(
                    "weather_card.header.accessibility_fmt",
                    value: "%@. %@. %@. Chance of rain: %@. High %@, Low %@.",
                    comment: "Full accessibility description of weather card header."
                ),
                forecast.regionName,
                WeatherFormatter.conditionText(for: forecast.currentForecast.iconName),
                WeatherFormatter.formatTemp(forecast.currentForecast.temperature, locale: locale),
                "\(Int(forecast.currentForecast.precipProbability * 100))%",
                WeatherFormatter.formatTemp(hourlyHigh, locale: locale),
                WeatherFormatter.formatTemp(hourlyLow, locale: locale)
            )
        )
    }

    // MARK: - Hourly Row

    private var hourlyRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(
                    Array(forecast.hourlyForecasts.prefix(10).enumerated()),
                    id: \.element.time
                ) { index, hour in
                    hourlyCellView(hour: hour, isFirst: index == 0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .accessibilityLabel(
            OBALoc(
                "weather_card.hourly_forecast",
                value: "Hourly Forecast",
                comment: "Accessibility label for the hourly forecast scroll view in the weather card"
            )
        )
    }

    private func hourlyCellView(hour: WeatherForecast.HourlyForecast, isFirst: Bool) -> some View {
        let timeLabel = isFirst
            ? OBALoc("weather_card.now", value: "Now", comment: "Label for the current hour in the hourly forecast")
        : WeatherFormatter.formatTime(hour.time, locale: locale)

        return VStack(spacing: 6) {
            Text(timeLabel)
                .font(.caption)
                .fontWeight(isFirst ? .semibold : .regular)
                .foregroundColor(isFirst ? .primary : .secondary)

            styledWeatherIcon(for: hour.iconName)
                .font(.body)
                .accessibilityHidden(true)

            Text(WeatherFormatter.formatTemp(hour.temperature, locale: locale))
                .font(.caption)
                .fontWeight(isFirst ? .bold : .regular)
                .foregroundColor(isFirst ? .primary : .secondary)
        }
        .frame(width: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(
                format: OBALoc(
                    "weather_card.hourly_cell.accessibility_fmt",
                    value: "%@: %@, %@",
                    comment: "Accessibility label for an hourly forecast cell. Arguments: time, condition, temperature. e.g. Now: Clear, 22°"
                ),
                timeLabel,
                WeatherFormatter.conditionText(for: hour.iconName),
                WeatherFormatter.formatTemp(hour.temperature, locale: locale)
            )
        )
    }

    // MARK: - Detail Row

    private var detailRow: some View {
        HStack(spacing: 0) {
            detailPill(
                icon: "wind",
                iconColor: .secondary,
                value: WeatherFormatter.formatWindSpeed(forecast.currentForecast.windSpeed, locale: locale),
                accessibilityLabel: String(
                    format: OBALoc(
                        "weather_card.wind_speed_fmt",
                        value: "Wind speed: %@",
                        comment: "Accessibility label for wind speed in the weather card. e.g. Wind speed: 9 km/h"
                    ),
                    WeatherFormatter.formatWindSpeed(forecast.currentForecast.windSpeed, locale: locale)
                )
            )

            Divider().frame(height: 32)

            detailPill(
                icon: "drop.fill",
                iconColor: .blue,
                value: "\(Int(forecast.currentForecast.precipProbability * 100))%",
                accessibilityLabel: String(
                    format: OBALoc(
                        "weather_card.precipitation_fmt",
                        value: "Precipitation: %@",
                        comment: "Accessibility label for precipitation percentage in the weather card. e.g. Precipitation: 0%"
                    ),
                    "\(Int(forecast.currentForecast.precipProbability * 100))%"
                )
            )

            Divider().frame(height: 32)

            detailPill(
                icon: "thermometer.medium",
                iconColor: .orange,
                value: WeatherFormatter.formatTemp(forecast.currentForecast.temperatureFeelsLike, locale: locale),
                accessibilityLabel: String(
                    format: OBALoc(
                        "weather_card.feels_like_fmt",
                        value: "Feels like: %@",
                        comment: "Accessibility label for feels like temperature in the weather card. e.g. Feels like: 17°"
                    ),
                    WeatherFormatter.formatTemp(forecast.currentForecast.temperatureFeelsLike, locale: locale)
                )
            )
        }
        .padding(.vertical, 10)
    }

    private func detailPill(icon: String, iconColor: Color, value: String, accessibilityLabel: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.subheadline)
                .accessibilityHidden(true)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Close Button

    private var closeButton: some View {
        Button(action: onDismiss) {
            ZStack {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
                    .frame(width: 72, height: 32)
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)

                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(
            OBALoc(
                "weather_card.close_button",
                value: "Close weather forecast",
                comment: "Accessibility label for the close button on the weather forecast card"
            )
        )
        .accessibilityHint(
            OBALoc(
                "weather_card.close_button.hint",
                value: "Closes the weather forecast card",
                comment: "Accessibility hint for the close button on the weather forecast card"
            )
        )
        .accessibilityAddTraits(.isButton)
        .padding(.top, 10)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Icon Styling

    private struct WeatherIconConfig {
        let name: String
        let primary: Color
        let secondary: Color
    }

    private static let iconConfigMap: [String: WeatherIconConfig] = [
        "clear-day": .init(name: "sun.max.fill", primary: .yellow, secondary: .clear),
        "clear-night": .init(name: "moon.stars.fill", primary: .gray, secondary: .yellow),
        "rain": .init(name: "cloud.rain.fill", primary: .gray, secondary: .blue),
        "snow": .init(name: "cloud.snow.fill", primary: .gray, secondary: .cyan),
        "sleet": .init(name: "cloud.sleet.fill", primary: .gray, secondary: .cyan),
        "wind": .init(name: "wind", primary: .gray, secondary: .clear),
        "fog": .init(name: "cloud.fog.fill", primary: .gray, secondary: .gray),
        "cloudy": .init(name: "cloud.fill", primary: .gray, secondary: .clear),
        "partly-cloudy-day": .init(name: "cloud.sun.fill", primary: .gray, secondary: .yellow),
        "partly-cloudy-night": .init(name: "cloud.moon.fill", primary: .gray, secondary: .indigo)
    ]

    private func weatherIconConfig(for weatherIcon: String) -> WeatherIconConfig {
        return Self.iconConfigMap[weatherIcon]
            ?? .init(name: "thermometer", primary: .gray, secondary: .clear)
    }

    @ViewBuilder
    private func styledWeatherIcon(for weatherIcon: String) -> some View {
        let config = weatherIconConfig(for: weatherIcon)
        if weatherIcon == "clear-day" {
            Image(systemName: config.name).renderingMode(.original)
        } else {
            Image(systemName: config.name)
                .symbolRenderingMode(.palette)
                .foregroundStyle(config.primary, config.secondary)
        }
    }
}
