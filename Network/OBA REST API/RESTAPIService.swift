//
//  RESTAPIService.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation
import MapKit

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
    /// - Returns: The enqueued network operation.
    public func getVehicle(_ vehicleID: String) -> RequestVehicleOperation {
        let url = RequestVehicleOperation.buildURL(vehicleID: vehicleID, baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: RequestVehicleOperation.self, url: url)
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
    /// - Returns: The enqueued network operation.
    public func getVehicleTrip(vehicleID: String) -> VehicleTripOperation {
        let url = VehicleTripOperation.buildURL(vehicleID: vehicleID, baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: VehicleTripOperation.self, url: url)
    }

    // MARK: - Current Time

    /// Retrieves the current system time of the OneBusAway server.
    ///
    /// - API Endpoint: `/api/where/current-time.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/current-time.html)
    ///
    /// - Returns: The enqueued network operation.
    public func getCurrentTime() -> CurrentTimeOperation {
        let url = CurrentTimeOperation.buildURL(baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: CurrentTimeOperation.self, url: url)
    }

    // MARK: - Stops

    /// Retrieves stops in the vicinity of `coordinate`.
    ///
    /// - API Endpoint: `/api/where/stops-for-location.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/stops-for-location.html)
    ///
    /// - Parameters:
    ///   - coordinate: The coordinate around which to search for stops.
    /// - Returns: The enqueued network operation.
    public func getStops(coordinate: CLLocationCoordinate2D) -> StopsOperation {
        let url = StopsOperation.buildURL(coordinate: coordinate, baseURL: baseURL, defaultQueryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: StopsOperation.self, url: url)
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

    /// - Returns: The enqueued network operation.
    public func getStops(region: MKCoordinateRegion) -> StopsOperation {
        let url = StopsOperation.buildURL(region: region, baseURL: baseURL, defaultQueryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: StopsOperation.self, url: url)
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
    /// - Returns: The enqueued network operation.
    public func getStops(circularRegion: CLCircularRegion, query: String) -> StopsOperation {
        let url = StopsOperation.buildURL(circularRegion: circularRegion, query: query, baseURL: baseURL, defaultQueryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: StopsOperation.self, url: url)
    }

    /// Retrieves the stop with the specified ID.
    ///
    /// - API Endpoint: `/api/where/stop/{id}.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/stop.html)
    ///
    /// - Parameters:
    ///   - id: The full, agency-prefixed ID of the stop.
    /// - Returns: The enqueued network operation.
    public func getStop(id: String) -> StopOperation {
        let url = StopOperation.buildURL(stopID: id, baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: StopOperation.self, url: url)
    }

    // MARK: - Arrivals and Departures for Stop

    /// Retrieves a list of vehicle arrivals and departures for the specified stop for the time frame of
    /// `minutesBefore` to `minutesAfter`.
    ///
    /// - API Endpoint: `/api/where/arrivals-and-departures-for-stop/{id}.json`
    /// - [View REST API Documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/arrivals-and-departures-for-stop.html)
    ///
    /// - Parameters:
    ///   - id: The stop ID
    ///   - minutesBefore: How many minutes before now should Arrivals and Departures be returned for
    ///   - minutesAfter: How many minutes after now should Arrivals and Departures be returned for
    /// - Returns: The enqueued network operation.
    public func getArrivalsAndDeparturesForStop(id: String, minutesBefore: UInt, minutesAfter: UInt) -> StopArrivalsAndDeparturesOperation {
        let url = StopArrivalsAndDeparturesOperation.buildURL(stopID: id, minutesBefore: minutesBefore, minutesAfter: minutesAfter, baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: StopArrivalsAndDeparturesOperation.self, url: url)
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
    /// - Returns: The enqueued network operation.
    public func getTripArrivalDepartureAtStop(stopID: String, tripID: String, serviceDate: Date, vehicleID: String?, stopSequence: Int) -> TripArrivalDepartureOperation {
        let url = TripArrivalDepartureOperation.buildURL(stopID: stopID, tripID: tripID, serviceDate: serviceDate, vehicleID: vehicleID, stopSequence: stopSequence, baseURL: baseURL, defaultQueryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: TripArrivalDepartureOperation.self, url: url)
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
    /// - Returns: The enqueued network operation.
    @discardableResult public func getTrip(tripID: String, vehicleID: String?, serviceDate: Date?) -> TripDetailsOperation {
        let url = TripDetailsOperation.buildURL(tripID: tripID, vehicleID: vehicleID, serviceDate: serviceDate, baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: TripDetailsOperation.self, url: url)
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
    /// - Returns: The enqueued network operation.
    public func getStopsForRoute(id: String) -> StopsForRouteOperation {
        let url = StopsForRouteOperation.buildURL(routeID: id, baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: StopsForRouteOperation.self, url: url)
    }

    /// Search for routes within a region, by name
    ///
    /// - API Endpoint: `/api/where/routes-for-location.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/routes-for-location.html)
    ///
    /// - Parameters:
    ///   - query: Search query
    ///   - region: The circular region from which to return results.
    /// - Returns: The enqueued network operation.
    public func getRoute(query: String, region: CLCircularRegion) -> RouteSearchOperation {
        let url = RouteSearchOperation.buildURL(searchQuery: query, region: region, baseURL: baseURL, defaultQueryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: RouteSearchOperation.self, url: url)
    }

    /// Performs a local search and returns matching results
    ///
    /// - Parameters:
    ///   - query: The term for which to search.
    ///   - region: The coordinate region in which to search.
    /// - Returns: The enqueued network operation.
    public func getPlacemarks(query: String, region: MKCoordinateRegion) -> PlacemarkSearchOperation {
        let operation = PlacemarkSearchOperation(query: query, region: region)
        networkQueue.addOperation(operation)

        return operation
    }

    // MARK: - Shapes

    /// Retrieve a shape (the path traveled by a transit vehicle) by id
    ///
    /// - API Endpoint: `/api/where/shape/{id}.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/shape.html)
    ///
    /// - Parameters:
    ///   - id: The ID of the shape to retrieve.
    /// - Returns: The enqueued network operation.
    public func getShape(id: String) -> ShapeOperation {
        let url = ShapeOperation.buildURL(shapeID: id, baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: ShapeOperation.self, url: url)
    }

    // MARK: - Agencies

    public func getAgenciesWithCoverage() -> AgenciesWithCoverageOperation {
        let url = AgenciesWithCoverageOperation.buildURL(baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: AgenciesWithCoverageOperation.self, url: url)
    }

    // MARK: - Regional Alerts

    public func getRegionalAlerts(agencyID: String) -> RegionalAlertsOperation {
        let url = RegionalAlertsOperation.buildRESTURL(agencyID: agencyID, baseURL: baseURL, queryItems: defaultQueryItems)
        let request = RegionalAlertsOperation.buildRequest(for: url)
        let operation = RegionalAlertsOperation(request: request)
        networkQueue.addOperation(operation)

        return operation
    }

    // MARK: - Problem Reporting

    /// Submit a user-generated problem report for a particular stop.
    ///
    /// - API Endpoint: `/api/where/report-problem-with-stop/{stopID}.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/1.1.19/api/where/methods/report-problem-with-stop.html)
    ///
    /// The reporting mechanism provides lots of fields that can be specified to give more context
    /// about the details of the problem (which trip, stop, vehicle, etc was involved), making it
    /// easier for a developer or transit agency staff to diagnose the problem. These reports feed
    /// into the problem reporting admin interface.
    ///
    /// - Parameters:
    ///   - stopID: The stop ID where the problem was encountered.
    ///   - code: A code to indicate the type of problem encountered.
    ///   - comment: An optional free text field that allows the user to provide more context.
    ///   - location: An optional location value to provide more context.
    /// - Returns: The enqueued network operation.
    public func getStopProblem(stopID: String, code: StopProblemCode, comment: String?, location: CLLocation?) -> StopProblemOperation {
        let url = StopProblemOperation.buildURL(stopID: stopID, code: code, comment: comment, location: location, baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: StopProblemOperation.self, url: url)
    }

    /// Submit a user-generated problem report for a particular trip.
    ///
    /// - API Endpoint: `/api/where/report-problem-with-trip/{stopID}.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/1.1.19/api/where/methods/report-problem-with-trip.html)
    ///
    /// The reporting mechanism provides lots of fields that can be specified to give more context about the details of the
    /// problem (which trip, stop, vehicle, etc was involved), making it easier for a developer or transit agency staff to
    /// diagnose the problem. These reports feed into the problem reporting admin interface.
    ///
    /// - Parameter tripID: The trip ID on which the problem was encountered.
    /// - Parameter serviceDate: The service date of the trip.
    /// - Parameter vehicleID: Optional. The vehicle ID on which the problem was encountered.
    /// - Parameter stopID: Optional. The stop ID indicating the stop where the problem was encountered.
    /// - Parameter code: An identifier clarifying the type of problem encountered.
    /// - Parameter comment: Optional. Free-form user input describing the issue.
    /// - Parameter userOnVehicle: Indicates if the user is on the vehicle experiencing the issue.
    /// - Parameter location: Optional. The user's current location.
    /// - Returns: The enqueued network operation.
    public func getTripProblem(
        tripID: String,
        serviceDate: Date,
        vehicleID: String?,
        stopID: String?,
        code: TripProblemCode,
        comment: String?,
        userOnVehicle: Bool,
        location: CLLocation?
    ) -> TripProblemOperation {
        // swiftlint:disable:next line_length
        let url = TripProblemOperation.buildURL(tripID: tripID, serviceDate: serviceDate, vehicleID: vehicleID, stopID: stopID, code: code, comment: comment, userOnVehicle: userOnVehicle, location: location, baseURL: baseURL, queryItems: defaultQueryItems)
        return buildAndEnqueueOperation(type: TripProblemOperation.self, url: url)
    }

    // MARK: - Private Internal Helpers

    private func buildAndEnqueueOperation<T>(type: T.Type, url: URL) -> T where T: RESTAPIOperation {
        let request = type.buildRequest(for: url)
        let operation = type.init(request: request)
        networkQueue.addOperation(operation)

        return operation
    }
}
