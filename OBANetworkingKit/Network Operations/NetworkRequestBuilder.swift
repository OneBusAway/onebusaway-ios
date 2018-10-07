//
//  NetworkRequestBuilder.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation
import MapKit

//- (AnyPromise*)requestStopsForRoute:(NSString*)routeID;
//- (AnyPromise*)requestStopsForPlacemark:(OBAPlacemark*)placemark;
//- (AnyPromise*)requestRoutesForQuery:(NSString*)routeQuery region:(CLCircularRegion*)region;
//- (AnyPromise*)placemarksForAddress:(NSString*)address;
//- (OBAModelServiceRequest*)reportProblemWithStop:(OBAReportProblemWithStopV2 *)problem completionBlock:(OBADataSourceCompletion)completion;
//- (OBAModelServiceRequest*)reportProblemWithTrip:(OBAReportProblemWithTripV2 *)problem completionBlock:(OBADataSourceCompletion)completion;

// Done:

//x (AnyPromise*)requestShapeForID:(NSString*)shapeID;
//x (AnyPromise*)requestArrivalAndDeparture:(OBAArrivalAndDepartureInstanceRef*)instanceRef;
//x (AnyPromise*)requestArrivalAndDepartureWithConvertible:(id<OBAArrivalAndDepartureConvertible>)convertible;
//x (AnyPromise*)requestStopsForRegion:(MKCoordinateRegion)region;
//x (AnyPromise*)requestStopsForQuery:(NSString*)query region:(nullable CLCircularRegion*)region;
//x (AnyPromise*)requestStopsNear:(CLLocationCoordinate2D)coordinate;
//x (AnyPromise*)requestVehicleForID:(NSString*)vehicleID;
//x (AnyPromise*)requestCurrentTime;

public typealias NetworkCompletionBlock = (_ operation: RESTAPIOperation) -> Void

@objc(OBANetworkRequestBuilder)
public class NetworkRequestBuilder: NSObject {
    private let baseURL: URL
    private let networkQueue: NetworkQueue

    @objc public init(baseURL: URL, networkQueue: NetworkQueue) {
        self.baseURL = baseURL
        self.networkQueue = networkQueue
    }

    @objc public convenience init(baseURL: URL) {
        self.init(baseURL: baseURL, networkQueue: NetworkQueue())
    }

    // MARK: - Query Items

    private var defaultQueryItems: [URLQueryItem] {
        var items = [URLQueryItem]()
        items.append(URLQueryItem(name: "key", value: "org.onebusaway.iphone"))
        items.append(URLQueryItem(name: "app_uid", value: "BD88D98C-A72D-47BE-8F4A-C60467239736"))
        items.append(URLQueryItem(name: "app_ver", value: "20181001.23"))
        items.append(URLQueryItem(name: "version", value: "2"))

        return items
    }

    // MARK: - Vehicle with ID

    @discardableResult @objc
    public func getVehicle(_ vehicleID: String, completion: NetworkCompletionBlock?) -> RequestVehicleOperation {
        let url = RequestVehicleOperation.buildURL(vehicleID: vehicleID, baseURL: baseURL, queryItems: defaultQueryItems)
        let operation = RequestVehicleOperation(url: url)
        operation.completionBlock = { [weak operation] in
            if let operation = operation { completion?(operation) }
        }
        networkQueue.add(operation)

        return operation
    }

    // MARK: - Current Time

    @discardableResult @objc
    public func getCurrentTime(completion: NetworkCompletionBlock?) -> CurrentTimeOperation {
        let url = CurrentTimeOperation.buildURL(baseURL: baseURL, queryItems: defaultQueryItems)
        let operation = CurrentTimeOperation(url: url)
        operation.completionBlock = { [weak operation] in
            if let operation = operation { completion?(operation) }
        }

        networkQueue.add(operation)

        return operation
    }

    // MARK: - Stops

    @discardableResult @objc
    public func getStops(coordinate: CLLocationCoordinate2D, completion: NetworkCompletionBlock?) -> StopsOperation {
        let url = StopsOperation.buildURL(coordinate: coordinate, baseURL: baseURL, defaultQueryItems: defaultQueryItems)
        return getStops(url: url, completion: completion)
    }

    @discardableResult @objc
    public func getStops(region: MKCoordinateRegion, completion: NetworkCompletionBlock?) -> StopsOperation {
        let url = StopsOperation.buildURL(region: region, baseURL: baseURL, defaultQueryItems: defaultQueryItems)
        return getStops(url: url, completion: completion)
    }

    @discardableResult @objc
    public func getStops(circularRegion: CLCircularRegion, query: String, completion: NetworkCompletionBlock?) -> StopsOperation {
        let url = StopsOperation.buildURL(circularRegion: circularRegion, query: query, baseURL: baseURL, defaultQueryItems: defaultQueryItems)
        return getStops(url: url, completion: completion)
    }

    private func getStops(url: URL, completion: NetworkCompletionBlock?) -> StopsOperation {
        let operation = StopsOperation(url: url)
        operation.completionBlock = { [weak operation] in
            if let operation = operation { completion?(operation) }
        }
        networkQueue.add(operation)
        return operation
    }

    // MARK: - Arrival and Departure for Stop

    @discardableResult @objc
    public func getArrivalDepartureForStop(stopID: String, tripID: String, serviceDate: Int64, vehicleID: String?, stopSequence: Int, completion: NetworkCompletionBlock?) -> ArrivalDepartureForStopOperation {
        let url = ArrivalDepartureForStopOperation.buildURL(stopID: stopID, tripID: tripID, serviceDate: serviceDate, vehicleID: vehicleID, stopSequence: stopSequence, baseURL: baseURL, defaultQueryItems: defaultQueryItems)
        let operation = ArrivalDepartureForStopOperation(url: url)
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
        let operation = ShapeOperation(url: url)
        operation.completionBlock = { [weak operation] in
            if let operation = operation { completion?(operation) }
        }

        networkQueue.add(operation)
        return operation
    }
}
