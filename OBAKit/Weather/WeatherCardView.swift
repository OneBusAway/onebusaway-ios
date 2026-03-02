//
//  WeatherCardView.swift
//  OBAKit
//
//  Created by VED PATEL on 20/02/26.
//

import SwiftUI
import OBAKitCore

struct WeatherCardView: View {
    let forecast: WeatherForecast
    let locale: Locale
    let onDismiss: () -> Void

    private var hourlyHigh: Double {
        forecast.hourlyForecasts.map(\.temperature).max() ?? forecast.currentForecast.temperature
    }

    private var hourlyLow: Double {
        forecast.hourlyForecasts.map(\.temperature).min() ?? forecast.currentForecast.temperature
    }

    var body: some View {
        VStack(spacing: 0) {

            // MARK: - Header row

            HStack(alignment: .center, spacing: 14) {

                styledWeatherIcon(for: forecast.currentForecast.iconName)
                    .font(.system(size: 52))
                    .frame(width: 60)

                VStack(alignment: .leading, spacing: 2) {
                    Text(forecast.regionName)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    Text(conditionText(for: forecast.currentForecast.iconName))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("Chance of Rain: \(Int(forecast.currentForecast.precipProbability * 100))%")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatTemp(forecast.currentForecast.temperature))
                        .font(.system(size: 48, weight: .thin))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text("H:\(formatTemp(hourlyHigh))  L:\(formatTemp(hourlyLow))")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 0)

            // MARK: - Hourly forecast row

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(
                        Array(forecast.hourlyForecasts.prefix(10).enumerated()),
                        id: \.element.time
                    ) { index, hour in
                        hourlyCell(hour: hour, isFirst: index == 0)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            Divider()

            // MARK: - Wind + Precipitation row

            HStack(spacing: 0) {
                detailPill(
                    icon: "wind",
                    iconColor: .secondary,
                    value: formatWindSpeed(forecast.currentForecast.windSpeed)
                )

                Divider()
                    .frame(height: 32)

                detailPill(
                    icon: "drop.fill",
                    iconColor: .blue,
                    value: "\(Int(forecast.currentForecast.precipProbability * 100))%"
                )

                Divider()
                    .frame(height: 32)

                detailPill(
                    icon: "thermometer.medium",
                    iconColor: .orange,
                    value: formatTemp(forecast.currentForecast.temperatureFeelsLike)
                )
            }
            .padding(.vertical, 10)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(0.15),
                        lineWidth: 0.5
                    )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 4)
        .safeAreaInset(edge: .bottom, spacing: 0) {

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
                }
            }
            .padding(.top, 10)
            .frame(maxWidth: .infinity)
        }
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture {
            onDismiss()
        }
    }

    // MARK: - Hourly Cell

    private func hourlyCell(hour: WeatherForecast.HourlyForecast, isFirst: Bool) -> some View {
        VStack(spacing: 6) {
            Text(isFirst ? "Now" : formatTime(hour.time))
                .font(.caption)
                .fontWeight(isFirst ? .semibold : .regular)
                .foregroundColor(isFirst ? .primary : .secondary)

            styledWeatherIcon(for: hour.iconName)
                .font(.body)

            Text(formatTemp(hour.temperature))
                .font(.caption)
                .fontWeight(isFirst ? .bold : .regular)
                .foregroundColor(isFirst ? .primary : .secondary)
        }
        .frame(width: 44)
    }

    // MARK: - Detail Pill

    private func detailPill(icon: String, iconColor: Color, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.subheadline)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = locale
        return formatter.string(from: date)
    }

    private func formatTemp(_ temp: Double) -> String {
        MeasurementFormatter.unitlessConversion(temperature: temp, unit: .fahrenheit, to: locale)
    }

    private func formatWindSpeed(_ speed: Double) -> String {
        let measurement = Measurement(value: speed, unit: UnitSpeed.kilometersPerHour)
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = 0
        return formatter.string(from: measurement)
    }

    private func conditionText(for iconName: String) -> String {
        switch iconName {
        case "clear-day", "clear-night": return "Clear"
        case "rain":                     return "Rain"
        case "snow":                     return "Snow"
        case "sleet":                    return "Sleet"
        case "wind":                     return "Windy"
        case "fog":                      return "Foggy"
        case "cloudy":                   return "Cloudy"
        case "partly-cloudy-day",
             "partly-cloudy-night":      return "Partly Cloudy"
        default:                         return "Unknown"
        }
    }

    // MARK: - Icon Styling

    private struct WeatherIconConfig {
        let name: String
        let primary: Color
        let secondary: Color
    }

    private func weatherIconConfig(for weatherIcon: String) -> WeatherIconConfig {
        switch weatherIcon {
        case "clear-day":           return .init(name: "sun.max.fill", primary: .yellow, secondary: .clear)
        case "clear-night":         return .init(name: "moon.stars.fill", primary: .gray, secondary: .yellow)
        case "rain":                return .init(name: "cloud.rain.fill", primary: .gray, secondary: .blue)
        case "snow":                return .init(name: "cloud.snow.fill", primary: .gray, secondary: .cyan)
        case "sleet":               return .init(name: "cloud.sleet.fill", primary: .gray, secondary: .cyan)
        case "wind":                return .init(name: "wind", primary: .gray, secondary: .clear)
        case "fog":                 return .init(name: "cloud.fog.fill", primary: .gray, secondary: .gray)
        case "cloudy":              return .init(name: "cloud.fill", primary: .gray, secondary: .clear)
        case "partly-cloudy-day":   return .init(name: "cloud.sun.fill", primary: .gray, secondary: .yellow)
        case "partly-cloudy-night": return .init(name: "cloud.moon.fill", primary: .gray, secondary: .indigo)
        default:                    return .init(name: "thermometer", primary: .gray, secondary: .clear)
        }
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
