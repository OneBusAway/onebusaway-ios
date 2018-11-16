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

    /// Provides access to the user's location and heading.
    @objc public let locationService: LocationService

    /// Responsible for managing `Region`s and determining the correct `Region` for the user.
    @objc public let regionsService: RegionsService

    @objc public weak var delegate: ApplicationDelegate?

    @objc public init(config: AppConfig) {
        self.locationService = config.locationService
        self.regionsService = config.regionsService

        super.init()

        self.locationService.addDelegate(self)

        if self.locationService.isLocationUseAuthorized {
            self.locationService.startUpdates()
        }
    }

    // MARK: - App Launch State Management

    /// True when the app should show an interstitial location service permission
    /// request user interface. Meant to be called on app launch to determine
    /// which piece of UI should be shown initially.
    @objc public var showPermissionPromptUI: Bool {
        return locationService.canRequestAuthorization
    }
}

extension Application: LocationServiceDelegate {
    public func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus) {
        delegate?.applicationReloadRootInterface(self)
    }
}
