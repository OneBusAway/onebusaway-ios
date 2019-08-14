//
//  AppConfig.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/16/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation

@objc(OBAAppConfig)
public class AppConfig: NSObject {

    let regionsBaseURL: URL
    let obacoBaseURL: URL?
    let apiKey: String
    let uuid: String
    let appVersion: String
    let queue: OperationQueue
    let userDefaults: UserDefaults
    let locationService: LocationService
    let analytics: Analytics?

    /// Convenience initializer that elides some properties.
    /// - Parameter regionsBaseURL: The base URL for the Regions server.
    /// - Parameter obacoBaseURL: The base URL for the Obaco server.
    /// - Parameter apiKey: Your API key for the REST API server.
    /// - Parameter uuid: A unique identifier for the client.
    /// - Parameter appVersion: The version of the app.
    /// - Parameter userDefaults: The user defaults object.
    /// - Parameter analytics: An object that conforms to the `Analytics` protocol.
    @objc public convenience init(
        regionsBaseURL: URL,
        obacoBaseURL: URL?,
        apiKey: String,
        uuid: String,
        appVersion: String,
        userDefaults: UserDefaults,
        analytics: Analytics?
    ) {
        self.init(
            regionsBaseURL: regionsBaseURL,
            obacoBaseURL: obacoBaseURL,
            apiKey: apiKey,
            uuid: uuid,
            appVersion: appVersion,
            userDefaults: userDefaults,
            analytics: analytics,
            queue: OperationQueue(),
            locationService: LocationService(locationManager: CLLocationManager())
        )
    }

    /// This initializer will let you specify all properties.
    /// - Parameter regionsBaseURL: The base URL for the Regions server.
    /// - Parameter obacoBaseURL: The base URL for the Obaco server.
    /// - Parameter apiKey: Your API key for the REST API server.
    /// - Parameter uuid: A unique identifier for the client.
    /// - Parameter appVersion: The version of the app.
    /// - Parameter userDefaults: The user defaults object.
    /// - Parameter analytics: An object that conforms to the `Analytics` protocol.
    /// - Parameter queue: An operation queue.
    /// - Parameter locationService: The location service object.
    @objc public init(
        regionsBaseURL: URL,
        obacoBaseURL: URL?,
        apiKey: String,
        uuid: String,
        appVersion: String,
        userDefaults: UserDefaults,
        analytics: Analytics?,
        queue: OperationQueue,
        locationService: LocationService
    ) {
        self.regionsBaseURL = regionsBaseURL
        self.obacoBaseURL = obacoBaseURL
        self.apiKey = apiKey
        self.uuid = uuid
        self.appVersion = appVersion
        self.userDefaults = userDefaults
        self.queue = queue
        self.locationService = locationService
        self.analytics = analytics
    }

    // MARK: - Regions

    private lazy var regionsAPIService = RegionsAPIService(baseURL: regionsBaseURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, networkQueue: queue)

    private lazy var regionsModelService = RegionsModelService(apiService: regionsAPIService, dataQueue: queue)

    lazy var regionsService = RegionsService(modelService: regionsModelService, locationService: locationService, userDefaults: userDefaults)

    // MARK: - Theme

    public var themeBundle: Bundle {
        return Bundle(for: AppConfig.self)
    }
}
