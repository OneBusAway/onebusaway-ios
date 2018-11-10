//
//  ObacoService.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/11/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

@objc(OBAObacoService)
public class ObacoService: APIService {

    private let regionID: String

    @objc public init(baseURL: URL, apiKey: String, uuid: String, appVersion: String, regionID: String, networkQueue: OperationQueue) {
        self.regionID = regionID
        super.init(baseURL: baseURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, networkQueue: networkQueue)
    }

    // MARK: - Weather

    @objc public func getWeather(regionID: String) -> WeatherOperation {
        let url = WeatherOperation.buildURL(regionID: regionID, baseURL: baseURL, queryItems: defaultQueryItems)
        let operation = WeatherOperation(url: url)
        networkQueue.addOperation(operation)

        return operation
    }

    // MARK: - Alarms

    @objc public func postAlarm(secondsBefore: TimeInterval, stopID: String, tripID: String, serviceDate: Int64, vehicleID: String, stopSequence: Int, userPushID: String) -> CreateAlarmOperation {
        let request = CreateAlarmOperation.buildURLRequest(secondsBefore: secondsBefore, stopID: stopID, tripID: tripID, serviceDate: serviceDate, vehicleID: vehicleID, stopSequence: stopSequence, userPushID: userPushID, regionID: regionID, baseURL: baseURL, queryItems: defaultQueryItems)

        let operation = CreateAlarmOperation(urlRequest: request)
        networkQueue.addOperation(operation)

        return operation
    }

    @objc public func deleteAlarm(url: URL) -> NetworkOperation {
        let request = NSMutableURLRequest(url: url)
        request.httpMethod = "DELETE"

        let op = NetworkOperation(urlRequest: request as URLRequest)
        networkQueue.addOperation(op)

        return op
    }

    @objc public func getVehicles(matching query: String) -> MatchingVehiclesOperation {
        let url = MatchingVehiclesOperation.buildURL(query: query, regionID: regionID, baseURL: baseURL, queryItems: defaultQueryItems)

        let operation = MatchingVehiclesOperation(url: url)
        networkQueue.addOperation(operation)

        return operation
    }
}
