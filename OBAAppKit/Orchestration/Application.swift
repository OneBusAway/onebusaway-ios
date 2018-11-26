//
//  Application.swift
//  OBAAppKit
//
//  Created by Aaron Brethorst on 11/15/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit
import OBANetworkingKit
import OBALocationKit
import CoreLocation

@objc(OBAApplicationDelegate)
public protocol ApplicationDelegate {

    /// This method is called when the delegate should reload the `rootViewController`
    /// of the app's
    @objc func applicationReloadRootInterface(_ app: Application)
}

@objc(OBAApplication)
public class Application: NSObject {

    /// App configuration parameters: API keys, region server, user UUID, and other
    /// configuration values.
    private let config: AppConfig

    /// Provides access to the user's location and heading.
    @objc public let locationService: LocationService

    /// Responsible for managing `Region`s and determining the correct `Region` for the user.
    @objc public let regionsService: RegionsService

    @objc public private(set) var restAPIModelService: RESTAPIModelService?

    @objc public private(set) var theme: Theme

    @objc public weak var delegate: ApplicationDelegate?

    @objc public init(config: AppConfig) {
        self.config = config
        self.locationService = config.locationService
        self.regionsService = config.regionsService

        self.theme = Theme(bundle: config.themeBundle, traitCollection: nil)

        super.init()

        self.locationService.addDelegate(self)
        self.regionsService.addDelegate(self)

        if self.locationService.isLocationUseAuthorized {
            self.locationService.startUpdates()
        }

        refreshRESTAPIModelService()
    }

    private func refreshRESTAPIModelService() {
        guard let region = regionsService.currentRegion else {
            return
        }

        let apiService = RESTAPIService(baseURL: region.OBABaseURL, apiKey: config.apiKey, uuid: config.uuid, appVersion: config.appVersion, networkQueue: config.queue)
        restAPIModelService = RESTAPIModelService(apiService: apiService, dataQueue: config.queue)
    }

    // MARK: - App Launch State Management

    /// True when the app should show an interstitial location service permission
    /// request user interface. Meant to be called on app launch to determine
    /// which piece of UI should be shown initially.
    @objc public var showPermissionPromptUI: Bool {
        return locationService.canRequestAuthorization
    }
}

extension Application: RegionsServiceDelegate {
    public func regionsServiceUnableToSelectRegion(_ service: RegionsService) {
        // abxoxo - todo!
    }

    public func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        refreshRESTAPIModelService()
    }
}

extension Application: LocationServiceDelegate {
    public func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus) {
        delegate?.applicationReloadRootInterface(self)
    }
}
