//
//  WeatherFormatter.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//


import Foundation
import SwiftUI

public struct WeatherFormatter {

    private static let hourlyTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    public static func formatTime(_ date: Date, locale: Locale) -> String {
        hourlyTimeFormatter.locale = locale
        return hourlyTimeFormatter.string(from: date)
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
}
