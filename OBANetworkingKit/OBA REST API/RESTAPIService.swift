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

public typealias RESTAPICompletionBlock = (_ operation: RESTAPIOperation) -> Void
public typealias PlacemarkSearchCompletionBlock = (_ operation: PlacemarkSearchOperation) -> Void
public typealias RegionalAlertsCompletionBlock = (_ operation: RegionalAlertsOperation) -> Void

@objc(OBARESTAPIService)
public class RESTAPIService: APIService {

    // MARK: - Vehicle with ID

    /// Provides information on the vehicle with the specified ID.
    ///
    /// API Endpoint: `/api/where/vehicle/{id}.json`
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
    public func getVehicle(_ vehicleID: String, completion: RESTAPICompletionBlock?) -> RequestVehicleOperation {
        let url = RequestVehicleOperation.buildURL(vehicleID: vehicleID, baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: RequestVehicleOperation.self, url: url, completionBlock: completion)
    }

    /// Get extended trip details for a specific transit vehicle. That is, given a vehicle id for a transit vehicle currently operating in the field, return extended trip details about the current trip for the vehicle.
    ///
    /// - API Endpoint: `/api/where/trip-for-vehicle/{id}.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/trip-for-vehicle.html)
    ///
    /// - Important: Vehicle IDs are seldom not identical to the IDs that
    /// are physically printed on buses. For example, in Puget Sound, a
    /// KC Metro bus that has the number `1234` printed on its side will
    /// likely have the vehicle ID `1_1234` to ensure that the vehicle ID
    /// is unique across the Puget Sound region with all of its agencies.
    ///
    /// - Parameters:
    ///   - vehicleID: The ID of the vehicle
    ///   - completion: An optional completion block
    /// - Returns: The enqueued network operation.
    @discardableResult @objc
    public func getVehicleTrip(vehicleID: String, completion: RESTAPICompletionBlock?) -> VehicleTripOperation {
        let url = VehicleTripOperation.buildURL(vehicleID: vehicleID, baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: VehicleTripOperation.self, url: url, completionBlock: completion)
    }

    // MARK: - Current Time

    /// Retrieves the current system time of the OneBusAway server.
    ///
    /// - API Endpoint: `/api/where/current-time.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/current-time.html)
    ///
    /// - Parameter completion: An optional completion block
    /// - Returns: The enqueued network operation.
    @discardableResult @objc
    public func getCurrentTime(completion: RESTAPICompletionBlock?) -> CurrentTimeOperation {
        let url = CurrentTimeOperation.buildURL(baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: CurrentTimeOperation.self, url: url, completionBlock: completion)
    }

    // MARK: - Stops

    /// Retrieves stops in the vicinity of `coordinate`.
    ///
    /// - API Endpoint: `/api/where/stops-for-location.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/stops-for-location.html)
    ///
    /// - Parameters:
    ///   - coordinate: The coordinate around which to search for stops.
    ///   - completion: An optional completion block.
    /// - Returns: The enqueued network operation.
    @discardableResult @objc
    public func getStops(coordinate: CLLocationCoordinate2D, completion: RESTAPICompletionBlock?) -> StopsOperation {
        let url = StopsOperation.buildURL(coordinate: coordinate, baseURL: baseURL, defaultQueryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: StopsOperation.self, url: url, completionBlock: completion)
    }

    /// Retrieves stops within `region`.
    ///
    /// - API Endpoint: `/api/where/stops-for-location.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/stops-for-location.html)
    ///
    /// - Important: Depending on the number of stops located within `region`, you may only receive back
    /// a subset of the total list of stops within `region`. Zoom in (i.e. provide a smaller region) to
    /// better guarantee that you will receive a full list.
    ///
    /// - Parameters:
    ///   - region: A coordinate region from which to search for stops.
    ///   - completion: An optional completion block.
    /// - Returns: The enqueued network operation.
    @discardableResult @objc
    public func getStops(region: MKCoordinateRegion, completion: RESTAPICompletionBlock?) -> StopsOperation {
        let url = StopsOperation.buildURL(region: region, baseURL: baseURL, defaultQueryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: StopsOperation.self, url: url, completionBlock: completion)
    }

    /// Retrieves stops within `circularRegion`.
    ///
    /// - API Endpoint: `/api/where/stops-for-location.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/stops-for-location.html)
    ///
    /// - Important: Depending on the number of stops located within `circularRegion`, you may only receive back
    /// a subset of the total list of stops within `circularRegion`. Zoom in (i.e. provide a smaller region) to
    /// better guarantee that you will receive a full list.
    ///
    /// - Parameters:
    ///   - circularRegion: A circular region from which to search for stops.
    ///   - query: A search query for a specific stop code.
    ///   - completion: An optional completion block.
    /// - Returns: The enqueued network operation.
    @discardableResult @objc
    public func getStops(circularRegion: CLCircularRegion, query: String, completion: RESTAPICompletionBlock?) -> StopsOperation {
        let url = StopsOperation.buildURL(circularRegion: circularRegion, query: query, baseURL: baseURL, defaultQueryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: StopsOperation.self, url: url, completionBlock: completion)
    }

