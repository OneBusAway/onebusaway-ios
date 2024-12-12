//
//  ObacoAPIService.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import os.log

public protocol ObacoServiceDelegate: NSObjectProtocol {
    var shouldDisplayRegionalTestAlerts: Bool { get }
}

/// API service client for the Obaco (`alerts.onebusaway.org`) service.
///
/// Obaco provides services like weather, trip status, and alarms to the iOS app.
public actor ObacoAPIService: @preconcurrency APIService {
    public let configuration: APIServiceConfiguration
    public nonisolated let dataLoader: URLDataLoader

    public let logger = os.Logger(subsystem: "org.onebusaway.iphone", category: "ObacoAPIService")

    private let regionID: RegionIdentifier
    private weak var delegate: ObacoServiceDelegate?

    private var shouldDisplayRegionTestAlerts: Bool {
        guard let delegate else {
            return false
        }

        return delegate.shouldDisplayRegionalTestAlerts
    }

    public init(regionID: RegionIdentifier, delegate: ObacoServiceDelegate?, configuration: APIServiceConfiguration, dataLoader: URLDataLoader) {
        self.regionID = regionID
        self.delegate = delegate
        self.configuration = configuration
        self.dataLoader = dataLoader
    }

    /// - precondition: `configuration.regionIdentifier` must be non-nil.
    public init(_ configuration: APIServiceConfiguration, dataLoader: URLDataLoader) {
        guard let regionID = configuration.regionIdentifier else {
            preconditionFailure("Configuration must have a region identifier.")
        }

        self.regionID = regionID
        self.delegate = nil
        self.configuration = configuration
        self.dataLoader = dataLoader
    }

    private nonisolated func buildURL(path: String, queryItems: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)!
        components.appendPath(path)
        components.queryItems = configuration.defaultQueryItems + queryItems

        return components.url!
    }

    public nonisolated func getWeather() async throws -> WeatherForecast {
        let path = String(format: "/api/v1/regions/%d/weather.json", regionID)
        let url = buildURL(path: path)

        return try await getData(for: url, decodeAs: WeatherForecast.self, using: JSONDecoder.obacoServiceDecoder)
    }

    public nonisolated func postAlarm(minutesBefore: Int, arrivalDeparture: ArrivalDeparture, userPushID: String) async throws -> Alarm {
        return try await postAlarm(
            secondsBefore: TimeInterval(minutesBefore * 60),
            stopID: arrivalDeparture.stopID,
            tripID: arrivalDeparture.tripID,
            serviceDate: arrivalDeparture.serviceDate,
            vehicleID: arrivalDeparture.vehicleID,
            stopSequence: arrivalDeparture.stopSequence,
            userPushID: userPushID
        )
    }

    public nonisolated func postCreatePaymentIntent(
        donationAmountInCents: Int,
        recurring: Bool,
        name: String,
        email: String,
        testMode: Bool
    ) async throws -> PaymentIntentResponse {
        let url = buildURL(path: "/api/v1/payment_intents")
        let urlRequest = NSMutableURLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 10)
        urlRequest.httpMethod = "POST"

        let params: [String: Any] = [
            "donation_amount_in_cents": donationAmountInCents,
            "donation_frequency": recurring ? "recurring" : "onetime",
            "name": name,
            "email": email,
            "test_mode": testMode ? "1" : "0"
        ]

        let json = try JSONSerialization.data(withJSONObject: params, options: [])
        urlRequest.httpBody = json

        let (data, _) = try await data(for: urlRequest as URLRequest)
        return try JSONDecoder.obacoServiceDecoder.decode(PaymentIntentResponse.self, from: data)
    }

    public nonisolated func postAlarm(
        secondsBefore: TimeInterval,
        stopID: StopID,
        tripID: String,
        serviceDate: Date,
        vehicleID: String?,
        stopSequence: Int,
        userPushID: String
    ) async throws -> Alarm {
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

        let (data, _) = try await data(for: urlRequest as URLRequest)
        return try JSONDecoder.obacoServiceDecoder.decode(Alarm.self, from: data)
    }

    @discardableResult public nonisolated func deleteAlarm(url: URL) async throws -> (Data, URLResponse) {
        let request = NSMutableURLRequest(url: url)
        request.httpMethod = "DELETE"

        return try await data(for: request as URLRequest)
    }

    // MARK: - Vehicles
    public nonisolated func getVehicles(matching query: String) async throws -> [AgencyVehicle] {
        let apiPath = String(format: "/api/v1/regions/%d/vehicles", regionID)
        let url = buildURL(path: apiPath, queryItems: [URLQueryItem(name: "query", value: query)])

        return try await getData(for: url, decodeAs: [AgencyVehicle].self, using: JSONDecoder.obacoServiceDecoder)
    }

    // MARK: - Alerts
    public func getAlerts(agencies: [AgencyWithCoverage]) async throws -> [AgencyAlert] {
        let queryItems = self.shouldDisplayRegionTestAlerts ? [URLQueryItem(name: "test", value: "1")] : []
        let apiPath = String(format: "/api/v1/regions/%d/alerts.pb", regionID)
        let url = buildURL(path: apiPath, queryItems: queryItems)

        let (data, _) = try await getData(for: url)
        let message = try TransitRealtime_FeedMessage(serializedData: data)
        let entities = message.entity

        var qualifiedEntities: [TransitRealtime_FeedEntity] = []
        for entity in entities {
            let hasAlert = entity.hasAlert
            let alert = entity.alert
            let isAgencyWide = AgencyAlert.isAgencyWideAlert(alert: alert)

            if hasAlert && isAgencyWide {
                qualifiedEntities.append(entity)
            }
        }

        return qualifiedEntities.compactMap { (entity: TransitRealtime_FeedEntity) -> AgencyAlert? in
            return try? AgencyAlert(feedEntity: entity, agencies: agencies)
        }
    }
}
