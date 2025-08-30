//
//  RESTAPIURLBuilder.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import MapKit

// MARK: - URL Builder Class

/// Creates `URL`s for the `RESTAPIService`.
///
/// This class is designed to handle the oddities of different OBA regions' URL schemes without over- or under-escaping paths.
class RESTAPIURLBuilder: NSObject {
    private let baseURL: URL
    private let defaultQueryItems: [URLQueryItem]
    private let surveyBaseURL: URL?

    init(baseURL: URL, defaultQueryItems: [URLQueryItem]) {
        self.baseURL = baseURL
        self.defaultQueryItems = defaultQueryItems
        self.surveyBaseURL = nil
    }

    init(baseURL: URL, defaultQueryItems: [URLQueryItem], surveyBaseURL: URL?) {
          self.baseURL = baseURL
          self.defaultQueryItems = defaultQueryItems
          self.surveyBaseURL = surveyBaseURL
      }

    public func generateURL(path: String, params: [String: Any]? = nil) -> URL {
        let urlString = joinBaseURLToPath(path)
        let queryParamString = buildQueryParams(params)
        let fullURLString = String(format: "%@?%@", urlString, queryParamString)

        return URL(string: fullURLString)!
    }

    private func joinBaseURLToPath(_ path: String) -> String {
        let baseURLString = baseURL.absoluteString

        if baseURLString.hasSuffix("/") && path.hasPrefix("/") {
            return baseURLString + String(path.dropFirst())
        }
        else if !baseURLString.hasSuffix("/") && !path.hasPrefix("/") {
            return String(format: "%@/%@", baseURLString, path)
        }
        else {
            return baseURLString + path
        }
    }

    /// Takes in a hash of params and this object's default query items, and produces a list of `&`-separated `key=value` pairs.
    /// - Parameter params: Additional query parameters having to do with the in-flight API call.
    private func buildQueryParams(_ params: [String: Any]? = nil) -> String {
        let allQueryItems: [URLQueryItem] = NetworkHelpers.dictionary(toQueryItems: params ?? [:]) + defaultQueryItems
        return allQueryItems.compactMap { queryItem in
            guard
                let key = queryItem.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                let value = queryItem.value?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            else {
                return nil
            }

            return String(format: "%@=%@", key, value)
        }.joined(separator: "&")
    }
}

// MARK: - REST API URL Builders

extension RESTAPIURLBuilder {
    /// Creates a full URL for the `getVehicle` API call, including query params.
    ///
    /// API Endpoint: `/api/where/vehicle/{id}.json`
    ///
    /// - Parameter vehicleID: Vehicle ID string
    /// - Returns: An URL suitable for making a request to retrieve information.
    func getVehicleURL(_ vehicleID: String) -> URL {
        return generateURL(path: String(
            format: "/api/where/vehicle/%@.json",
            NetworkHelpers.escapePathVariable(vehicleID)
        ))
    }

    /// Creates a full URL for the `getVehicleTrip` API call, including query params.
    ///
    /// - API Endpoint: `/api/where/trip-for-vehicle/{id}.json`
    ///
    /// - Parameters:
    ///   - vehicleID: The ID of the vehicle
    /// - Returns: An URL suitable for making a request to retrieve information.
    public func getVehicleTrip(vehicleID: String) -> URL {
        let apiPath = String(format: "/api/where/trip-for-vehicle/%@.json", NetworkHelpers.escapePathVariable(vehicleID))
        return generateURL(path: apiPath)
    }

    /// Creates a full URL for the `getCurrentTime` API call, including query params.
    ///
    /// - API Endpoint: `/api/where/current-time.json`
    ///
    /// - Returns: An URL suitable for making a request to retrieve information.
    public func getCurrentTime() -> URL {
        generateURL(path: "/api/where/current-time.json")
    }

    // MARK: - Stops

    private var getStopsAPIPath: String { "/api/where/stops-for-location.json" }

