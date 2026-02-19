//
//  WeatherForecastView.swift
//  OBAKit
//
//  Created by VED PATEL on 20/02/26.
//

import SwiftUI
import OBAKitCore

struct WeatherForecastView: View {
    let forecast: WeatherForecast
    let locale: Locale
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {

                    VStack(spacing: 8) {
                        styledWeatherIcon(for: forecast.currentForecast.iconName)
                                .font(.system(size: 64))
                                .padding(.bottom, 4)

                        Text(formatTemp(forecast.currentForecast.temperature))
                            .font(.system(size: 54, weight: .bold, design: .rounded))

                        Text(forecast.todaySummary)
                            .font(.title3)
                            .fontWeight(.medium)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Text("Feels like \(formatTemp(forecast.currentForecast.temperatureFeelsLike))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 16)

                        VStack(alignment: .leading, spacing: 12) {
                            Label("HOURLY FORECAST", systemImage: "clock")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                                .padding(.top, 16)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 28) {
                                    ForEach(forecast.hourlyForecasts, id: \.time) { hour in
                                        VStack(spacing: 12) {
                                            Text(formatTime(hour.time))
                                                .font(.subheadline)
                                                .foregroundColor(.primary)

                                            styledWeatherIcon(for: hour.iconName)
                                                    .font(.title2)

                                            Text(formatTemp(hour.temperature))
                                                .font(.headline)
                                                .fontWeight(.semibold)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.bottom, 16)
                            }
                        }
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(16)
                        .padding(.horizontal)

                        VStack(spacing: 0) {
                            WeatherDetailRow(icon: "wind", title: "Wind Speed", value: formatWindSpeed(forecast.currentForecast.windSpeed))
                            Divider().padding(.leading, 50)
                            WeatherDetailRow(icon: "drop.fill", iconColor: .blue, title: "Precipitation", value: "\(Int(forecast.currentForecast.precipProbability * 100))%")
                        }
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(16)
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(forecast.regionName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
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
        return MeasurementFormatter.unitlessConversion(temperature: temp, unit: .fahrenheit, to: locale)
    }

    private func formatWindSpeed(_ speed: Double) -> String {
        let measurementSystem = locale.measurementSystem
        switch measurementSystem {
        case .us, .uk:
            let mph = speed / 1.60934
            return "\(Int(mph)) mph"
        default:
            return "\(Int(speed)) km/h"
        }
    }

    // MARK: - Icon Configuration

    private struct WeatherIconConfig {
        let name: String
        let primary: Color
        let secondary: Color
    }

    private func weatherIconConfig(for weatherIcon: String) -> WeatherIconConfig {
        let mapping: [String: WeatherIconConfig] = [
            "clear-day": WeatherIconConfig(name: "sun.max.fill", primary: .yellow, secondary: .clear),
            "clear-night": WeatherIconConfig(name: "moon.stars.fill", primary: .gray, secondary: .yellow),
            "rain": WeatherIconConfig(name: "cloud.rain.fill", primary: .gray, secondary: .blue),
            "snow": WeatherIconConfig(name: "cloud.snow.fill", primary: .gray, secondary: .cyan),
            "sleet": WeatherIconConfig(name: "cloud.sleet.fill", primary: .gray, secondary: .cyan),
            "wind": WeatherIconConfig(name: "wind", primary: .gray, secondary: .clear),
            "fog": WeatherIconConfig(name: "cloud.fog.fill", primary: .gray, secondary: .gray),
            "cloudy": WeatherIconConfig(name: "cloud.fill", primary: .gray, secondary: .clear),
            "partly-cloudy-day": WeatherIconConfig(name: "cloud.sun.fill", primary: .gray, secondary: .yellow),
            "partly-cloudy-night": WeatherIconConfig(name: "cloud.moon.fill", primary: .gray, secondary: .indigo)
        ]
        return mapping[weatherIcon] ?? WeatherIconConfig(name: "thermometer", primary: .gray, secondary: .clear)
    }

    @ViewBuilder
    private func styledWeatherIcon(for weatherIcon: String) -> some View {
        let config = weatherIconConfig(for: weatherIcon)

        if weatherIcon == "clear-day" {

            Image(systemName: config.name)
                .renderingMode(.original)
        } else {
            Image(systemName: config.name)
                .symbolRenderingMode(.palette)
                .foregroundStyle(config.primary, config.secondary)
        }
    }
}

// MARK: - Subviews

struct WeatherDetailRow: View {
    let icon: String
    var iconColor: Color = .secondary
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.title3)
                .frame(width: 24)

            Text(title)
                .foregroundColor(.primary)

            Spacer()

            Text(value)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
