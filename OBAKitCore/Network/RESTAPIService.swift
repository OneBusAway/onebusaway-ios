//
//  RESTAPIService.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import MapKit

/// Loads data from a OneBusAway REST API server and returns it as model objects.

@available(*, deprecated, message: "Use RESTAPIService")
public class _RESTAPIService: APIService {
    lazy var URLBuilder = RESTAPIURLBuilder(baseURL: baseURL, defaultQueryItems: defaultQueryItems)

    private let regionIdentifier: Int

    /// Creates a new instance of `RESTAPIService`.
    /// - Parameters:
    ///   - baseURL: The base URL for the service you will be using.
    ///   - apiKey: The API key for the service you will be using. Passed along as `key` in query params.
    ///   - uuid: A unique, anonymous user ID.
    ///   - appVersion: The version of the app making the request.
    ///   - networkQueue: The queue on which all network operations will be performed.
    ///   - dataLoader: The object used to perform network operations. A protocol facade is provided here to simplify testing.
    ///   - regionIdentifier: The unique ID of the `Region` that this service object is tied to.
    public init(baseURL: URL, apiKey: String, uuid: String, appVersion: String, networkQueue: OperationQueue, dataLoader: URLDataLoader, regionIdentifier: Int) {
        self.regionIdentifier = regionIdentifier
        super.init(baseURL: baseURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, networkQueue: networkQueue, dataLoader: dataLoader)
    }

    private func buildOperation<T>(type: T.Type, URL: URL) -> DecodableOperation<T> where T: Decodable {
        return DecodableOperation(type: type, decoder: JSONDecoder.RESTDecoder(regionIdentifier: regionIdentifier), URL: URL, dataLoader: dataLoader)
    }

    // MARK: - Vehicle with ID

    /// Provides information on the vehicle with the specified ID.
    ///
    /// API Endpoint: `/api/where/vehicle/{id}.json`
    ///
    /// - Important: Vehicle IDs are seldom identical to the IDs that are physically printed
    /// on buses. For example, in Puget Sound, a KC Metro bus that has the number `1234`
    /// printed on its side will likely have the vehicle ID `1_1234` to ensure that the vehicle ID
    /// is unique across the Puget Sound region with all of its agencies.
    ///
    /// - Parameters:
    ///   - vehicleID: Vehicle ID string
    /// - Returns: The enqueued network operation.
    public func getVehicle(_ vehicleID: String) -> DecodableOperation<RESTAPIResponse<VehicleStatus>> {
        let url = URLBuilder.getVehicleURL(vehicleID)
        let operation = buildOperation(type: RESTAPIResponse<VehicleStatus>.self, URL: url)
        enqueueOperation(operation)
        return operation
    }

    /// Get extended trip details for a specific transit vehicle. That is, given a vehicle id for a transit vehicle
    /// currently operating in the field, return extended trip details about the current trip for the vehicle.
    ///
    /// - API Endpoint: `/api/where/trip-for-vehicle/{id}.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/trip-for-vehicle.html)
    ///
    /// - Important: Vehicle IDs are seldom identical to the IDs that are physically printed
    /// on buses. For example, in Puget Sound, a KC Metro bus that has the number `1234`
    /// printed on its side will likely have the vehicle ID `1_1234` to ensure that the vehicle ID
    /// is unique across the Puget Sound region with all of its agencies.
    ///
    /// - Parameters:
    ///   - vehicleID: The ID of the vehicle
    /// - Returns: The enqueued network operation.
    public func getVehicleTrip(vehicleID: String) -> DecodableOperation<RESTAPIResponse<TripDetails>> {
        let url = URLBuilder.getVehicleTrip(vehicleID: vehicleID)
        let operation = buildOperation(type: RESTAPIResponse<TripDetails>.self, URL: url)
        enqueueOperation(operation)
        return operation
    }

