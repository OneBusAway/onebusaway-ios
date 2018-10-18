//
//  ObacoService.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/11/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public typealias WeatherCompletionBlock = (_ operation: WeatherOperation) -> Void
public typealias CreateAlarmCompletionBlock = (_ operation: CreateAlarmOperation) -> Void
public typealias DeleteAlarmCompletionBlock = (_ operation: NetworkOperation) -> Void


@objc(OBAObacoService)
public class ObacoService: APIService {

    private let regionID: String

    @objc public init(baseURL: URL, apiKey: String, uuid: String, appVersion: String, regionID: String, networkQueue: NetworkQueue) {
        self.regionID = regionID
        super.init(baseURL: baseURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, networkQueue: networkQueue)
    }

    // MARK: - Weather

    @discardableResult @objc
    public func getWeather(regionID: String, completion: WeatherCompletionBlock?) -> WeatherOperation {
        let url = WeatherOperation.buildURL(regionID: regionID, baseURL: baseURL, queryItems: defaultQueryItems)
        let operation = WeatherOperation(url: url)
        operation.completionBlock = { [weak operation] in
            if let operation = operation { completion?(operation) }
        }

        networkQueue.add(operation)

        return operation
    }

    // MARK: - Alarms

    @discardableResult @objc
    public func postAlarm(secondsBefore: TimeInterval, stopID: String, tripID: String, serviceDate: Int64, vehicleID: String, stopSequence: Int, userPushID: String, completion: CreateAlarmCompletionBlock?) -> CreateAlarmOperation {
        let request = CreateAlarmOperation.buildURLRequest(secondsBefore: secondsBefore, stopID: stopID, tripID: tripID, serviceDate: serviceDate, vehicleID: vehicleID, stopSequence: stopSequence, userPushID: userPushID, regionID: regionID, baseURL: baseURL, queryItems: defaultQueryItems)
        let operation = CreateAlarmOperation(urlRequest: request)
        operation.completionBlock = { [weak operation] in
            if let operation = operation { completion?(operation) }
        }

        networkQueue.add(operation)

        return operation
    }

    @discardableResult @objc
    public func deleteAlarm(url: URL, completion: DeleteAlarmCompletionBlock?) -> NetworkOperation {
        let request = NSMutableURLRequest(url: url)
        request.httpMethod = "DELETE"
        let op = NetworkOperation(urlRequest: request as URLRequest)
        op.completionBlock = { [weak op] in
            if let op = op { completion?(op) }
        }

        networkQueue.add(op)

        return op
    }

    //    /// Returns a PromiseWrapper that resolves to an array of `MatchingAgencyVehicle` objects,
    //    /// suitable for passing along to `requestVehicleTrip()`.
    //    ///
    //    /// - Parameter matching: A substring that must appear in all returned vehicles
    //    /// - Parameter region: The region from which to load all vehicle IDs
    //    /// - Returns: A `PromiseWrapper` that resolves to `[MatchingAgencyVehicle]`
    //    @objc public func requestVehicles(matching: String, in region: OBARegionV2) -> PromiseWrapper
    //
    //    /// Returns a PromiseWrapper that resolves to an OBATripDetailsV2 object.
    //    ///
    //    /// - Parameter vehicleID: The vehicle for which to retrieve trip details.
    //    /// - Returns: a PromiseWrapper that resolves to trip details.
    //    @objc public func requestVehicleTrip(_ vehicleID: String) -> PromiseWrapper
}