    /// Creates a full URL for the `getStops` API call, including query params.
    ///
    /// - API Endpoint: `/api/where/stops-for-location.json`
    ///
    /// - Parameters:
    ///   - coordinate: The coordinate around which to search for stops.
    /// - Returns: An URL suitable for making a request to retrieve information.
    public func getStops(coordinate: CLLocationCoordinate2D) -> URL {
        generateURL(path: getStopsAPIPath, params: [
            "lat": coordinate.latitude,
            "lon": coordinate.longitude
        ])
    }

    /// Creates a full URL for the `getStops` API call, including query params.
    ///
    /// - API Endpoint: `/api/where/stops-for-location.json`
    ///
    /// - Parameter region: The coordinate region for which the API call will be generated.
    /// - Returns: An URL suitable for making a request to retrieve information.
    public func getStops(region: MKCoordinateRegion) -> URL {
        generateURL(path: getStopsAPIPath, params: [
            "lat": region.center.latitude,
            "lon": region.center.longitude,
            "latSpan": region.span.latitudeDelta,
            "lonSpan": region.span.longitudeDelta
        ])
    }

    /// Creates a full URL for the `getStops` API call, including query params.
    ///
    /// - API Endpoint: `/api/where/stops-for-location.json`
    ///
    /// - Parameters:
    ///   - circularRegion: A circular region  for which the API call will be generated.
    ///   - query: A search query.
    /// - Returns: An URL suitable for making a request to retrieve information.
    public func getStops(circularRegion: CLCircularRegion, query: String) -> URL {
        generateURL(path: getStopsAPIPath, params: [
            "lat": circularRegion.center.latitude,
            "lon": circularRegion.center.longitude,
            "query": query,
            // make sure radius is greater than zero and less than 15,000
            "radius": Int(max(min(15000.0, circularRegion.radius), 1.0))
        ])
    }

    /// Creates a full URL for the `getStop` API call, including query params.
    ///
    /// - API Endpoint: `/api/where/stop/{id}.json`
    ///
    /// - Parameters:
    ///   - id: The full, agency-prefixed ID of the stop.
    /// - Returns: An URL suitable for making a request to retrieve information.
    public func getStop(stopID: StopID) -> URL {
        generateURL(path: String(
            format: "/api/where/stop/%@.json",
            NetworkHelpers.escapePathVariable(stopID)
        ))
    }

    /// Creates a full URL for the `getArrivalsAndDeparturesForStop` API call, including query params.
    ///
    /// - API Endpoint: `/api/where/arrivals-and-departures-for-stop/{id}.json`
    ///
    /// - Parameters:
    ///   - id: The stop ID
    ///   - minutesBefore: How many minutes before now should Arrivals and Departures be returned for
    ///   - minutesAfter: How many minutes after now should Arrivals and Departures be returned for
    /// - Returns: An URL suitable for making a request to retrieve information.
    public func getArrivalsAndDeparturesForStop(id: StopID, minutesBefore: UInt, minutesAfter: UInt) -> URL {
        generateURL(
            path: String(format: "/api/where/arrivals-and-departures-for-stop/%@.json",
                         NetworkHelpers.escapePathVariable(id)),
            params: [
                "minutesBefore": minutesBefore,
                "minutesAfter": minutesAfter
        ])
    }

    /// Creates a full URL for the `getTripArrivalDepartureAtStop` API call, including query params.
    ///
    /// - API Endpoint: `/api/where/arrival-and-departure-for-stop/{id}.json`
    ///
    /// - Parameters:
    ///   - stopID: The ID of the stop.
    ///   - tripID: The trip id of the arriving transit vehicle.
    ///   - serviceDate: The service date of the arriving transit vehicle.
    ///   - vehicleID: The vehicle id of the arriving transit vehicle (optional).
    ///   - stopSequence: the stop sequence index of the stop in the transit vehicle’s trip.
    /// - Returns: An URL suitable for making a request to retrieve information.
    public func getTripArrivalDepartureAtStop(stopID: StopID, tripID: String, serviceDate: Date, vehicleID: String?, stopSequence: Int) -> URL {
        var args: [String: Any] = [
            "serviceDate": Int64(serviceDate.timeIntervalSince1970 * 1000),
            "tripId": tripID
        ]

        if let vehicleID = vehicleID {
            args["vehicleId"] = vehicleID
        }

        if stopSequence > 0 {
            args["stopSequence"] = stopSequence
        }

        return generateURL(path: String(format: "/api/where/arrival-and-departure-for-stop/%@.json", NetworkHelpers.escapePathVariable(stopID)), params: args)
    }