    // MARK: - Arrivals and Departures for Stop

    /// Retrieves a list of vehicle arrivals and departures for the specified stop for the time frame of
    /// `minutesBefore` to `minutesAfter`.
    ///
    /// - Parameters:
    ///   - id: The stop ID
    ///   - minutesBefore: How many minutes before now should Arrivals and Departures be returned for
    ///   - minutesAfter: How many minutes after now should Arrivals and Departures be returned for
    ///   - completion: An optional completion block.
    /// - Returns: The enqueued network operation.
    @discardableResult @objc
    public func getArrivalsAndDeparturesForStop(id: String, minutesBefore: UInt, minutesAfter: UInt, completion: RESTAPICompletionBlock?) -> StopArrivalsAndDeparturesOperation {
        let url = StopArrivalsAndDeparturesOperation.buildURL(stopID: id, minutesBefore: minutesBefore, minutesAfter: minutesAfter, baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: StopArrivalsAndDeparturesOperation.self, url: url, completionBlock: completion)
    }

    // MARK: - Arrival and Departure for Stop

    /// Get info about a single arrival and departure for a stop
    ///
    /// - API Endpoint: `/api/where/arrival-and-departure-for-stop/{id}.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/arrival-and-departure-for-stop.html)
    ///
    /// - Parameters:
    ///   - stopID: The ID of the stop.
    ///   - tripID: The trip id of the arriving transit vehicle.
    ///   - serviceDate: The service date of the arriving transit vehicle.
    ///   - vehicleID: The vehicle id of the arriving transit vehicle (optional).
    ///   - stopSequence: the stop sequence index of the stop in the transit vehicle’s trip.
    ///   - completion: An optional completion block.
    /// - Returns: The enqueued network operation.
    @discardableResult @objc
    public func getTripArrivalDepartureForStop(stopID: String, tripID: String, serviceDate: Int64, vehicleID: String?, stopSequence: Int, completion: RESTAPICompletionBlock?) -> ArrivalDepartureForStopOperation {
        let url = ArrivalDepartureForStopOperation.buildURL(stopID: stopID, tripID: tripID, serviceDate: serviceDate, vehicleID: vehicleID, stopSequence: stopSequence, baseURL: baseURL, defaultQueryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: ArrivalDepartureForStopOperation.self, url: url, completionBlock: completion)
    }

    // MARK: - Trip Details

    @objc @discardableResult
    public func getTrip(tripID: String, vehicleID: String?, serviceDate: Int64, completion: RESTAPICompletionBlock?) -> TripDetailsOperation {
        let url = TripDetailsOperation.buildURL(tripID: tripID, vehicleID: vehicleID, serviceDate: serviceDate, baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: TripDetailsOperation.self, url: url, completionBlock: completion)
    }

    // MARK: - Search

    @discardableResult @objc
    public func getStopsForRoute(id: String, completion: RESTAPICompletionBlock?) -> StopsForRouteOperation {
        let url = StopsForRouteOperation.buildURL(routeID: id, baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: StopsForRouteOperation.self, url: url, completionBlock: completion)
    }

    @discardableResult @objc
    public func getRoute(query: String, region: CLCircularRegion, completion: RESTAPICompletionBlock?) -> RouteSearchOperation {
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
    public func getShape(id: String, completion: RESTAPICompletionBlock?) -> ShapeOperation {
        let url = ShapeOperation.buildURL(shapeID: id, baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: ShapeOperation.self, url: url, completionBlock: completion)
    }

    // MARK: - Agencies

    @discardableResult @objc
    public func getAgenciesWithCoverage(completion: RESTAPICompletionBlock?) -> AgenciesWithCoverageOperation {
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
    public func getStopProblem(stopID: String, code: StopProblemCode, comment: String, location: CLLocation?, completion: RESTAPICompletionBlock?) -> StopProblemOperation {
        let url = StopProblemOperation.buildURL(stopID: stopID, code: code, comment: comment, location: location, baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: StopProblemOperation.self, url: url, completionBlock: completion)
    }

    @discardableResult @objc
    public func getTripProblem(tripID: String, serviceDate: Int64, vehicleID: String?, stopID: String?, code: TripProblemCode, comment: String?, userOnVehicle: Bool, location: CLLocation?, completion: RESTAPICompletionBlock?) -> TripProblemOperation {
        let url = TripProblemOperation.buildURL(tripID: tripID, serviceDate: serviceDate, vehicleID: vehicleID, stopID: stopID, code: code, comment: comment, userOnVehicle: userOnVehicle, location: location, baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: TripProblemOperation.self, url: url, completionBlock: completion)
    }

    // MARK: - Private Internal Helpers

    private func buildAndEnqueueOperation<T>(type: T.Type, url: URL, completionBlock: RESTAPICompletionBlock?) -> T where T: RESTAPIOperation {
        let operation = type.init(url: url)
        operation.completionBlock = { [weak operation] in
            if let operation = operation { completionBlock?(operation) }
        }

        networkQueue.add(operation)

        return operation
    }
}
