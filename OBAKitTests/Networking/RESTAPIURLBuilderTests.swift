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
import MapKit

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
        components.hour = 12
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: components)!
        
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
        components.hour = 12
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: components)!
        
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

    @Test func testGetSurveysWithoutSurveyBaseURLReturnsNil() {
        let builderWithoutSurveys = RESTAPIURLBuilder(
            baseURL: URL(string: "https://api.pugetsound.onebusaway.org")!,
            defaultQueryItems: [URLQueryItem(name: "key", value: "TEST")],
            surveyBaseURL: nil
        )
        #expect(builderWithoutSurveys.getSurveys(userID: "user123", regionID: 1) == nil)
    }

    @Test func testSubmitSurveyResponseWithoutSurveyBaseURLReturnsNil() {
        let builderWithoutSurveys = RESTAPIURLBuilder(
            baseURL: URL(string: "https://api.pugetsound.onebusaway.org")!,
            defaultQueryItems: [URLQueryItem(name: "key", value: "TEST")],
            surveyBaseURL: nil
        )
        #expect(builderWithoutSurveys.submitSurveyResponse() == nil)
    }

    @Test func testUpdateSurveyResponse() {
        let url = builder.updateSurveyResponse(responseID: "resp_123")
        #expect(url?.absoluteString == "https://surveys.onebusaway.org/api/v1/survey_responses/resp_123?key=TEST")
    }

    @Test func testUpdateSurveyResponseEscapesResponseID() throws {
        let url = builder.updateSurveyResponse(responseID: "resp/123 special")
        let unwrappedURL = try #require(url)
        let components = URLComponents(url: unwrappedURL, resolvingAgainstBaseURL: false)
        #expect(components?.percentEncodedPath == "/api/v1/survey_responses/resp%2F123%20special")
    }

    @Test func testUpdateSurveyResponseWithoutSurveyBaseURLReturnsNil() {
        let builderWithoutSurveys = RESTAPIURLBuilder(
            baseURL: URL(string: "https://api.pugetsound.onebusaway.org")!,
            defaultQueryItems: [URLQueryItem(name: "key", value: "TEST")],
            surveyBaseURL: nil
        )
        #expect(builderWithoutSurveys.updateSurveyResponse(responseID: "resp_123") == nil)
    }

    // MARK: - On-demand

    private func queryValue(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    @Test func testGetOnDemandService() {
        let url = builder.getOnDemandService(id: "5088_77652", geometryDetail: .full)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.path == "/api/ondemand/service/5088_77652.json")
        #expect(queryValue(url, "geometryDetail") == "full")
        #expect(queryValue(url, "key") == "TEST")
    }

    @Test func testGetOnDemandServiceEscapesID() {
        let url = builder.getOnDemandService(id: "CC_CC2 med/x", geometryDetail: .simplified)
        #expect(url.absoluteString.contains("/api/ondemand/service/CC_CC2%20med%2Fx.json"))
    }

    @Test func testGetOnDemandServicesForAgency() {
        let url = builder.getOnDemandServices(agencyID: "CC", geometryDetail: .none)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.path == "/api/ondemand/services-for-agency/CC.json")
        #expect(queryValue(url, "geometryDetail") == "none")
        #expect(queryValue(url, "key") == "TEST")
    }

    @Test func testGetOnDemandServicesForRegion() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 38.83, longitude: -77.05),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.2)
        )
        let url = builder.getOnDemandServices(region: region, geometryDetail: .simplified)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.path == "/api/ondemand/services-for-location.json")
        #expect(queryValue(url, "lat").flatMap(Double.init) == 38.83)
        #expect(queryValue(url, "lon").flatMap(Double.init) == -77.05)
        #expect(queryValue(url, "latSpan").flatMap(Double.init) == 0.1)
        #expect(queryValue(url, "lonSpan").flatMap(Double.init) == 0.2)
        #expect(queryValue(url, "radius") == nil, "viewport mode must not send a radius; radius wins the server tiebreak")
        #expect(queryValue(url, "geometryDetail") == "simplified")
    }

    @Test func testGetOnDemandServicesNearPoint() {
        let url = builder.getOnDemandServices(
            near: CLLocationCoordinate2D(latitude: 45.3, longitude: -85.2),
            radiusMeters: 5000,
            geometryDetail: .none
        )
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.path == "/api/ondemand/services-for-location.json")
        #expect(queryValue(url, "lat").flatMap(Double.init) == 45.3)
        #expect(queryValue(url, "lon").flatMap(Double.init) == -85.2)
        #expect(queryValue(url, "radius").flatMap(Double.init) == 5000)
        #expect(queryValue(url, "latSpan") == nil, "point mode never sends a span")
        #expect(queryValue(url, "geometryDetail") == "none")
    }

    // MARK: - Core REST API URL Builder Endpoints

    @Test func testGetVehicleURL() {
        let url = builder.getVehicleURL("1_4321")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.path == "/api/where/vehicle/1_4321.json")
        #expect(queryValue(url, "key") == "TEST")
    }

    @Test func testGetVehicleURLEscapesPathVariable() {
        let url = builder.getVehicleURL("metro/vehicle 99#")
        #expect(url.absoluteString.contains("/api/where/vehicle/metro%2Fvehicle%2099%23.json"))
    }

    @Test func testGetVehicleTrip() {
        let url = builder.getVehicleTrip(vehicleID: "1_5678")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.path == "/api/where/trip-for-vehicle/1_5678.json")
        #expect(queryValue(url, "key") == "TEST")
    }

    @Test func testGetVehicleTripEscapesPathVariable() {
        let url = builder.getVehicleTrip(vehicleID: "agency/bus id")
        #expect(url.absoluteString.contains("/api/where/trip-for-vehicle/agency%2Fbus%20id.json"))
    }

    @Test func testGetCurrentTime() {
        let url = builder.getCurrentTime()
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.path == "/api/where/current-time.json")
        #expect(queryValue(url, "key") == "TEST")
    }

    @Test func testGetStopsAtCoordinate() {
        let coordinate = CLLocationCoordinate2D(latitude: 47.6097, longitude: -122.3331)
        let url = builder.getStops(coordinate: coordinate)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.path == "/api/where/stops-for-location.json")
        #expect(queryValue(url, "lat").flatMap(Double.init) == 47.6097)
        #expect(queryValue(url, "lon").flatMap(Double.init) == -122.3331)
        #expect(queryValue(url, "key") == "TEST")
    }

    @Test func testGetStopsInCoordinateRegion() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 47.6097, longitude: -122.3331),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.08)
        )
        let url = builder.getStops(region: region)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.path == "/api/where/stops-for-location.json")
        #expect(queryValue(url, "lat").flatMap(Double.init) == 47.6097)
        #expect(queryValue(url, "lon").flatMap(Double.init) == -122.3331)
        #expect(queryValue(url, "latSpan").flatMap(Double.init) == 0.05)
        #expect(queryValue(url, "lonSpan").flatMap(Double.init) == 0.08)
        #expect(queryValue(url, "key") == "TEST")
    }

    @Test func testGetStopsInCircularRegionWithQueryClampsRadius() {
        // Radius clamped between 1.0 and 15000.0 meters
        let smallCircle = CLCircularRegion(center: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3), radius: -50.0, identifier: "small")
        let urlSmall = builder.getStops(circularRegion: smallCircle, query: "University")
        #expect(queryValue(urlSmall, "radius") == "1")
        #expect(queryValue(urlSmall, "query") == "University")

        let largeCircle = CLCircularRegion(center: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3), radius: 50000.0, identifier: "large")
        let urlLarge = builder.getStops(circularRegion: largeCircle, query: "Pike")
        #expect(queryValue(urlLarge, "radius") == "15000")
        #expect(queryValue(urlLarge, "query") == "Pike")

        let normalCircle = CLCircularRegion(center: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3), radius: 800.0, identifier: "normal")
        let urlNormal = builder.getStops(circularRegion: normalCircle, query: "3rd Ave")
        #expect(queryValue(urlNormal, "radius") == "800")
    }

    @Test func testGetStopsInRegionWithStopCodeQuery() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3),
            span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.3)
        )
        let url = builder.getStops(region: region, query: "10020")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.path == "/api/where/stops-for-location.json")
        #expect(queryValue(url, "lat").flatMap(Double.init) == 47.6)
        #expect(queryValue(url, "lon").flatMap(Double.init) == -122.3)
        #expect(queryValue(url, "latSpan").flatMap(Double.init) == 0.2)
        #expect(queryValue(url, "lonSpan").flatMap(Double.init) == 0.3)
        #expect(queryValue(url, "query") == "10020")
        #expect(queryValue(url, "radius") == nil, "Region stop code query must not send a radius parameter")
    }

    @Test func testGetStop() {
        let url = builder.getStop(stopID: "1_10020")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.path == "/api/where/stop/1_10020.json")
    }

    @Test func testGetStopEscapesID() {
        let url = builder.getStop(stopID: "agency/stop 123")
        #expect(url.absoluteString.contains("/api/where/stop/agency%2Fstop%20123.json"))
    }

    @Test func testGetArrivalsAndDeparturesForStop() {
        let url = builder.getArrivalsAndDeparturesForStop(id: "1_10020", minutesBefore: 5, minutesAfter: 35)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.path == "/api/where/arrivals-and-departures-for-stop/1_10020.json")
        #expect(queryValue(url, "minutesBefore") == "5")
        #expect(queryValue(url, "minutesAfter") == "35")
    }

    @Test func testGetTripArrivalDepartureAtStop() {
        let serviceDate = Date(timeIntervalSince1970: 1600000000)
        let url = builder.getTripArrivalDepartureAtStop(
            stopID: "1_10020",
            tripID: "1_trip99",
            serviceDate: serviceDate,
            vehicleID: "1_veh12",
            stopSequence: 4
        )
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.path == "/api/where/arrival-and-departure-for-stop/1_10020.json")
        #expect(queryValue(url, "tripId") == "1_trip99")
        #expect(queryValue(url, "vehicleId") == "1_veh12")
        #expect(queryValue(url, "serviceDate") == "1600000000000")
        #expect(queryValue(url, "stopSequence") == "4")
    }

    @Test func testGetTripArrivalDepartureAtStopOmitsOptionalFields() {
        let serviceDate = Date(timeIntervalSince1970: 1600000000)
        let url = builder.getTripArrivalDepartureAtStop(
            stopID: "1_10020",
            tripID: "1_trip99",
            serviceDate: serviceDate,
            vehicleID: nil,
            stopSequence: 0
        )
        #expect(queryValue(url, "vehicleId") == nil)
        #expect(queryValue(url, "stopSequence") == nil, "stopSequence <= 0 must be omitted")
    }

    @Test func testGetTripWithAllParameters() {
        let serviceDate = Date(timeIntervalSince1970: 1600000000)
        let url = builder.getTrip(tripID: "1_trip777", vehicleID: "1_bus88", serviceDate: serviceDate)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.path == "/api/where/trip-details/1_trip777.json")
        #expect(queryValue(url, "vehicleId") == "1_bus88")
        #expect(queryValue(url, "serviceDate") == "1600000000000")
    }

    @Test func testGetTripWithMinimalParameters() {
        let url = builder.getTrip(tripID: "1_trip777", vehicleID: nil, serviceDate: nil)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.path == "/api/where/trip-details/1_trip777.json")
        #expect(queryValue(url, "vehicleId") == nil)
        #expect(queryValue(url, "serviceDate") == nil)
    }

    @Test func testGetStopsForRoute() {
        let url = builder.getStopsForRoute(id: "1_100")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.path == "/api/where/stops-for-route/1_100.json")
    }

    @Test func testGetStopsForRouteEscapesID() {
        let url = builder.getStopsForRoute(id: "agency/route 40")
        #expect(url.absoluteString.contains("/api/where/stops-for-route/agency%2Froute%2040.json"))
    }

    @Test func testGetStopsForAgency() {
        let url = builder.getStopsForAgency(id: "1")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.path == "/api/where/stops-for-agency/1.json")
    }

    @Test func testGetRouteClampsToMaxRegionalRadius() {
        // maxRegionalRadius is 40,000 meters. Radius below 40,000 should be clamped up to 40,000.
        let circleSmall = CLCircularRegion(center: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3), radius: 5000.0, identifier: "small")
        let urlSmall = builder.getRoute(query: "RapidRide", region: circleSmall)
        #expect(queryValue(urlSmall, "radius") == "40000.0")
        #expect(queryValue(urlSmall, "query") == "RapidRide")

        // Radius above 40,000 should remain unchanged
        let circleLarge = CLCircularRegion(center: CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3), radius: 60000.0, identifier: "large")
        let urlLarge = builder.getRoute(query: "Link", region: circleLarge)
        #expect(queryValue(urlLarge, "radius") == "60000.0")
    }

    @Test func testGetConfig() {
        let url = builder.getConfig()
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.path == "/api/where/config.json")
        #expect(queryValue(url, "key") == "TEST")
    }

    @Test func testGetStopProblemAllFields() {
        let location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 47.6097, longitude: -122.3331), altitude: 10, horizontalAccuracy: 5.5, verticalAccuracy: 2.0, timestamp: Date())
        let url = builder.getStopProblem(stopID: "1_10020", code: .busDoesNotStop, comment: "Bus drove past", location: location)
        #expect(queryValue(url, "code") == "bus_does_not_stop")
        #expect(queryValue(url, "userComment") == "Bus drove past")
        #expect(queryValue(url, "userLat") == "47.6097")
        #expect(queryValue(url, "userLon") == "-122.3331")
        #expect(queryValue(url, "userLocationAccuracy") == "5.5")
    }

    @Test func testGetStopProblemMinimalFields() {
        let url = builder.getStopProblem(stopID: "1_10020", code: .other, comment: nil, location: nil)
        #expect(queryValue(url, "code") == "other")
        #expect(queryValue(url, "userComment") == nil)
        #expect(queryValue(url, "userLat") == nil)
        #expect(queryValue(url, "userLon") == nil)
        #expect(queryValue(url, "userLocationAccuracy") == nil)
    }

    @Test func testGetTripProblemAllFields() {
        let serviceDate = Date(timeIntervalSince1970: 1600000000)
        let location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 47.6097, longitude: -122.3331), altitude: 10, horizontalAccuracy: 4.0, verticalAccuracy: 2.0, timestamp: Date())
        let url = builder.getTripProblem(
            tripID: "1_trip100",
            serviceDate: serviceDate,
            vehicleID: "1_veh200",
            stopID: "1_stop300",
            code: .vehicleDoesntStop,
            comment: "Drove right past the stop",
            userOnVehicle: true,
            location: location
        )
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.path == "/api/where/report-problem-with-trip.json")
        #expect(queryValue(url, "tripId") == "1_trip100")
        #expect(queryValue(url, "serviceDate") == "1600000000000")
        #expect(queryValue(url, "vehicleId") == "1_veh200")
        #expect(queryValue(url, "stopId") == "1_stop300")
        #expect(queryValue(url, "code") == "vehicle_doesnt_stop")
        #expect(queryValue(url, "userComment") == "Drove right past the stop")
        #expect(queryValue(url, "userOnVehicle") == "true")
        #expect(queryValue(url, "userLat") == "47.6097")
        #expect(queryValue(url, "userLon") == "-122.3331")
        #expect(queryValue(url, "userLocationAccuracy") == "4.0")
    }

    @Test func testGetTripProblemMinimalFields() {
        let serviceDate = Date(timeIntervalSince1970: 1600000000)
        let url = builder.getTripProblem(
            tripID: "1_trip100",
            serviceDate: serviceDate,
            vehicleID: nil,
            stopID: nil,
            code: .neverCame,
            comment: nil,
            userOnVehicle: false,
            location: nil
        )
        #expect(queryValue(url, "tripId") == "1_trip100")
        #expect(queryValue(url, "serviceDate") == "1600000000000")
        #expect(queryValue(url, "vehicleId") == nil)
        #expect(queryValue(url, "stopId") == nil)
        #expect(queryValue(url, "code") == "never_came")
        #expect(queryValue(url, "userComment") == nil)
        #expect(queryValue(url, "userOnVehicle") == "false")
        #expect(queryValue(url, "userLat") == nil)
        #expect(queryValue(url, "userLon") == nil)
        #expect(queryValue(url, "userLocationAccuracy") == nil)
    }
}
