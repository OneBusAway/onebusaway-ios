//
//  RESTAPIModelService.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/18/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import CoreLocation
import Foundation
import MapKit

@objc(OBARESTAPIModelService)
public class RESTAPIModelService: NSObject {
    private let dataQueue: OperationQueue
    private let apiService: RESTAPIService

    public init(apiService: RESTAPIService, dataQueue: OperationQueue) {
        self.apiService = apiService
        self.dataQueue = dataQueue
    }

    // MARK: - Agencies
    public func getAgenciesWithCoverage() -> AgenciesWithCoverageModelOperation {
        let service = apiService.getAgenciesWithCoverage()
        return generateModels(type: AgenciesWithCoverageModelOperation.self, serviceOperation: service)
    }


    // MARK: - Vehicles

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
    /// - Parameter vehicleID: Vehicle ID string
    /// - Returns: The enqueued model operation.
    public func getVehicleStatus(_ vehicleID: String) -> VehicleStatusModelOperation {
        let service = apiService.getVehicle(vehicleID)
        return generateModels(type: VehicleStatusModelOperation.self, serviceOperation: service)
    }

    // MARK: - Miscellaneous

    /// Retrieves the server's current date and time.
    ///
    /// Useful for easily verifying that a given OBA server URL is working correctly.
    ///
    /// - Returns: The enqueued model operation.
    public func getCurrentTime() -> CurrentTimeModelOperation {
        let service = apiService.getCurrentTime()
        return generateModels(type: CurrentTimeModelOperation.self, serviceOperation: service)
    }

    // MARK: - Stops

