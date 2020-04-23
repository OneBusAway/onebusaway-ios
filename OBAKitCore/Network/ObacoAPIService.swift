//
//  ObacoAPIService.swift
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
public class ObacoAPIService: APIService {

    private let regionID: Int

    public init(baseURL: URL, apiKey: String, uuid: String, appVersion: String, regionID: Int, networkQueue: OperationQueue, delegate: ObacoServiceDelegate?) {
        self.regionID = regionID
        self.delegate = delegate
        super.init(baseURL: baseURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, networkQueue: networkQueue)
    }

    private func buildOperation<T>(type: T.Type, URL: URL) -> DecodableOperation<T> where T: Decodable {
        return DecodableOperation(type: type, decoder: JSONDecoder.obacoServiceDecoder, URL: URL)
    }

    // MARK: - Delegate

    public weak var delegate: ObacoServiceDelegate?

    private var shouldDisplayRegionalTestAlerts: Bool {
        guard let delegate = delegate else {
            return false
        }

        return delegate.shouldDisplayRegionalTestAlerts
    }

    // MARK: - URL Construction

    private func buildURL(path: String, queryItems: [URLQueryItem]? = nil) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.appendPath(path)
        components.queryItems = defaultQueryItems + (queryItems ?? [])

        return components.url!
    }

    // MARK: - Weather

    public func getWeather() -> DecodableOperation<WeatherForecast> {
        let apiPath = String(format: "/api/v1/regions/%d/weather.json", regionID)
        let url = buildURL(path: apiPath)
        let operation = buildOperation(type: WeatherForecast.self, URL: url)
        enqueueOperation(operation)

        return operation
    }

    // MARK: - Alarms

    public func postAlarm(minutesBefore: Int, arrivalDeparture: ArrivalDeparture, userPushID: String) -> DecodableOperation<Alarm> {
        return postAlarm(
            secondsBefore: TimeInterval(minutesBefore * 60),
            stopID: arrivalDeparture.stopID,
            tripID: arrivalDeparture.tripID,
            serviceDate: arrivalDeparture.serviceDate,
            vehicleID: arrivalDeparture.vehicleID,
            stopSequence: arrivalDeparture.stopSequence,
            userPushID: userPushID
        )
    }

    public func postAlarm(
        secondsBefore: TimeInterval,
        stopID: StopID,
        tripID: String,
        serviceDate: Date,
        vehicleID: String?,
        stopSequence: Int,
        userPushID: String
    ) -> DecodableOperation<Alarm> {
        let url = buildURL(path: String(format: "/api/v1/regions/%d/alarms", regionID))
        let urlRequest = NSMutableURLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 10)
        urlRequest.httpMethod = "POST"

        var params: [String: Any] = [
            "seconds_before": secondsBefore,
            "stop_id": stopID,
            "trip_id": tripID,
            "service_date": Int64(serviceDate.timeIntervalSince1970 * 1000),
            "stop_sequence": stopSequence,
            "user_push_id": userPushID
        ]

        if let vehicleID = vehicleID {
            params["vehicle_id"] = vehicleID
        }
        urlRequest.httpBody = NetworkHelpers.dictionary(toHTTPBodyData: params)

        let operation = DecodableOperation(type: Alarm.self, decoder: JSONDecoder.obacoServiceDecoder, request: urlRequest as URLRequest)
        enqueueOperation(operation)
        return operation
    }

    @discardableResult public func deleteAlarm(url: URL) -> NetworkOperation {
        let request = NSMutableURLRequest(url: url)
        request.httpMethod = "DELETE"
        let op = NetworkOperation(request: request as URLRequest)
        enqueueOperation(op)
        return op
    }

    // MARK: - Vehicles

    public func getVehicles(matching query: String) -> DecodableOperation<[VehicleStatus]> {
        let apiPath = String(format: "/api/v1/regions/%d/vehicles", regionID)
        let url = buildURL(path: apiPath, queryItems: [URLQueryItem(name: "query", value: query)])
        let op = buildOperation(type: [VehicleStatus].self, URL: url)
        enqueueOperation(op)
        return op
    }

    // MARK: - Alerts

    public func getAlerts(agencies: [AgencyWithCoverage]) -> AgencyAlertsOperation {
        let queryItems = shouldDisplayRegionalTestAlerts ? [URLQueryItem(name: "test", value: "1")] : nil
        let apiPath = String(format: "/api/v1/regions/%d/alerts.pb", regionID)
        let url = buildURL(path: apiPath, queryItems: queryItems)

        let op = AgencyAlertsOperation(agencies: agencies, URL: url)
        enqueueOperation(op)

        return op
    }
}
