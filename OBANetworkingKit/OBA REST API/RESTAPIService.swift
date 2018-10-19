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
    public func getVehicle(_ vehicleID: String, completion: RESTAPICompletionBlock? = nil) -> RequestVehicleOperation {
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
    public func getVehicleTrip(vehicleID: String, completion: RESTAPICompletionBlock? = nil) -> VehicleTripOperation {
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
    public func getCurrentTime(completion: RESTAPICompletionBlock? = nil) -> CurrentTimeOperation {
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
    public func getStops(coordinate: CLLocationCoordinate2D, completion: RESTAPICompletionBlock? = nil) -> StopsOperation {
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
    public func getStops(region: MKCoordinateRegion, completion: RESTAPICompletionBlock? = nil) -> StopsOperation {
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
    public func getStops(circularRegion: CLCircularRegion, query: String, completion: RESTAPICompletionBlock? = nil) -> StopsOperation {
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
    public func getArrivalsAndDeparturesForStop(id: String, minutesBefore: UInt, minutesAfter: UInt, completion: RESTAPICompletionBlock? = nil) -> StopArrivalsAndDeparturesOperation {
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
    public func getTripArrivalDepartureForStop(stopID: String, tripID: String, serviceDate: Int64, vehicleID: String?, stopSequence: Int, completion: RESTAPICompletionBlock? = nil) -> ArrivalDepartureForStopOperation {
        let url = ArrivalDepartureForStopOperation.buildURL(stopID: stopID, tripID: tripID, serviceDate: serviceDate, vehicleID: vehicleID, stopSequence: stopSequence, baseURL: baseURL, defaultQueryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: ArrivalDepartureForStopOperation.self, url: url, completionBlock: completion)
    }

    // MARK: - Trip Details

    /// Get extended details for a specific trip.
    ///
    /// - API Endpoint: `/api/where/trip-details/{id}.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/trip-details.html)
    ///
    /// - Parameters:
    ///   - tripID: The ID of the trip.
    ///   - vehicleID: Optional ID for the specific transit vehicle on this trip.
    ///   - serviceDate: The service date for this trip.
    ///   - completion: An optional completion block.
    /// - Returns: The enqueued network operation.
    @objc @discardableResult
    public func getTrip(tripID: String, vehicleID: String?, serviceDate: Int64, completion: RESTAPICompletionBlock? = nil) -> TripDetailsOperation {
        let url = TripDetailsOperation.buildURL(tripID: tripID, vehicleID: vehicleID, serviceDate: serviceDate, baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: TripDetailsOperation.self, url: url, completionBlock: completion)
    }

    // MARK: - Search

    /// Retrieve the set of stops serving a particular route, including groups by direction of travel.
    ///
    /// The `stops-for-route` method first and foremost provides a method for retrieving the set of stops
    /// that serve a particular route. In addition to the full set of stops, we provide various
    /// "stop groupings" that are used to group the stops into useful collections. Currently, the main
    /// grouping provided organizes the set of stops by direction of travel for the route. Finally,
    /// this method also returns a set of polylines that can be used to draw the path traveled by the route.
    ///
    /// - API Endpoint: `/api/where/stops-for-route/{id}.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/stops-for-route.html)
    ///
    /// - Parameters:
    ///   - id: The route ID.
    ///   - completion: An optional completion block.
    /// - Returns: The enqueued network operation.
    @discardableResult @objc
    public func getStopsForRoute(id: String, completion: RESTAPICompletionBlock? = nil) -> StopsForRouteOperation {
        let url = StopsForRouteOperation.buildURL(routeID: id, baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: StopsForRouteOperation.self, url: url, completionBlock: completion)
    }

    /// Search for routes within a region, by name
    ///
    /// - API Endpoint: `/api/where/routes-for-location.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/routes-for-location.html)
    ///
    /// - Parameters:
    ///   - query: Search query
    ///   - region: The circular region from which to return results.
    ///   - completion: An optional completion block.
    /// - Returns: The enqueued network operation.
    @discardableResult @objc
    public func getRoute(query: String, region: CLCircularRegion, completion: RESTAPICompletionBlock? = nil) -> RouteSearchOperation {
        let url = RouteSearchOperation.buildURL(searchQuery: query, region: region, baseURL: baseURL, defaultQueryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: RouteSearchOperation.self, url: url, completionBlock: completion)
    }

    /// Performs a local search and returns matching results
    ///
    /// - Parameters:
    ///   - query: The term for which to search.
    ///   - region: The coordinate region in which to search.
    ///   - completion: An optional completion block.
    /// - Returns: The enqueued network operation.
    @discardableResult @objc
    public func getPlacemarks(query: String, region: MKCoordinateRegion, completion: PlacemarkSearchCompletionBlock? = nil) -> PlacemarkSearchOperation {
        let operation = PlacemarkSearchOperation(query: query, region: region)
        operation.completionBlock = { [weak operation] in
            if let operation = operation { completion?(operation) }
        }
        networkQueue.add(operation)

        return operation
    }

    // MARK: - Shapes

    @discardableResult @objc
    public func getShape(id: String, completion: RESTAPICompletionBlock? = nil) -> ShapeOperation {
        let url = ShapeOperation.buildURL(shapeID: id, baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: ShapeOperation.self, url: url, completionBlock: completion)
    }

    // MARK: - Agencies

    @discardableResult @objc
    public func getAgenciesWithCoverage(completion: RESTAPICompletionBlock? = nil) -> AgenciesWithCoverageOperation {
        let url = AgenciesWithCoverageOperation.buildURL(baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: AgenciesWithCoverageOperation.self, url: url, completionBlock: completion)
    }

    // MARK: - Regional Alerts

    @discardableResult @objc
    public func getRegionalAlerts(agencyID: String, completion: RegionalAlertsCompletionBlock? = nil) -> RegionalAlertsOperation {
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
    public func getStopProblem(stopID: String, code: StopProblemCode, comment: String, location: CLLocation?, completion: RESTAPICompletionBlock? = nil) -> StopProblemOperation {
        let url = StopProblemOperation.buildURL(stopID: stopID, code: code, comment: comment, location: location, baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: StopProblemOperation.self, url: url, completionBlock: completion)
    }

    @discardableResult @objc
    public func getTripProblem(tripID: String, serviceDate: Int64, vehicleID: String?, stopID: String?, code: TripProblemCode, comment: String?, userOnVehicle: Bool, location: CLLocation?, completion: RESTAPICompletionBlock? = nil) -> TripProblemOperation {
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
