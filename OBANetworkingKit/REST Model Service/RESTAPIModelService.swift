//
//  RESTAPIModelService.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/18/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import CoreLocation
import Foundation

@objc(OBARESTAPIModelService)
public class RESTAPIModelService: NSObject {
    private let dataQueue: OperationQueue
    private let apiService: RESTAPIService

    public init(apiService: RESTAPIService, dataQueue: OperationQueue) {
        self.apiService = apiService
        self.dataQueue = dataQueue
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
        let data = VehicleStatusModelOperation()

        transferData(from: service, to: data) { [unowned service, unowned data] in
            data.apiOperation = service
        }

        return data
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
    /// - Returns: The enqueued model operation.
    public func getTripDetails(vehicleID: String) -> TripDetailsModelOperation {
        let service = apiService.getVehicleTrip(vehicleID: vehicleID)
        let data = TripDetailsModelOperation()

        transferData(from: service, to: data) { [unowned service, unowned data] in
            data.apiOperation = service
        }

        return data
    }

    // MARK: - Miscellaneous

    /// Retrieves the server's current date and time.
    ///
    /// Useful for easily verifying that a given OBA server URL is working correctly.
    ///
    /// - Returns: The enqueued model operation.
    public func getCurrentTime() -> CurrentTimeModelOperation {
        let service = apiService.getCurrentTime()
        let data = CurrentTimeModelOperation()

        transferData(from: service, to: data) { [unowned service, unowned data] in
            data.apiOperation = service
        }

        return data
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
        let data = StopsModelOperation()

        transferData(from: service, to: data) { [unowned service, unowned data] in
            data.apiOperation = service
        }

        return data
    }

    // MARK: - Private Internal Helpers

    private func transferData(from serviceOperation: Operation, to dataOperation: Operation, transfer: @escaping () -> Void) {
        let transferOperation = BlockOperation(block: transfer)

        transferOperation.addDependency(serviceOperation)
        dataOperation.addDependency(transferOperation)

        dataQueue.addOperations([transferOperation, dataOperation], waitUntilFinished: false)
    }

    /*
In Progress:

 TODO:

func getStops(region: MKCoordinateRegion, completion: RESTAPICompletionBlock?) -> StopsOperation
func getStops(circularRegion: CLCircularRegion, query: String, completion: RESTAPICompletionBlock?) -> StopsOperation
func getArrivalsAndDeparturesForStop(id: String, minutesBefore: UInt, minutesAfter: UInt, completion: RESTAPICompletionBlock?) fivalsAndDeparturesOperation
func getTripArrivalDepartureForStop(stopID: String, tripID: String, serviceDate: Int64, vehicleID: String?, stopSequence: Int, f: RESTAPICompletionBlock?) -> ArrivalDepartureForStopOperation
func getTrip(tripID: String, vehicleID: String?, serviceDate: Int64, completion: RESTAPICompletionBlock?) -> fsOperation
func getStopsForRoute(id: String, completion: RESTAPICompletionBlock?) -> StopsForRouteOperation
func getRoute(query: String, region: CLCircularRegion, completion: RESTAPICompletionBlock?) -> RouteSearchOperation
func getPlacemarks(query: String, region: MKCoordinateRegion, completion: PlacemarkSearchCompletionBlock?) -> fearchOperation
func getShape(id: String, completion: RESTAPICompletionBlock?) -> ShapeOperation
func getAgenciesWithCoverage(completion: RESTAPICompletionBlock?) -> AgenciesWithCoverageOperation
func getRegionalAlerts(agencyID: String, completion: RegionalAlertsCompletionBlock?) -> RegionalAlertsOperation
func getStopProblem(stopID: String, code: StopProblemCode, comment: String, location: CLLocation?, completion: fpletionBlock?) -> StopProblemOperation
func getTripProblem(tripID: String, serviceDate: Int64, vehicleID: String?, stopID: String?, code: TripProblemCode, comment: String?, userOnVehicle: Bool, location: CLLocation?, completion: RESTAPICompletionBlock?) -> TripProblemOperation

DONE:

func getVehicle(_ vehicleID: String, completion: RESTAPICompletionBlock?) -> RequestVehicleOperation
func getVehicleTrip(vehicleID: String, completion: RESTAPICompletionBlock?) -> VehicleTripOperation
func getCurrentTime(completion: RESTAPICompletionBlock?) -> CurrentTimeOperation
func getStops(coordinate: CLLocationCoordinate2D, completion: RESTAPICompletionBlock?) -> StopsOperation
 */
}
