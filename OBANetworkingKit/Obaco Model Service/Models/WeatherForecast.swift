//
//  WeatherForecast.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 11/9/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import CoreLocation
import Foundation

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
        case regionIdentifier
        case regionName
        case retrievedAt
        case units
        case todaySummary
        case currentForecast
        case hourlyForecast
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

        currentForecast = try container.decode(HourlyForecast.self, forKey: .currentForecast)
        hourlyForecasts = try container.decode([HourlyForecast].self, forKey: .hourlyForecast)
    }
}

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
        case precipPerHour, precipProbability
        case summary
        case temperature, temperatureFeelsLike
        case time
        case windSpeed
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