    /// Creates a full URL for the `getTrip` API call, including query params.
    ///
    /// - API Endpoint: `/api/where/trip-details/{id}.json`
    ///
    /// - Parameters:
    ///   - tripID: The ID of the trip.
    ///   - vehicleID: Optional ID for the specific transit vehicle on this trip.
    ///   - serviceDate: The service date for this trip.
    /// - Returns: An URL suitable for making a request to retrieve information.
    public func getTrip(tripID: String, vehicleID: String?, serviceDate: Date?) -> URL {
        var args: [String: Any] = [:]
        if let serviceDate = serviceDate {
            args["serviceDate"] = Int64(serviceDate.timeIntervalSince1970 * 1000)
        }

        if let vehicleID = vehicleID {
            args["vehicleId"] = vehicleID
        }

        return generateURL(
            path: String(format: "/api/where/trip-details/%@.json", NetworkHelpers.escapePathVariable(tripID)),
            params: args
        )
    }

    /// Creates a full URL for the `getStopsForRoute` API call, including query params.
    ///
    /// - API Endpoint: `/api/where/stops-for-route/{id}.json`
    ///
    /// - Parameters:
    ///   - id: The route ID.
    /// - Returns: An URL suitable for making a request to retrieve information.
    public func getStopsForRoute(id: RouteID) -> URL {
        generateURL(path: String(
            format: "/api/where/stops-for-route/%@.json",
            NetworkHelpers.escapePathVariable(id)
        ))
    }

    /// Creates a full URL for the `getRoute` API call, including query params.
    ///
    /// - API Endpoint: `/api/where/routes-for-location.json`
    ///
    /// - Parameters:
    ///   - query: Search query
    ///   - region: The circular region from which to return results.
    /// - Returns: An URL suitable for making a request to retrieve information.
    public func getRoute(query: String, region: CLCircularRegion) -> URL {
        generateURL(
            path: "/api/where/routes-for-location.json",
            params: [
                "lat": region.center.latitude,
                "lon": region.center.longitude,
                "query": query,
                "radius": String(max(region.radius, maxRegionalRadius))
        ])
    }

    /*
     See https://github.com/OneBusAway/onebusaway-iphone/issues/601
     for more information on this. In short, the issue is that
     the route disambiguation UI should always appears when there are
     multiple routes whose names contain the same search string, but
     sometimes this doesn't happen. It's a result of routes-for-location
     searches not having a wide enough radius.
     */
    private var maxRegionalRadius: CLLocationDistance { 40000.0 }

    /// Creates a full URL for the `getShape` API call, including query params.
    ///
    /// - API Endpoint: `/api/where/shape/{id}.json`
    ///
    /// - Parameters:
    ///   - id: The ID of the shape to retrieve.
    /// - Returns: An URL suitable for making a request to retrieve information.
    public func getShape(id: String) -> URL {
        generateURL(path: String(
            format: "/api/where/shape/%@.json",
            NetworkHelpers.escapePathVariable(id)
        ))
    }

    /// Creates a full URL for the `getShape` API call, including query params.
    ///
    /// - API Endpoint: `/api/where/agencies-with-coverage.json`
    ///
    /// - Returns: An URL suitable for making a request to retrieve information.
    public func getAgenciesWithCoverage() -> URL {
        generateURL(path: "/api/where/agencies-with-coverage.json")
    }

    public enum RegionalAlertsSource: String {
        case obaco = "/api/v1/regions/%@/alerts.pb"
        case rest = "/api/gtfs_realtime/alerts-for-agency/%@.pb"
    }

