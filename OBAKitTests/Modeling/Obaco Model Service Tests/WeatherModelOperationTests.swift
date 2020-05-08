//
//  WeatherModelOperationTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 11/9/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import XCTest
import Nimble
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

class WeatherOperationTests: OBATestCase {

    func testSuccessfulWeatherRequest() {
        let dataLoader = (obacoService.dataLoader as! MockDataLoader)
        let data = Fixtures.loadData(file: "pugetsound-weather.json")
        dataLoader.mock(URLString: "https://alerts.example.com/api/v1/regions/1/weather.json", with: data)

        let op = obacoService.getWeather()

        waitUntil { done in
            op.complete { result in

                switch result {
                case .failure:
                    fatalError()
                case .success(let response):
                    let forecast = response
                    expect(forecast).toNot(beNil())

                    expect(forecast.location.coordinate.latitude).to(beCloseTo(47.63671875))
                    expect(forecast.location.coordinate.longitude).to(beCloseTo(-122.6953125))

                    expect(forecast.regionIdentifier) == 1
                    expect(forecast.regionName) == "Puget Sound"
                    expect(forecast.retrievedAt) == Date.fromComponents(year: 2018, month: 10, day: 17, hour: 22, minute: 15, second: 55)
                    expect(forecast.units) == "us"
                    expect(forecast.todaySummary) == "Partly cloudy starting tonight."

                    let currentForecast = forecast.currentForecast
                    expect(currentForecast.iconName) == "clear-day"
                    expect(currentForecast.precipPerHour) == 0.0
                    expect(currentForecast.precipProbability) == 0.0
                    expect(currentForecast.summary) == "Clear"
                    expect(currentForecast.temperature) == 70.51
                    expect(currentForecast.temperatureFeelsLike) == 70.51
                    expect(currentForecast.time) == Date.fromComponents(year: 2018, month: 10, day: 17, hour: 21, minute: 49, second: 25)
                    expect(currentForecast.windSpeed) == 0.41

                    let hourlyForecasts = forecast.hourlyForecasts
                    expect(hourlyForecasts.count) == 49
                    expect(hourlyForecasts[6].precipProbability) == 0.01
                    expect(hourlyForecasts[6].precipPerHour) == 0.0006

                    done()
                }
            }
        }
    }
}
