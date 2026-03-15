//
//  CoreAppConfig.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

/// This is an application configuration object suitable for using in an
/// extension, non-graphical application, or basically anything that isn't
/// a traditional UIKit iOS app.
///
/// - Note: If you are building a traditional UIKit-based iOS app, check out
///         `OBAKit.AppConfig` instead. It offers additional features you'll
///         likely want to use in your app.
@objc(OBACoreAppConfig)
open class CoreAppConfig: NSObject {
    public let regionsBaseURL: URL?
    public let regionsAPIPath: String?
    public let apiKey: String
    public let appVersion: String
    public let queue: OperationQueue
    public let userDefaults: UserDefaults
    public let locationService: LocationService
    public let bundledRegionsFilePath: String
    public let dataLoader: URLDataLoader

    /// The name of a fixed region to auto-select at launch, bypassing the region picker.
    public let fixedRegionName: String?

    /// The OBA base URL for a fixed region, used as a fallback when `fixedRegionName` doesn't match.
    public let fixedRegionOBABaseURL: URL?

    /// Convenience initializer that pulls from the host application's main `Bundle`.
    /// - Parameter appBundle: The application `Bundle` from which initialization properties will be extracted.
    /// - Parameter userDefaults: The user defaults object.
    /// - Parameter bundledRegionsFilePath: The path to the `regions.json` file in the app bundle.
    @objc public convenience init(
        appBundle: Bundle,
        userDefaults: UserDefaults,
        bundledRegionsFilePath: String
    ) {
        self.init(
            regionsBaseURL: appBundle.regionsServerBaseAddress!,
            apiKey: appBundle.restServerAPIKey!,
            appVersion: appBundle.appVersion,
            userDefaults: userDefaults,
            queue: OperationQueue(),
            locationService: LocationService(userDefaults: userDefaults, locationManager: CLLocationManager()),
            bundledRegionsFilePath: bundledRegionsFilePath,
            regionsAPIPath: appBundle.regionsServerAPIPath!,
            dataLoader: URLSession.shared,
            fixedRegionName: appBundle.fixedRegionName,
            fixedRegionOBABaseURL: appBundle.fixedRegionOBABaseURL
        )
    }

    /// This initializer will let you specify all properties.
    /// - Parameter regionsBaseURL: The base URL for the Regions server.
    /// - Parameter apiKey: Your API key for the REST API server.
    /// - Parameter appVersion: The version of the app.
    /// - Parameter userDefaults: The user defaults object.
    /// - Parameter queue: An operation queue.
    /// - Parameter locationService: The location service object.
    /// - Parameter bundledRegionsFilePath: The path to the `regions.json` file in the app bundle.
    /// - Parameter regionsAPIPath: The API Path on the Regions server to the regions file.
    public init(
        regionsBaseURL: URL?,
        apiKey: String,
        appVersion: String,
        userDefaults: UserDefaults,
        queue: OperationQueue,
        locationService: LocationService,
        bundledRegionsFilePath: String,
        regionsAPIPath: String?,
        dataLoader: URLDataLoader,
        fixedRegionName: String? = nil,
        fixedRegionOBABaseURL: URL? = nil
    ) {
        self.regionsBaseURL = regionsBaseURL
        self.apiKey = apiKey
        self.appVersion = appVersion
        self.queue = queue
        self.userDefaults = userDefaults
        self.locationService = locationService
        self.bundledRegionsFilePath = bundledRegionsFilePath
        self.regionsAPIPath = regionsAPIPath
        self.dataLoader = dataLoader
        self.fixedRegionName = fixedRegionName
        self.fixedRegionOBABaseURL = fixedRegionOBABaseURL
    }
}