    // MARK: - Stops
    /// Retrieves the stop with the specified ID.
    ///
    /// - API Endpoint: `/api/where/stop/{id}.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/stop.html)
    ///
    /// - Parameters:
    ///   - id: The full, agency-prefixed ID of the stop.
    ///   - enqueue: When `false`, the caller will be expected to enqueue this operation themselves.
    /// - Returns: The enqueued network operation.
    @available(*, deprecated, message: "This is for DataMigrator use only.")
    func getStop(id: String, enqueue: Bool = true) -> DecodableOperation<RESTAPIResponse<Stop>> {
        let url = URLBuilder.getStop(stopID: id)
        let operation = buildOperation(type: RESTAPIResponse<Stop>.self, URL: url)
        if enqueue { enqueueOperation(operation) }
        return operation
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
    ///   - enqueue: When `false`, the caller will be expected to enqueue this operation themselves.
    /// - Returns: The enqueued network operation.
    public func getArrivalsAndDeparturesForStop(id: StopID, minutesBefore: UInt, minutesAfter: UInt, enqueue: Bool = true) -> DecodableOperation<RESTAPIResponse<StopArrivals>> {
        let url = URLBuilder.getArrivalsAndDeparturesForStop(id: id, minutesBefore: minutesBefore, minutesAfter: minutesAfter)
        let operation = buildOperation(type: RESTAPIResponse<StopArrivals>.self, URL: url)
        if enqueue { enqueueOperation(operation) }
        return operation
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
    public func getTripArrivalDepartureAtStop(stopID: StopID, tripID: String, serviceDate: Date, vehicleID: String?, stopSequence: Int) -> DecodableOperation<RESTAPIResponse<ArrivalDeparture>> {
        let url = URLBuilder.getTripArrivalDepartureAtStop(stopID: stopID, tripID: tripID, serviceDate: serviceDate, vehicleID: vehicleID, stopSequence: stopSequence)
        let operation = buildOperation(type: RESTAPIResponse<ArrivalDeparture>.self, URL: url)
        enqueueOperation(operation)
        return operation
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
    public func getTrip(tripID: String, vehicleID: String?, serviceDate: Date?) -> DecodableOperation<RESTAPIResponse<TripDetails>> {
        let url = URLBuilder.getTrip(tripID: tripID, vehicleID: vehicleID, serviceDate: serviceDate)
        let operation = buildOperation(type: RESTAPIResponse<TripDetails>.self, URL: url)
        enqueueOperation(operation)
        return operation
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
    public func getStopsForRoute(id: RouteID) -> DecodableOperation<RESTAPIResponse<StopsForRoute>> {
        let url = URLBuilder.getStopsForRoute(id: id)
        let operation = buildOperation(type: RESTAPIResponse<StopsForRoute>.self, URL: url)
        enqueueOperation(operation)
        return operation
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
    public func getRoute(query: String, region: CLCircularRegion) -> DecodableOperation<RESTAPIResponse<[Route]>> {
        let url = URLBuilder.getRoute(query: query, region: region)
        let operation = buildOperation(type: RESTAPIResponse<[Route]>.self, URL: url)
        enqueueOperation(operation)
        return operation
    }

    /// Performs a local search and returns matching results
    ///
    /// - Parameters:
    ///   - query: The term for which to search.
    ///   - region: The coordinate region in which to search.
    /// - Returns: The enqueued network operation.
    public func getPlacemarks(query: String, region: MKCoordinateRegion) -> PlacemarkSearchOperation {
        let operation = PlacemarkSearchOperation(query: query, region: region)
        enqueueOperation(operation)
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
    public func getShape(id: String) -> DecodableOperation<RESTAPIResponse<PolylineEntity>> {
        let url = URLBuilder.getShape(id: id)
        let operation = buildOperation(type: RESTAPIResponse<PolylineEntity>.self, URL: url)
        enqueueOperation(operation)
        return operation
    }

    // MARK: - Agencies

    /// Retrieves a list of agencies with known coverage areas for the current region.
    ///
    /// - API Endpoint: `/api/where/agencies-with-coverage.json`
    ///
    /// - Returns: The enqueued network operation.
    public func getAgenciesWithCoverage() -> DecodableOperation<RESTAPIResponse<[AgencyWithCoverage]>> {
        let url = URLBuilder.getAgenciesWithCoverage()
        let operation = buildOperation(type: RESTAPIResponse<[AgencyWithCoverage]>.self, URL: url)
        enqueueOperation(operation)
        return operation
    }

    // MARK: - Regional Alerts

    public func getAlerts(agencies: [AgencyWithCoverage]) -> MultiAgencyAlertsOperation {
        // Set up the final operation that will collect all of our agency alerts.
        let multiAgencyOp = MultiAgencyAlertsOperation()

        for agency in agencies {
            let subOp = getAlerts(agency: agency)
            multiAgencyOp.addDependency(subOp)
        }

        networkQueue.addOperation(multiAgencyOp)

        return multiAgencyOp
    }

    public func getAlerts(agency: AgencyWithCoverage) -> AgencyAlertsOperation {
        let url = URLBuilder.getRESTRegionalAlerts(agencyID: agency.agencyID)
        let operation = AgencyAlertsOperation(agencies: [agency], URL: url, dataLoader: dataLoader)
        enqueueOperation(operation)
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
    public func getStopProblem(
        stopID: StopID,
        code: StopProblemCode,
        comment: String?,
        location: CLLocation?
    ) -> DecodableOperation<CoreRESTAPIResponse> {
        let url = URLBuilder.getStopProblem(stopID: stopID, code: code, comment: comment, location: location)
        let operation = buildOperation(type: CoreRESTAPIResponse.self, URL: url)
        enqueueOperation(operation)
        return operation
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
        stopID: StopID?,
        code: TripProblemCode,
        comment: String?,
        userOnVehicle: Bool,
        location: CLLocation?
    ) -> DecodableOperation<CoreRESTAPIResponse> {
        // swiftlint:disable:next line_length
        let url = URLBuilder.getTripProblem(tripID: tripID, serviceDate: serviceDate, vehicleID: vehicleID, stopID: stopID, code: code, comment: comment, userOnVehicle: userOnVehicle, location: location)
        let operation = buildOperation(type: CoreRESTAPIResponse.self, URL: url)
        enqueueOperation(operation)
        return operation
    }
}
