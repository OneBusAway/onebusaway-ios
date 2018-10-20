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

    public func getVehicle(_ vehicleID: String) -> VehicleModelOperation {
        let service = apiService.getVehicle(vehicleID)
        let data = VehicleModelOperation()

        transferData(from: service, to: data) { [unowned service, unowned data] in
            data.apiOperation = service
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
 @objc public func getVehicle(_ vehicleID: String, completion: RESTAPICompletionBlock?) -> RequestVehicleOperation
 @objc public func getVehicleTrip(vehicleID: String, completion: RESTAPICompletionBlock?) -> VehicleTripOperation
 @objc public func getCurrentTime(completion: RESTAPICompletionBlock?) -> CurrentTimeOperation
 @objc public func getStops(coordinate: CLLocationCoordinate2D, completion: RESTAPICompletionBlock?) -> StopsOperation
 @objc public func getStops(region: MKCoordinateRegion, completion: RESTAPICompletionBlock?) -> StopsOperation
 @objc public func getStops(circularRegion: CLCircularRegion, query: String, completion: RESTAPICompletionBlock?) -> StopsOperation
 @objc public func getArrivalsAndDeparturesForStop(id: String, minutesBefore: UInt, minutesAfter: UInt, completion: RESTAPICompletionBlock?) -> StopArrivalsAndDeparturesOperation
 @objc public func getTripArrivalDepartureForStop(stopID: String, tripID: String, serviceDate: Int64, vehicleID: String?, stopSequence: Int, completion: RESTAPICompletionBlock?) -> ArrivalDepartureForStopOperation
 @objc public func getTrip(tripID: String, vehicleID: String?, serviceDate: Int64, completion: RESTAPICompletionBlock?) -> TripDetailsOperation
 @objc public func getStopsForRoute(id: String, completion: RESTAPICompletionBlock?) -> StopsForRouteOperation
 @objc public func getRoute(query: String, region: CLCircularRegion, completion: RESTAPICompletionBlock?) -> RouteSearchOperation
 @objc public func getPlacemarks(query: String, region: MKCoordinateRegion, completion: PlacemarkSearchCompletionBlock?) -> PlacemarkSearchOperation
 @objc public func getShape(id: String, completion: RESTAPICompletionBlock?) -> ShapeOperation
 @objc public func getAgenciesWithCoverage(completion: RESTAPICompletionBlock?) -> AgenciesWithCoverageOperation
 @objc public func getRegionalAlerts(agencyID: String, completion: RegionalAlertsCompletionBlock?) -> RegionalAlertsOperation
 @objc public func getStopProblem(stopID: String, code: StopProblemCode, comment: String, location: CLLocation?, completion: RESTAPICompletionBlock?) -> StopProblemOperation
 @objc public func getTripProblem(tripID: String, serviceDate: Int64, vehicleID: String?, stopID: String?, code: TripProblemCode, comment: String?, userOnVehicle: Bool, location: CLLocation?, completion: RESTAPICompletionBlock?) -> TripProblemOperation
 */

}
