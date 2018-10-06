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

//- (AnyPromise*)requestArrivalAndDeparture:(OBAArrivalAndDepartureInstanceRef*)instanceRef;
//- (AnyPromise*)requestArrivalAndDepartureWithConvertible:(id<OBAArrivalAndDepartureConvertible>)convertible;
//- (AnyPromise*)requestShapeForID:(NSString*)shapeID;
//- (AnyPromise*)requestStopsForRegion:(MKCoordinateRegion)region;
//- (AnyPromise*)requestStopsForQuery:(NSString*)query region:(nullable CLCircularRegion*)region;
//- (AnyPromise*)requestStopsForRoute:(NSString*)routeID;
//- (AnyPromise*)requestStopsForPlacemark:(OBAPlacemark*)placemark;
//- (AnyPromise*)requestRoutesForQuery:(NSString*)routeQuery region:(CLCircularRegion*)region;
//- (AnyPromise*)placemarksForAddress:(NSString*)address;
//- (OBAModelServiceRequest*)reportProblemWithStop:(OBAReportProblemWithStopV2 *)problem completionBlock:(OBADataSourceCompletion)completion;
//- (OBAModelServiceRequest*)reportProblemWithTrip:(OBAReportProblemWithTripV2 *)problem completionBlock:(OBADataSourceCompletion)completion;

// Done:
//- (AnyPromise*)requestStopsNear:(CLLocationCoordinate2D)coordinate;
//x (AnyPromise*)requestVehicleForID:(NSString*)vehicleID;
//x (AnyPromise*)requestCurrentTime;

public typealias CurrentTimeCompletion = (_ operation: CurrentTimeOperation) -> Void
public typealias GetVehicleCompletion = (_ operation: RequestVehicleOperation) -> Void

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
    public func getVehicle(_ vehicleID: String, completion: GetVehicleCompletion?) -> RequestVehicleOperation {
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
    public func getCurrentTime(completion: CurrentTimeCompletion?) -> CurrentTimeOperation {
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
    public func getStops(coordinate: CLLocationCoordinate2D, completion: GetStopsCompletion?) -> StopsOperation {
        let url = StopsOperation.buildURL(coordinate: coordinate, baseURL: baseURL, defaultQueryItems: defaultQueryItems)
        return getStops(url: url, completion: completion)
    }

    @discardableResult @objc
    public func getStops(region: MKCoordinateRegion, completion: GetStopsCompletion?) -> StopsOperation {
        let url = StopsOperation.buildURL(region: region, baseURL: baseURL, defaultQueryItems: defaultQueryItems)
        return getStops(url: url, completion: completion)
    }

    @discardableResult @objc
    public func getStops(circularRegion: CLCircularRegion, query: String, completion: GetStopsCompletion?) -> StopsOperation {
        let url = StopsOperation.buildURL(circularRegion: circularRegion, query: query, baseURL: baseURL, defaultQueryItems: defaultQueryItems)
        return getStops(url: url, completion: completion)
    }

    private func getStops(url: URL, completion: GetStopsCompletion?) -> StopsOperation {
        let operation = StopsOperation(url: url)
        operation.completionBlock = { [weak operation] in
            if let operation = operation {
                completion?(operation)
            }
        }
        networkQueue.add(operation)
        return operation
    }
}