    /// Retrieves stops in the vicinity of `coordinate`.
    ///
    /// - API Endpoint: `/api/where/stops-for-location.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/stops-for-location.html)
    ///
    /// - Parameters:
    ///   - coordinate: The coordinate around which to search for stops.
    /// - Returns: The enqueued model operation.
    public func getStops(coordinate: CLLocationCoordinate2D) -> StopsModelOperation {
        let service = apiService.getStops(coordinate: coordinate)
        return generateModels(type: StopsModelOperation.self, serviceOperation: service)
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
    /// - Returns: The enqueued model operation.
    public func getStops(region: MKCoordinateRegion) -> StopsModelOperation {
        let service = apiService.getStops(region: region)
        return generateModels(type: StopsModelOperation.self, serviceOperation: service)
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
    /// - Returns: The enqueued model operation.
    public func getStops(circularRegion: CLCircularRegion, query: String) -> StopsModelOperation {
        let service = apiService.getStops(circularRegion: circularRegion, query: query)
        return generateModels(type: StopsModelOperation.self, serviceOperation: service)
    }

    // MARK: - Arrivals and Departures

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
    /// - Returns: The enqueued model operation.
    public func getArrivalsAndDeparturesForStop(id: String, minutesBefore: UInt, minutesAfter: UInt) -> StopArrivalsModelOperation {
        let service = apiService.getArrivalsAndDeparturesForStop(id: id, minutesBefore: minutesBefore, minutesAfter: minutesAfter)
        return generateModels(type: StopArrivalsModelOperation.self, serviceOperation: service)
    }

    /// Get info about a single arrival and departure at a stop
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
    /// - Returns: The enqueued model operation.
    public func getTripArrivalDepartureAtStop(stopID: String, tripID: String, serviceDate: Int64, vehicleID: String?, stopSequence: Int) -> TripArrivalsModelOperation {
        let service = apiService.getTripArrivalDepartureAtStop(stopID: stopID, tripID: tripID, serviceDate: serviceDate, vehicleID: vehicleID, stopSequence: stopSequence)
        return generateModels(type: TripArrivalsModelOperation.self, serviceOperation: service)
    }

    // MARK: - Trips

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
    /// - Returns: The enqueued model operation.
    public func getTripDetails(vehicleID: String) -> TripDetailsModelOperation {
        let service = apiService.getVehicleTrip(vehicleID: vehicleID)
        return generateModels(type: TripDetailsModelOperation.self, serviceOperation: service)
    }

    /// Get extended details for a specific trip.
    ///
    /// - API Endpoint: `/api/where/trip-details/{id}.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/trip-details.html)
    ///
    /// - Parameters:
    ///   - tripID: The ID of the trip.
    ///   - vehicleID: Optional ID for the specific transit vehicle on this trip.
    ///   - serviceDate: The service date for this trip.
    /// - Returns: The enqueued model operation.
    func getTripDetails(tripID: String, vehicleID: String?, serviceDate: Int64) -> TripDetailsModelOperation {
        let service = apiService.getTrip(tripID: tripID, vehicleID: vehicleID, serviceDate: serviceDate)
        return generateModels(type: TripDetailsModelOperation.self, serviceOperation: service)
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
    ///   - id: The route ID
    /// - Returns: The enqueued model operation.
    public func getStopsForRoute(routeID: String) -> StopsForRouteModelOperation {
        let service = apiService.getStopsForRoute(id: routeID)
        return generateModels(type: StopsForRouteModelOperation.self, serviceOperation: service)
    }

    /// Search for routes within a region, by name
    ///
    /// - API Endpoint: `/api/where/routes-for-location.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/routes-for-location.html)
    ///
    /// - Parameters:
    ///   - query: Search query
    ///   - region: The circular region from which to return results.
    /// - Returns: The enqueued model operation.
    public func getRoute(query: String, region: CLCircularRegion) -> RouteSearchModelOperation {
        let service = apiService.getRoute(query: query, region: region)
        return generateModels(type: RouteSearchModelOperation.self, serviceOperation: service)
    }

    /// Retrieve a shape (the path traveled by a transit vehicle) by id
    ///
    /// - API Endpoint: `/api/where/shape/{id}.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/shape.html)
    ///
    /// - Parameters:
    ///   - id: The ID of the shape to retrieve.
    /// - Returns: The enqueued model operation.
    public func getShape(id: String) -> ShapeModelOperation {
        let service = apiService.getShape(id: id)
        return generateModels(type: ShapeModelOperation.self, serviceOperation: service)
    }

    // MARK: - Problem Reporting

    /// Submit a user-generated problem report for a particular stop.
    ///
    /// - API Endpoint: `/api/where/report-problem-with-stop/{stopID}.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/1.1.19/api/where/methods/report-problem-with-stop.html)
    ///
    /// The reporting mechanism provides lots of fields that can be specified to give more context about the details of the problem (which trip, stop, vehicle, etc was involved), making it easier for a developer or transit agency staff to diagnose the problem. These reports feed into the problem reporting admin interface.
    ///
    /// - Parameters:
    ///   - stopID: The stop ID where the problem was encountered.
    ///   - code: A code to indicate the type of problem encountered.
    ///   - comment: An optional free text field that allows the user to provide more context.
    ///   - location: An optional location value to provide more context.
    /// - Returns: The enqueued model operation.
    public func getStopProblem(stopID: String, code: StopProblemCode, comment: String, location: CLLocation?) -> StopProblemModelOperation {
        let service = apiService.getStopProblem(stopID: stopID, code: code, comment: comment, location: location)
        return generateModels(type: StopProblemModelOperation.self, serviceOperation: service)
    }

//
//    func getTripProblem(tripID: String, serviceDate: Int64, vehicleID: String?, stopID: String?, code: TripProblemCode, comment: String?, userOnVehicle: Bool, location: CLLocation?, completion: RESTAPICompletionBlock?) -> TripProblemOperation


    // MARK: - Private Internal Helpers

    private func generateModels<T>(type: T.Type, serviceOperation: RESTAPIOperation) -> T where T: RESTModelOperation {
        let data = type.init()
        transferData(from: serviceOperation, to: data) { [unowned serviceOperation, unowned data] in
            data.apiOperation = serviceOperation
        }

        return data
    }

    private func transferData(from serviceOperation: Operation, to dataOperation: Operation, transfer: @escaping () -> Void) {
        let transferOperation = BlockOperation(block: transfer)

        transferOperation.addDependency(serviceOperation)
        dataOperation.addDependency(transferOperation)

        dataQueue.addOperations([transferOperation, dataOperation], waitUntilFinished: false)
    }

    /*
 TODO:
     func getRegionalAlerts(agencyID: String, completion: RegionalAlertsCompletionBlock?) -> RegionalAlertsOperation
     func getPlacemarks(query: String, region: MKCoordinateRegion, completion: PlacemarkSearchCompletionBlock?) -> fearchOperation
 */
}
