//
//  ObacoService.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/11/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CocoaLumberjackSwift

public protocol ObacoServiceDelegate: NSObjectProtocol {
    var shouldDisplayRegionalTestAlerts: Bool { get }
}

/// API service client for the Obaco (`alerts.onebusaway.org`) service.
///
/// Obaco provides services like weather, trip status, and alarms to the iOS app.
public class ObacoService: APIService {

    private let regionID: String

    public init(baseURL: URL, apiKey: String, uuid: String, appVersion: String, regionID: String, networkQueue: OperationQueue, delegate: ObacoServiceDelegate?) {
        self.regionID = regionID
        self.delegate = delegate
        super.init(baseURL: baseURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, networkQueue: networkQueue)
    }

    // MARK: - Delegate

    public weak var delegate: ObacoServiceDelegate?

    private var shouldDisplayRegionalTestAlerts: Bool {
        guard let delegate = delegate else {
            return false
        }

        return delegate.shouldDisplayRegionalTestAlerts
    }

    // MARK: - Weather

    public func getWeather() -> WeatherOperation {
        let url = WeatherOperation.buildURL(regionID: regionID, baseURL: baseURL, queryItems: defaultQueryItems)
        let request = WeatherOperation.buildRequest(for: url)
        let operation = WeatherOperation(request: request)
        enqueueOperation(operation)

        return operation
    }

    // MARK: - Alarms

    public func postAlarm(
        secondsBefore: TimeInterval,
        stopID: StopID,
        tripID: String,
        serviceDate: Date,
        vehicleID: String?,
        stopSequence: Int,
        userPushID: String
    ) -> CreateAlarmOperation {
        let request = CreateAlarmOperation.buildURLRequest(
            secondsBefore: secondsBefore,
            stopID: stopID,
            tripID: tripID,
            serviceDate: serviceDate,
            vehicleID: vehicleID,
            stopSequence: stopSequence,
            userPushID: userPushID,
            regionID: regionID,
            baseURL: baseURL,
            queryItems: defaultQueryItems
        )

        let operation = CreateAlarmOperation(request: request)
        enqueueOperation(operation)

        return operation
    }

    public func deleteAlarm(url: URL) -> NetworkOperation {
        let request = NSMutableURLRequest(url: url)
        request.httpMethod = "DELETE"

        let op = NetworkOperation(request: request as URLRequest)
        enqueueOperation(op)

        return op
    }

    // MARK: - Vehicles

    public func getVehicles(matching query: String) -> MatchingVehiclesOperation {
        let url = MatchingVehiclesOperation.buildURL(query: query, regionID: regionID, baseURL: baseURL, queryItems: defaultQueryItems)
        let request = MatchingVehiclesOperation.buildRequest(for: url)
        let operation = MatchingVehiclesOperation(request: request)
        enqueueOperation(operation)

        return operation
    }

    // MARK: - Alerts

    public func getAlerts() -> RegionalAlertsOperation {
        var queryItems = defaultQueryItems

        if shouldDisplayRegionalTestAlerts {
            queryItems.append(URLQueryItem(name: "test", value: "1"))
        }

        let url = RegionalAlertsOperation.buildObacoURL(regionID: regionID, baseURL: baseURL, queryItems: queryItems)
        let request = RegionalAlertsOperation.buildRequest(for: url)
        let operation = RegionalAlertsOperation(request: request)
        enqueueOperation(operation)

        return operation
    }

    private func enqueueOperation(_ operation: NetworkOperation) {
        networkQueue.addOperation(operation)
        DDLogInfo("Enqueuing URL: \(operation.request.url!.absoluteString)")
    }
}
