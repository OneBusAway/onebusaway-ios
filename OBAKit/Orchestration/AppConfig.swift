//
//  AppConfig.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import OBAKitCore
import Hyperconnectivity

@objc(OBAAppConfig)
public class AppConfig: CoreAppConfig {

    let analytics: Analytics?
    @objc public var pushServiceProvider: PushServiceProvider?

    /// Convenience initializer that pulls from the host application's main `Bundle`.
    /// - Parameter appBundle: The application `Bundle` from which initialization properties will be extracted.
    /// - Parameter userDefaults: The user defaults object.
    /// - Parameter analytics: An object that conforms to the `Analytics` protocol.
    @objc public convenience init(
        appBundle: Bundle,
        userDefaults: UserDefaults,
        analytics: Analytics?
    ) {
        self.init(
            regionsBaseURL: appBundle.regionsServerBaseAddress,
            apiKey: appBundle.restServerAPIKey!,
            appVersion: appBundle.appVersion,
            userDefaults: userDefaults,
            analytics: analytics,
            queue: OperationQueue(),
            locationService: LocationService(userDefaults: userDefaults, locationManager: CLLocationManager()),
            bundledRegionsFilePath: appBundle.bundledRegionsFilePath!,
            regionsAPIPath: appBundle.regionsServerAPIPath,
            dataLoader: URLSession.shared
        )
    }

    /// This initializer will let you specify all properties.
    /// - Parameter regionsBaseURL: The base URL for the Regions server.
    /// - Parameter apiKey: Your API key for the REST API server.
    /// - Parameter appVersion: The version of the app.
    /// - Parameter userDefaults: The user defaults object.
    /// - Parameter analytics: An object that conforms to the `Analytics` protocol.
    /// - Parameter queue: An operation queue.
    /// - Parameter locationService: The location service object.
    /// - Parameter bundledRegionsFilePath: The path to the `regions.json` file in the app bundle.
    /// - Parameter regionsAPIPath: The API Path on the Regions server to the regions file.
    public init(
        regionsBaseURL: URL?,
        apiKey: String,
        appVersion: String,
        userDefaults: UserDefaults,
        analytics: Analytics?,
        queue: OperationQueue,
        locationService: LocationService,
        bundledRegionsFilePath: String,
        regionsAPIPath: String?,
        dataLoader: URLDataLoader
    ) {
        self.analytics = analytics
        super.init(
            regionsBaseURL: regionsBaseURL,
            apiKey: apiKey,
            appVersion: appVersion,
            userDefaults: userDefaults,
            queue: queue,
            locationService: locationService,
            bundledRegionsFilePath: bundledRegionsFilePath,
            regionsAPIPath: regionsAPIPath,
            dataLoader: dataLoader
        )
    }
}
