//
//  WeatherFormatter.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

public struct WeatherFormatter {

    public static func formatTime(_ date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = locale
        return formatter.string(from: date)
    }

    public static func formatTemp(_ temp: Double, locale: Locale) -> String {
        MeasurementFormatter.unitlessConversion(temperature: temp, unit: .fahrenheit, to: locale)
    }

    public static func formatWindSpeed(_ speed: Double, locale: Locale) -> String {
        let measurement = Measurement(value: speed, unit: UnitSpeed.kilometersPerHour)
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = 0
        return formatter.string(from: measurement)
    }

    public static func systemImageName(for weatherIcon: String) -> String {
        let mapping: [String: String] = [
            "clear-day": "sun.max.fill",
            "clear-night": "moon.stars.fill",
            "rain": "cloud.rain.fill",
            "snow": "cloud.snow.fill",
            "sleet": "cloud.sleet.fill",
            "wind": "wind",
            "fog": "cloud.fog.fill",
            "cloudy": "cloud.fill",
            "partly-cloudy-day": "cloud.sun.fill",
            "partly-cloudy-night": "cloud.moon.fill"
        ]
        return mapping[weatherIcon] ?? "thermometer"
    }

    public static func conditionText(for iconName: String) -> String {
        switch iconName {
        case "clear-day", "clear-night":
            return OBALoc("weather_card.condition.clear", value: "Clear", comment: "Clear weather condition label in weather card")
        case "rain":
            return OBALoc("weather_card.condition.rain", value: "Rain", comment: "Rainy weather condition label in weather card")
        case "snow":
            return OBALoc("weather_card.condition.snow", value: "Snow", comment: "Snowy weather condition label in weather card")
        case "sleet":
            return OBALoc("weather_card.condition.sleet", value: "Sleet", comment: "Sleet weather condition label in weather card")
        case "wind":
            return OBALoc("weather_card.condition.wind", value: "Windy", comment: "Windy weather condition label in weather card")
        case "fog":
            return OBALoc("weather_card.condition.fog", value: "Foggy", comment: "Foggy weather condition label in weather card")
        case "cloudy":
            return OBALoc("weather_card.condition.cloudy", value: "Cloudy", comment: "Cloudy weather condition label in weather card")
        case "partly-cloudy-day", "partly-cloudy-night":
            return OBALoc("weather_card.condition.partly_cloudy", value: "Partly Cloudy", comment: "Partly cloudy weather condition label in weather card")
        default:
            return OBALoc("weather_card.condition.unknown", value: "Unknown", comment: "Unknown weather condition label in weather card")
        }
    }
}
