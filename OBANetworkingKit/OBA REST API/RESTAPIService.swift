//
//  RESTAPIService.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation
import MapKit

public typealias NetworkCompletionBlock = (_ operation: RESTAPIOperation) -> Void
public typealias PlacemarkSearchCompletionBlock = (_ operation: PlacemarkSearchOperation) -> Void
public typealias RegionalAlertsCompletionBlock = (_ operation: RegionalAlertsOperation) -> Void

@objc(OBARESTAPIService)
public class RESTAPIService: NSObject {
    private let baseURL: URL
    private let networkQueue: NetworkQueue
    internal let defaultQueryItems: [URLQueryItem]

    @objc public init(baseURL: URL, apiKey: String, uuid: String, appVersion: String, networkQueue: NetworkQueue) {
        self.baseURL = baseURL

        var queryItems = [URLQueryItem]()
        queryItems.append(URLQueryItem(name: "key", value: apiKey))
        queryItems.append(URLQueryItem(name: "app_uid", value: uuid))
        queryItems.append(URLQueryItem(name: "app_ver", value: appVersion))
        queryItems.append(URLQueryItem(name: "version", value: "2"))
        self.defaultQueryItems = queryItems

        self.networkQueue = networkQueue
    }

    @objc public convenience init(baseURL: URL, apiKey: String, uuid: String, appVersion: String) {
        self.init(baseURL: baseURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, networkQueue: NetworkQueue())
    }

    // MARK: - Vehicle with ID

    /// Provides information on the vehicle with the specified ID.
    ///
    /// - Important: Vehicle IDs are seldom not identical to the IDs that
    /// are physically printed on buses. For example, in Puget Sound, a
    /// KC Metro bus that has the number `1234` printed on its side will
    /// likely have the vehicle ID `1_1234` to ensure that the vehicle ID
    /// is unique across the Puget Sound region with all of its agencies.
    ///
    /// - Parameters:
    ///   - vehicleID: Vehicle ID string
    ///   - completion: An optional completion block
    /// - Returns: The enqueued network operation.
    @discardableResult @objc
    public func getVehicle(_ vehicleID: String, completion: NetworkCompletionBlock?) -> RequestVehicleOperation {
        let url = RequestVehicleOperation.buildURL(vehicleID: vehicleID, baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: RequestVehicleOperation.self, url: url, completionBlock: completion)
    }

    // MARK: - Current Time

    /// Retrieves the current system time of the OneBusAway server.
    ///
    /// - Parameter completion: An optional completion block
    /// - Returns: The enqueued network operation.
    @discardableResult @objc
    public func getCurrentTime(completion: NetworkCompletionBlock?) -> CurrentTimeOperation {
        let url = CurrentTimeOperation.buildURL(baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: CurrentTimeOperation.self, url: url, completionBlock: completion)
    }

    // MARK: - Stops

    @discardableResult @objc
    public func getStops(coordinate: CLLocationCoordinate2D, completion: NetworkCompletionBlock?) -> StopsOperation {
        let url = StopsOperation.buildURL(coordinate: coordinate, baseURL: baseURL, defaultQueryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: StopsOperation.self, url: url, completionBlock: completion)
    }

    @discardableResult @objc
    public func getStops(region: MKCoordinateRegion, completion: NetworkCompletionBlock?) -> StopsOperation {
        let url = StopsOperation.buildURL(region: region, baseURL: baseURL, defaultQueryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: StopsOperation.self, url: url, completionBlock: completion)
    }

    @discardableResult @objc
    public func getStops(circularRegion: CLCircularRegion, query: String, completion: NetworkCompletionBlock?) -> StopsOperation {
        let url = StopsOperation.buildURL(circularRegion: circularRegion, query: query, baseURL: baseURL, defaultQueryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: StopsOperation.self, url: url, completionBlock: completion)
    }

    // MARK: - Arrivals and Departures for Stop

    @discardableResult @objc
    public func getArrivalsAndDeparturesForStop(id: String, minutesBefore: UInt, minutesAfter: UInt, completion: NetworkCompletionBlock?) -> StopArrivalsAndDeparturesOperation {
        let url = StopArrivalsAndDeparturesOperation.buildURL(stopID: id, minutesBefore: minutesBefore, minutesAfter: minutesAfter, baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: StopArrivalsAndDeparturesOperation.self, url: url, completionBlock: completion)
    }

    // MARK: - Arrival and Departure for Stop

