//
//  RESTAPIModelService.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/18/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

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

    public func getVehicle(_ vehicleID: String) -> VehicleStatusModelOperation {
        let service = apiService.getVehicle(vehicleID)
        let data = VehicleStatusModelOperation()

        transferData(from: service, to: data) { [unowned service, unowned data] in
            data.apiOperation = service
        }

        return data
    }

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
func getVehicleTrip(vehicleID: String, completion: RESTAPICompletionBlock?) -> VehicleTripOperation
func getCurrentTime(completion: RESTAPICompletionBlock?) -> CurrentTimeOperation
func getStops(coordinate: CLLocationCoordinate2D, completion: RESTAPICompletionBlock?) -> StopsOperation
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
 */

}
