//
//  RESTAPIModelService.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/18/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import CoreLocation
import Foundation
import MapKit

/// Provides access to the OneBusAway REST API
///
/// - Note: See [develop.onebusaway.org](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/index.html)
///         for more information on the REST API.
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

    /// Retrieves the stop with the specified ID.
    ///
    /// - API Endpoint: `/api/where/stop/{id}.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/stop.html)
    ///
    /// - Parameters:
    ///   - id: The full, agency-prefixed ID of the stop.
    /// - Returns: The enqueued model operation.
    public func getStop(id: String) -> StopsModelOperation {
        let service = apiService.getStop(id: id)
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
    func getTripDetails(tripID: String, vehicleID: String?, serviceDate: Date?) -> TripDetailsModelOperation {
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
    ///   - routeID: The route ID
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
    public func getStopProblem(stopID: String, code: StopProblemCode, comment: String?, location: CLLocation?) -> StopProblemModelOperation {
        let service = apiService.getStopProblem(stopID: stopID, code: code, comment: comment, location: location)
        return generateModels(type: StopProblemModelOperation.self, serviceOperation: service)
    }

    public func getTripProblem(tripID: String, serviceDate: Date, vehicleID: String?, stopID: String?, code: TripProblemCode, comment: String?, userOnVehicle: Bool, location: CLLocation?) -> TripProblemModelOperation {
        let service = apiService.getTripProblem(tripID: tripID, serviceDate: serviceDate, vehicleID: vehicleID, stopID: stopID, code: code, comment: comment, userOnVehicle: userOnVehicle, location: location)
        return generateModels(type: TripProblemModelOperation.self, serviceOperation: service)
    }

    // MARK: - Alerts

    public func getRegionalAlerts() -> RegionalAlertsModelOperation {
        // Get a list of agencies
        let agenciesOperation = getAgenciesWithCoverage()

        // Set up the final operation that will collect all of our agency alerts.
        let regionalAlertsOperation = RegionalAlertsModelOperation()

        // Create a transfer operation that will create `n` alert
        // fetch operations for our `n` agencies. Also make the
        // final operation dependent on each of those sub-ops.
        let agenciesTransfer = BlockOperation { [unowned agenciesOperation, unowned regionalAlertsOperation] in
            let agencies = agenciesOperation.agenciesWithCoverage

            for agency in agencies {
                // Create a 'fetch alerts' operation for each agency
                let fetchAlertsOp = self.getRegionalAlerts(agency: agency)

                // add each 'fetch alerts' op as a dependency of the final operation.
                regionalAlertsOperation.addDependency(fetchAlertsOp)
            }
        }

        agenciesTransfer.addDependency(agenciesOperation)
        regionalAlertsOperation.addDependency(agenciesTransfer)

        dataQueue.addOperations([agenciesTransfer, regionalAlertsOperation], waitUntilFinished: false)

        return regionalAlertsOperation
    }

    func getRegionalAlerts(agency: AgencyWithCoverage) -> AgencyAlertsModelOperation {
        // Create the parent operations: we depend on GTFS alert data
        // and the list of agencies in the region.
        let serviceOperation = apiService.getRegionalAlerts(agencyID: agency.agencyID)

        // Create the operation that will process the agencies and the GTFS data.
        let dataOperation = AgencyAlertsModelOperation(agency: agency)

        // The transfer operation will prime the data operation with the raw data it needs.
        let transferOperation = BlockOperation { [unowned serviceOperation, unowned dataOperation] in
            dataOperation.apiOperation = serviceOperation
        }

        // Make the transfer operation dependent on the GTFS alert operation.
        transferOperation.addDependency(serviceOperation)

        // Make the data operation dependent on the transfer operation so that we can guarantee
        // that we will have all of our necessary data before beginning the data processing.
        dataOperation.addDependency(transferOperation)

        // Enqueue everything.
        dataQueue.addOperations([transferOperation, dataOperation], waitUntilFinished: false)

        // Return the data operation so the caller can become dependent on it and grab its data.
        return dataOperation
    }

    // MARK: - Placemarks

    public func getPlacemarks(query: String, region: MKCoordinateRegion) -> PlacemarkSearchOperation {
        return apiService.getPlacemarks(query: query, region: region)
    }

    // MARK: - Private Internal Helpers

    private func generateModels<T>(type: T.Type, serviceOperation: RESTAPIOperation) -> T where T: RESTModelOperation {
        let dataOperation = type.init()

        let transferOperation = TransferOperation(serviceOperation: serviceOperation, dataOperation: dataOperation)

        transferOperation.addDependency(serviceOperation)
        dataOperation.addDependency(transferOperation)

        dataQueue.addOperations([transferOperation, dataOperation], waitUntilFinished: false)

        return dataOperation
    }
}
