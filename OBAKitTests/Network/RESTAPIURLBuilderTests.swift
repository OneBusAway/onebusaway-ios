//
//  RESTAPIURLBuilderTests.swift
//  OBAKitTests
//
//  Copyright (c) Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore
import CoreLocation

@Suite(.serialized)
final class RESTAPIURLBuilderTests {
    
    var builder: RESTAPIURLBuilder!
    
    init() {
        builder = RESTAPIURLBuilder(baseURL: URL(string: "https://api.pugetsound.onebusaway.org")!, defaultQueryItems: [URLQueryItem(name: "key", value: "TEST")], surveyBaseURL: URL(string: "https://surveys.onebusaway.org")!)
    }

    @Test func testGetShape() {
        let url = builder.getShape(id: "1_10020")
        #expect(url.absoluteString == "https://api.pugetsound.onebusaway.org/api/where/shape/1_10020.json?key=TEST")
    }

    @Test func testGetAgenciesWithCoverage() {
        let url = builder.getAgenciesWithCoverage()
        #expect(url.absoluteString == "https://api.pugetsound.onebusaway.org/api/where/agencies-with-coverage.json?key=TEST")
    }

    @Test func testGetScheduleForRoute() {
        let url = builder.getScheduleForRoute(id: "1_100")
        #expect(url.absoluteString == "https://api.pugetsound.onebusaway.org/api/where/schedule-for-route/1_100.json?key=TEST")
        
        var components = DateComponents()
        components.year = 2023
        components.month = 1
        components.day = 1
        let date = Calendar.current.date(from: components)!
        
        let urlWithDate = builder.getScheduleForRoute(id: "1_100", date: date)
        let urlComponents = URLComponents(url: urlWithDate, resolvingAgainstBaseURL: false)
        #expect(urlComponents?.path == "/api/where/schedule-for-route/1_100.json")
        #expect(urlComponents?.queryItems?.contains(URLQueryItem(name: "date", value: "2023-01-01")) == true)
        #expect(urlComponents?.queryItems?.contains(URLQueryItem(name: "key", value: "TEST")) == true)
    }

    @Test func testGetScheduleForStop() {
        let url = builder.getScheduleForStop(id: "1_10020")
        #expect(url.absoluteString == "https://api.pugetsound.onebusaway.org/api/where/schedule-for-stop/1_10020.json?key=TEST")
        
        var components = DateComponents()
        components.year = 2023
        components.month = 1
        components.day = 1
        let date = Calendar.current.date(from: components)!
        
        let urlWithDate = builder.getScheduleForStop(id: "1_10020", date: date)
        let urlComponents = URLComponents(url: urlWithDate, resolvingAgainstBaseURL: false)
        #expect(urlComponents?.path == "/api/where/schedule-for-stop/1_10020.json")
        #expect(urlComponents?.queryItems?.contains(URLQueryItem(name: "date", value: "2023-01-01")) == true)
        #expect(urlComponents?.queryItems?.contains(URLQueryItem(name: "key", value: "TEST")) == true)
    }

    @Test func testGetRESTRegionalAlerts() {
        let url = builder.getRESTRegionalAlerts(agencyID: "1")
        #expect(url.absoluteString == "https://api.pugetsound.onebusaway.org/api/gtfs_realtime/alerts-for-agency/1.pb?key=TEST")
    }

    @Test func testGetStopProblem() {
        let location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3), altitude: 0, horizontalAccuracy: 10, verticalAccuracy: 10, timestamp: Date())
        let url = builder.getStopProblem(stopID: "1_10020", code: .nameWrong, comment: "Wrong name", location: location)
        
        let urlString = url.absoluteString
        #expect(urlString.contains("/api/where/report-problem-with-stop/1_10020.json"))
        #expect(urlString.contains("code=stop_name_wrong"))
        #expect(urlString.contains("userComment=Wrong%20name"))
        #expect(urlString.contains("userLat=47.6"))
        #expect(urlString.contains("userLon=-122.3"))
    }

    @Test func testGetSurveys() {
        let url = builder.getSurveys(userID: "user123", regionID: 1)!
        let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(urlComponents?.path == "/api/v1/regions/1/surveys.json")
        #expect(urlComponents?.queryItems?.contains(URLQueryItem(name: "user_id", value: "user123")) == true)
        #expect(urlComponents?.queryItems?.contains(URLQueryItem(name: "key", value: "TEST")) == true)
    }

    @Test func testSubmitSurveyResponse() {
        let url = builder.submitSurveyResponse()
        #expect(url?.absoluteString == "https://surveys.onebusaway.org/api/v1/survey_responses/?key=TEST")
    }
}
