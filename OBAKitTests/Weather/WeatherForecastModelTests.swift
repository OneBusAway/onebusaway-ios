//
//  WeatherForecastModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Tests for `WeatherForecast` decoding from JSON, coordinates parsing,
/// hourly conditions, temperature ranges, and precipitation probability.
@Suite(.serialized)
final class WeatherForecastModelTests: OBATestCase {

    private func makeForecastJSON(
        lat: Double = 47.6062,
        lon: Double = -122.3321,
        regionId: Int = 1,
        regionName: String = "Puget Sound",
        temp: Double = 65.5,
        precipProb: Double = 0.25
    ) -> Data {
        let json: [String: Any] = [
            "latitude": lat,
            "longitude": lon,
            "region_identifier": regionId,
            "region_name": regionName,
            "retrieved_at": "2023-11-14T22:13:20Z",
            "units": "us",
            "today_summary": "Partly cloudy throughout the day.",
            "current_forecast": [
                "icon": "partly-cloudy-day",
                "precip_per_hour": 0.0,
                "precip_probability": precipProb,
                "summary": "Partly Cloudy",
                "temperature": temp,
                "temperature_feels_like": temp - 2.0,
                "time": 1_700_000_000,
                "wind_speed": 5.4
            ],
            "hourly_forecast": [
                [
                    "icon": "partly-cloudy-day",
                    "precip_per_hour": 0.0,
                    "precip_probability": precipProb,
                    "summary": "Partly Cloudy",
                    "temperature": temp,
                    "temperature_feels_like": temp - 2.0,
                    "time": 1_700_000_000,
                    "wind_speed": 5.4
                ],
                [
                    "icon": "rain",
                    "precip_per_hour": 0.15,
                    "precip_probability": 0.85,
                    "summary": "Light Rain",
                    "temperature": temp - 5.0,
                    "temperature_feels_like": temp - 7.0,
                    "time": 1_700_003_600,
                    "wind_speed": 8.2
                ]
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    @Test func `WeatherForecast decodes correctly from valid Obaco JSON payload`() throws {
        let data = makeForecastJSON()
        let forecast = try JSONDecoder.obacoServiceDecoder.decode(WeatherForecast.self, from: data)

        #expect(forecast.regionIdentifier == 1)
        #expect(forecast.regionName == "Puget Sound")
        #expect(forecast.units == "us")
        #expect(forecast.todaySummary == "Partly cloudy throughout the day.")
        #expect(abs(forecast.location.coordinate.latitude - 47.6062) < 0.0001)
        #expect(abs(forecast.location.coordinate.longitude - (-122.3321)) < 0.0001)

        #expect(forecast.currentForecast.summary == "Partly Cloudy")
        #expect(forecast.currentForecast.iconName == "partly-cloudy-day")
        #expect(forecast.currentForecast.temperature == 65.5)
        #expect(forecast.currentForecast.precipProbability == 0.25)

        #expect(forecast.hourlyForecasts.count == 2)
        #expect(forecast.hourlyForecasts[1].summary == "Light Rain")
        #expect(forecast.hourlyForecasts[1].iconName == "rain")
        #expect(forecast.hourlyForecasts[1].precipPerHour == 0.15)
        #expect(forecast.hourlyForecasts[1].windSpeed == 8.2)
    }

    @Test func `HourlyForecast decodes directly with unix timestamp converted to Date`() throws {
        let hourlyJSON: [String: Any] = [
            "icon": "clear-day",
            "precip_per_hour": 0.0,
            "precip_probability": 0.0,
            "summary": "Clear",
            "temperature": 72.0,
            "temperature_feels_like": 71.0,
            "time": 1_700_000_000,
            "wind_speed": 3.0
        ]
        let data = try JSONSerialization.data(withJSONObject: hourlyJSON)
        let hourly = try JSONDecoder().decode(WeatherForecast.HourlyForecast.self, from: data)

        #expect(hourly.summary == "Clear")
        #expect(hourly.iconName == "clear-day")
        #expect(hourly.temperature == 72.0)
        #expect(hourly.time.timeIntervalSince1970 == 1_700_000_000)
    }

    @Test func `WeatherForecast decoding throws DecodingError when required keys are missing`() {
        // Missing "region_identifier"
        let brokenJSON = """
        {
            "latitude": 47.6,
            "longitude": -122.3,
            "region_name": "Puget Sound",
            "retrieved_at": "2023-11-14T22:13:20Z",
            "units": "us",
            "today_summary": "Sunny",
            "current_forecast": {
                "icon": "clear-day", "precip_per_hour": 0, "precip_probability": 0,
                "summary": "Clear", "temperature": 70, "temperature_feels_like": 70,
                "time": 1700000000, "wind_speed": 3
            },
            "hourly_forecast": []
        }
        """.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            try JSONDecoder.obacoServiceDecoder.decode(WeatherForecast.self, from: brokenJSON)
        }
    }
}
