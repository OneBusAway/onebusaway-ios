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

@MainActor
public protocol ObacoServiceDelegate: NSObjectProtocol, Sendable {
    var shouldDisplayRegionalTestAlerts: Bool { get }
}

/// API service client for the Obaco (`alerts.onebusaway.org`) service.
///
/// Obaco provides services like weather, trip status, and alarms to the iOS app.
public actor ObacoAPIService: @preconcurrency APIService {
    public let configuration: APIServiceConfiguration
    public nonisolated let dataLoader: URLDataLoader

    public let logger = os.Logger(subsystem: "org.onebusaway.iphone", category: "ObacoAPIService")

    public nonisolated let regionID: RegionIdentifier
    private weak var delegate: ObacoServiceDelegate?

    private func shouldDisplayRegionTestAlerts() async -> Bool {
        guard let delegate else {
            return false
        }

        return await delegate.shouldDisplayRegionalTestAlerts
    }

    public init(regionID: RegionIdentifier, delegate: ObacoServiceDelegate?, configuration: APIServiceConfiguration, dataLoader: URLDataLoader) {
        assert(configuration.regionIdentifier == nil || configuration.regionIdentifier == regionID,
               "ObacoAPIService regionID must match its configuration's regionIdentifier")
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

    private nonisolated func buildURL(path: String, queryItems: [URLQueryItem] = []) async -> URL {
        let baseURL = configuration.baseURL
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.appendPath(path)
        components.queryItems = configuration.defaultQueryItems + queryItems

        return components.url!
    }

    public nonisolated func getWeather() async throws -> WeatherForecast {
        let path = String(format: "/api/v1/regions/%d/weather.json", regionID)
        let url = await buildURL(path: path)

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
        let url = await buildURL(path: "/api/v1/payment_intents")
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
        let url = await buildURL(path: String(format: "/api/v2/regions/%d/alarms", regionID))
        let urlRequest = NSMutableURLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 10)
        urlRequest.httpMethod = "POST"

        var params: [String: Any] = [
            "seconds_before": secondsBefore,
            "stop_id": stopID,
            "trip_id": tripID,
            "service_date": Int64(serviceDate.timeIntervalSince1970 * 1000),
            "stop_sequence": stopSequence,
            "user_push_id": userPushID,
            "operating_system": "ios"
        ]

        if let vehicleID = vehicleID {
            params["vehicle_id"] = vehicleID
        }

        stampAPNsSandboxFlag(&params)

        urlRequest.httpBody = NetworkHelpers.dictionary(toHTTPBodyData: params)

        let (data, _) = try await data(for: urlRequest as URLRequest)
        return try JSONDecoder.obacoServiceDecoder.decode(Alarm.self, from: data)
    }

    @discardableResult public nonisolated func deleteAlarm(url: URL) async throws -> (Data, URLResponse) {
        let request = NSMutableURLRequest(url: url)
        request.httpMethod = "DELETE"

        return try await data(for: request as URLRequest)
    }

    // MARK: - APNs Environment

    /// Stamps `apns_sandbox=1` onto a token-registering request in debug builds.
    ///
    /// A debug build is provisioned with the development APNs entitlement, so every token
    /// it registers — alarm, service-alert registration, or Live Activity — is only valid
    /// against the APNs sandbox host. The server persists the flag and routes that token's
    /// pushes through the sandbox; without it they bounce with `BadDeviceToken`. Omission
    /// means production: release builds send nothing, and on upsert-style endpoints the
    /// next unflagged registration clears any previously stored flag.
    ///
    /// Every Obaco request that registers a push token MUST call this — the flag was
    /// originally implemented per-endpoint and the endpoint that got missed shipped
    /// exactly that bug.
    ///
    /// Caveat: DEBUG is a proxy for the `aps-environment` entitlement, not the
    /// entitlement itself. A Release-configuration build signed with a development
    /// provisioning profile (e.g. Xcode's Profile action) holds a sandbox token but
    /// sends no flag, so its pushes bounce. The entitlement isn't runtime-readable,
    /// so this is the best available signal.
    private nonisolated func stampAPNsSandboxFlag(_ params: inout [String: Any]) {
        #if DEBUG
        params["apns_sandbox"] = "1"
        #endif
    }

    // MARK: - Push Registrations

    /// Registers — or refreshes — this device's APNs push token with the OBACloud server so the
    /// region's transit agencies can send service-alert push notifications to it.
    ///
    /// The server upserts on `(region, token)`, so create and update are the same call. A
    /// successful response is a bare `204 No Content`.
    ///
    /// - Parameters:
    ///   - token: The hex-encoded APNs device token.
    ///   - locale: The device's BCP-47 locale identifier (e.g. `"es-MX"`), used by the server to
    ///     pick the alert translation. Sent as-reported; the server does its own mapping.
    ///   - testDevice: Whether this device should receive "Test users only" sends. The server
    ///     resets an omitted value to `false` on every upsert, so it is always sent explicitly.
    ///   - description: Free text identifying a test device to OBACloud admins (e.g. `"Aaron's
    ///     iPhone 17"`). The server requires a non-blank value (≤255 chars) whenever
    ///     `testDevice` is `true`, and rejects the registration with a `422` if it's missing.
    ///     Sent only when non-nil and non-empty.
    public nonisolated func postPushRegistration(token: String, locale: String, testDevice: Bool, description: String?) async throws {
        let url = await buildURL(path: String(format: "/api/v2/regions/%d/push_registrations", regionID))
        let urlRequest = NSMutableURLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 10)
        urlRequest.httpMethod = "POST"

        var params: [String: Any] = [
            "token": token,
            "operating_system": "ios",
            "locale": locale,
            "test_device": testDevice ? "true" : "false"
        ]

        if let description, !description.isEmpty {
            params["description"] = description
        }

        stampAPNsSandboxFlag(&params)

        urlRequest.httpBody = NetworkHelpers.dictionary(toHTTPBodyData: params)

        _ = try await data(for: urlRequest as URLRequest)
    }

    /// Removes this device's push registration from the OBACloud server.
    ///
    /// The token travels as a query item, matching the server's contract.
    ///
    /// Answers `204` on success and `404` if the token was never registered — the latter
    /// throws `APIError.requestNotFound`. Callers treating "never registered" as success
    /// should catch that case specifically rather than discarding all errors.
    @discardableResult
    public nonisolated func deletePushRegistration(token: String) async throws -> (Data, URLResponse) {
        let url = await buildURL(
            path: String(format: "/api/v2/regions/%d/push_registrations", regionID),
            queryItems: [URLQueryItem(name: "token", value: token)])
        let request = NSMutableURLRequest(url: url)
        request.httpMethod = "DELETE"
        return try await data(for: request as URLRequest)
    }

    // MARK: - Live Activities

    private struct LiveActivityRegistrationResponse: Codable {
        let url: URL
    }

    /// Registers (or re-registers, on ActivityKit token rotation) a Live
    /// Activity push token with OBACloud. Returns the URL to DELETE when the
    /// activity ends locally. POST is an upsert keyed by `activityID`.
    public nonisolated func postLiveActivity(
        activityID: String,
        pushToken: String,
        stopID: StopID,
        routeShortName: String,
        tripHeadsign: String,
        tripID: String?,
        serviceDate: Date?,
        vehicleID: String?,
        stopSequence: Int?
    ) async throws -> URL {
        let url = await buildURL(path: String(format: "/api/v2/regions/%d/live_activities", regionID))
        let urlRequest = NSMutableURLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 10)
        urlRequest.httpMethod = "POST"

        var params: [String: Any] = [
            "activity_id": activityID,
            "push_token": pushToken,
            "stop_id": stopID,
            "route_short_name": routeShortName,
            "trip_headsign": tripHeadsign
        ]
        if let tripID { params["trip_id"] = tripID }
        if let serviceDate { params["service_date"] = Int64(serviceDate.timeIntervalSince1970 * 1000) }
        if let vehicleID { params["vehicle_id"] = vehicleID }
        if let stopSequence { params["stop_sequence"] = stopSequence }

        // The stakes are highest here: an unflagged Live Activity doesn't just go
        // quiet — its pushes bounce with BadDeviceToken and the server retires the
        // subscription outright.
        stampAPNsSandboxFlag(&params)

        urlRequest.httpBody = NetworkHelpers.dictionary(toHTTPBodyData: params)

        let (data, _) = try await data(for: urlRequest as URLRequest)
        return try JSONDecoder.obacoServiceDecoder.decode(LiveActivityRegistrationResponse.self, from: data).url
    }

    /// Unregisters a Live Activity subscription (the server sends no push; the
    /// activity already ended on-device).
    @discardableResult public nonisolated func deleteLiveActivity(url: URL) async throws -> (Data, URLResponse) {
        let request = NSMutableURLRequest(url: url)
        request.httpMethod = "DELETE"
        return try await data(for: request as URLRequest)
    }

    // MARK: - Vehicles
    public nonisolated func getVehicles(matching query: String) async throws -> [AgencyVehicle] {
        let apiPath = String(format: "/api/v1/regions/%d/vehicles", regionID)
        let url = await buildURL(path: apiPath, queryItems: [URLQueryItem(name: "query", value: query)])

        return try await getData(for: url, decodeAs: [AgencyVehicle].self, using: JSONDecoder.obacoServiceDecoder)
    }

    // MARK: - Alerts
    public func getAlerts(agencies: [AgencyWithCoverage]) async throws -> [AgencyAlert] {
        let queryItems = await self.shouldDisplayRegionTestAlerts() ? [URLQueryItem(name: "test", value: "1")] : []
        let apiPath = String(format: "/api/v1/regions/%d/alerts.pb", regionID)
        let url = await buildURL(path: apiPath, queryItems: queryItems)

        let (data, _) = try await getData(for: url)
        let message = try TransitRealtime_FeedMessage(serializedBytes: data)
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
            do {
                return try AgencyAlert(feedEntity: entity, agencies: agencies)
            } catch {
                logger.error("Dropped alert \(entity.id, privacy: .public) from regional alerts feed: \(error, privacy: .public)")
                return nil
            }
        }
    }
}