    @discardableResult @objc
    public func getTripArrivalDepartureForStop(stopID: String, tripID: String, serviceDate: Int64, vehicleID: String?, stopSequence: Int, completion: NetworkCompletionBlock?) -> ArrivalDepartureForStopOperation {
        let url = ArrivalDepartureForStopOperation.buildURL(stopID: stopID, tripID: tripID, serviceDate: serviceDate, vehicleID: vehicleID, stopSequence: stopSequence, baseURL: baseURL, defaultQueryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: ArrivalDepartureForStopOperation.self, url: url, completionBlock: completion)
    }

    // MARK: - Trip Details

    @objc @discardableResult
    public func getTrip(tripID: String, vehicleID: String?, serviceDate: Int64, completion: NetworkCompletionBlock?) -> TripDetailsOperation {
        let url = TripDetailsOperation.buildURL(tripID: tripID, vehicleID: vehicleID, serviceDate: serviceDate, baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: TripDetailsOperation.self, url: url, completionBlock: completion)
    }

    // MARK: - Search

    @discardableResult @objc
    public func getStopsForRoute(id: String, completion: NetworkCompletionBlock?) -> StopsForRouteOperation {
        let url = StopsForRouteOperation.buildURL(routeID: id, baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: StopsForRouteOperation.self, url: url, completionBlock: completion)
    }

    @discardableResult @objc
    public func getRoute(query: String, region: CLCircularRegion, completion: NetworkCompletionBlock?) -> RouteSearchOperation {
        let url = RouteSearchOperation.buildURL(searchQuery: query, region: region, baseURL: baseURL, defaultQueryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: RouteSearchOperation.self, url: url, completionBlock: completion)
    }

    @discardableResult @objc
    public func getPlacemarks(query: String, region: MKCoordinateRegion, completion: PlacemarkSearchCompletionBlock?) -> PlacemarkSearchOperation {
        let operation = PlacemarkSearchOperation(query: query, region: region)
        operation.completionBlock = { [weak operation] in
            if let operation = operation { completion?(operation) }
        }
        networkQueue.add(operation)

        return operation
    }

    // MARK: - Shapes

    @discardableResult @objc
    public func getShape(id: String, completion: NetworkCompletionBlock?) -> ShapeOperation {
        let url = ShapeOperation.buildURL(shapeID: id, baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: ShapeOperation.self, url: url, completionBlock: completion)
    }

    // MARK: - Agencies

    @discardableResult @objc
    public func getAgenciesWithCoverage(completion: NetworkCompletionBlock?) -> AgenciesWithCoverageOperation {
        let url = AgenciesWithCoverageOperation.buildURL(baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: AgenciesWithCoverageOperation.self, url: url, completionBlock: completion)
    }

    // MARK: - Regional Alerts

    @discardableResult @objc
    public func getRegionalAlerts(agencyID: String, completion: RegionalAlertsCompletionBlock?) -> RegionalAlertsOperation {
        let url = RegionalAlertsOperation.buildURL(agencyID: agencyID, baseURL: baseURL, queryItems: defaultQueryItems)
        let operation = RegionalAlertsOperation(url: url)
        operation.completionBlock = { [weak operation] in
            if let operation = operation { completion?(operation) }
        }
        networkQueue.add(operation)
        return operation
    }

    // MARK: - Problem Reporting

    @discardableResult @objc
    public func getStopProblem(stopID: String, code: StopProblemCode, comment: String, location: CLLocation?, completion: NetworkCompletionBlock?) -> StopProblemOperation {
        let url = StopProblemOperation.buildURL(stopID: stopID, code: code, comment: comment, location: location, baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: StopProblemOperation.self, url: url, completionBlock: completion)
    }

    @discardableResult @objc
    public func getTripProblem(tripID: String, serviceDate: Int64, vehicleID: String?, stopID: String?, code: TripProblemCode, comment: String?, userOnVehicle: Bool, location: CLLocation?, completion: NetworkCompletionBlock?) -> TripProblemOperation {
        let url = TripProblemOperation.buildURL(tripID: tripID, serviceDate: serviceDate, vehicleID: vehicleID, stopID: stopID, code: code, comment: comment, userOnVehicle: userOnVehicle, location: location, baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: TripProblemOperation.self, url: url, completionBlock: completion)
    }

    // MARK: - Private Internal Helpers

    private func buildAndEnqueueOperation<T>(type: T.Type, url: URL, completionBlock: NetworkCompletionBlock?) -> T where T: RESTAPIOperation {
        let operation = type.init(url: url)
        operation.completionBlock = { [weak operation] in
            if let operation = operation { completionBlock?(operation) }
        }

        networkQueue.add(operation)

        return operation
    }
}
