//
//  WeatherForecast.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation

// swiftlint:disable nesting

/// Represents a weather forecast—usually for the region where the user is located. Part of the Obaco service.
public class WeatherForecast: NSObject, Decodable {
    public let location: CLLocation

    public let regionIdentifier: Int
    public let regionName: String

    public let retrievedAt: Date

    public let units: String

    public let todaySummary: String

    public let currentForecast: HourlyForecast

    public let hourlyForecasts: [HourlyForecast]

    private enum CodingKeys: String, CodingKey {
        case latitude, longitude
        case regionIdentifier = "region_identifier"
        case regionName = "region_name"
        case retrievedAt = "retrieved_at"
        case units
        case todaySummary = "today_summary"
        case currentForecast = "current_forecast"
        case hourlyForecast = "hourly_forecast"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let lat = try container.decode(Double.self, forKey: .latitude)
        let long = try container.decode(Double.self, forKey: .longitude)
        location = CLLocation(latitude: lat, longitude: long)

        regionIdentifier = try container.decode(Int.self, forKey: .regionIdentifier)
        regionName = try container.decode(String.self, forKey: .regionName)
        retrievedAt = try container.decode(Date.self, forKey: .retrievedAt)
        units = try container.decode(String.self, forKey: .units)
        todaySummary = try container.decode(String.self, forKey: .todaySummary)

        currentForecast = try container.decode(WeatherForecast.HourlyForecast.self, forKey: .currentForecast)
        hourlyForecasts = try container.decode([WeatherForecast.HourlyForecast].self, forKey: .hourlyForecast)
    }

    /// A part of a `WeatherForecast`. Represents one hour's weather conditions. Part of the Obaco service.
    public class HourlyForecast: NSObject, Decodable {
        public let iconName: String
        public let precipPerHour: Double
        public let precipProbability: Double
        public let summary: String
        public let temperature: Double
        public let temperatureFeelsLike: Double
        public let time: Date
        public let windSpeed: Double

        private enum CodingKeys: String, CodingKey {
            case iconName = "icon"
            case precipPerHour = "precip_per_hour"
            case precipProbability = "precip_probability"
            case summary
            case temperature
            case temperatureFeelsLike = "temperature_feels_like"
            case time
            case windSpeed = "wind_speed"
        }

        public required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            iconName = try container.decode(String.self, forKey: .iconName)
            precipPerHour = try container.decode(Double.self, forKey: .precipPerHour)
            precipProbability = try container.decode(Double.self, forKey: .precipProbability)
            summary = try container.decode(String.self, forKey: .summary)
            temperature = try container.decode(Double.self, forKey: .temperature)
            temperatureFeelsLike = try container.decode(Double.self, forKey: .temperatureFeelsLike)
            time = Date(timeIntervalSince1970: try container.decode(TimeInterval.self, forKey: .time))
            windSpeed = try container.decode(Double.self, forKey: .windSpeed)
        }
    }
}

// swiftlint:enable nesting
