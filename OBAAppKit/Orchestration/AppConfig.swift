//
//  AppConfig.swift
//  OBAAppKit
//
//  Created by Aaron Brethorst on 11/16/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation
import OBANetworkingKit
import OBALocationKit

@objc(OBAAppConfig)
public class AppConfig: NSObject {

    let regionsBaseURL: URL
    let apiKey: String
    let uuid: String
    let appVersion: String
    let queue: OperationQueue

    @objc public convenience init(regionsBaseURL: URL, apiKey: String, uuid: String, appVersion: String) {
        self.init(regionsBaseURL: regionsBaseURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, queue: OperationQueue())
    }

    @objc public init(regionsBaseURL: URL, apiKey: String, uuid: String, appVersion: String, queue: OperationQueue) {
        self.regionsBaseURL = regionsBaseURL
        self.apiKey = apiKey
        self.uuid = uuid
        self.appVersion = appVersion
        self.queue = queue
    }

    // MARK: - Derived Properties

    private lazy var regionsAPIService = RegionsAPIService(baseURL: regionsBaseURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, networkQueue: queue)

    private lazy var regionsModelService = RegionsModelService(apiService: regionsAPIService, dataQueue: queue)

    public lazy var locationService = LocationService(locationManager: CLLocationManager())

    public lazy var regionsService = RegionsService(modelService: regionsModelService, locationService: locationService)
}