    /// Creates a full URL for the `getRegionalAlerts` REST API.
    ///
    /// - API Endpoint : `/api/gtfs_realtime/alerts-for-agency/{ID}.pb`
    ///
    /// - Parameters:
    ///   - agencyID: The ID of the agency for which alerts will be requested.
    /// - Returns: An URL suitable for making a request to retrieve information.
    public func getRESTRegionalAlerts(agencyID: String) -> URL {
        generateURL(path: String(
            format: "/api/gtfs_realtime/alerts-for-agency/%@.pb",
            NetworkHelpers.escapePathVariable(agencyID)
        ))
    }

    public func getStopProblem(
        stopID: StopID,
        code: StopProblemCode,
        comment: String?,
        location: CLLocation?
    ) -> URL {
        var args: [String: Any] = [
            "code": code.APIStringValue
        ]

        if let comment = comment {
            args["userComment"] = comment
        }

        if let location = location {
            args["userLat"] = location.coordinate.latitude
            args["userLon"] = location.coordinate.longitude
            args["userLocationAccuracy"] = location.horizontalAccuracy
        }

        return generateURL(path: "/api/where/report-problem-with-stop/\(stopID).json", params: args)
    }

    public func getTripProblem(
        tripID: String,
        serviceDate: Date,
        vehicleID: String?,
        stopID: StopID?,
        code: TripProblemCode,
        comment: String?,
        userOnVehicle: Bool,
        location: CLLocation?
    ) -> URL {
        let apiPath = "/api/where/report-problem-with-trip.json"
        var args: [String: Any] = [
            "tripId": tripID,
            "serviceDate": Int64(serviceDate.timeIntervalSince1970 * 1000),
            "code": code.APIStringValue,
            "userOnVehicle": userOnVehicle ? "true" : "false"
        ]

        if let vehicleID = vehicleID {
            args["vehicleId"] = vehicleID
        }

        if let stopID = stopID {
            args["stopId"] = stopID
        }

        if let comment = comment {
            args["userComment"] = comment
        }

        if let location = location {
            args["userLat"] = location.coordinate.latitude
            args["userLon"] = location.coordinate.longitude
            args["userLocationAccuracy"] = location.horizontalAccuracy
        }

        return generateURL(path: apiPath, params: args)
    }

    // MARK: - Survey API URL Builders

    /// Creates a full URL for the `getSurveys` API call, including query params.
    ///
    /// - API Endpoint: `/api/v1/regions/{region_id}/surveys.json`
    ///
    /// - Parameter userID: The user's unique identifier
    /// - Parameter regionID: The region identifier
    /// - Returns: An URL suitable for making a request to retrieve surveys.
    public func getSurveys(userID: String, regionID: Int) -> URL? {
        guard let surveyBaseURL = surveyBaseURL else { return nil }

        let builder = RESTAPIURLBuilder(baseURL: surveyBaseURL, defaultQueryItems: defaultQueryItems)
        return builder.generateURL(
            path: "/api/v1/regions/\(regionID)/surveys.json",
            params: ["user_id": userID]
        )
    }

    /// Creates a full URL for the `submitSurveyResponse` API call.
    ///
    /// - API Endpoint: `/api/v1/survey_responses/`
    ///
    /// - Returns: An URL suitable for making a POST request to submit survey responses.
    public func submitSurveyResponse() -> URL? {
        guard let surveyBaseURL = surveyBaseURL else { return nil }

        let builder = RESTAPIURLBuilder(baseURL: surveyBaseURL, defaultQueryItems: defaultQueryItems)
        return builder.generateURL(path: "/api/v1/survey_responses/")
    }

    /// Creates a full URL for the `updateSurveyResponse` API call.
    ///
    /// - API Endpoint: `/api/v1/survey_responses/{response_id}`
    ///
    /// - Parameter responseID: The ID of the existing survey response
    /// - Returns: An URL suitable for making a PUT request to update survey responses.
    public func updateSurveyResponse(responseID: String) -> URL? {
        guard let surveyBaseURL = surveyBaseURL else { return nil }

        let builder = RESTAPIURLBuilder(baseURL: surveyBaseURL, defaultQueryItems: defaultQueryItems)
        return builder.generateURL(path: "/api/v1/survey_responses/\(NetworkHelpers.escapePathVariable(responseID))")
    }
}
