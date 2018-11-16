//
//  Application.swift
//  OBAAppKit
//
//  Created by Aaron Brethorst on 11/15/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit
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

    @objc public let locationService: LocationService

    @objc public weak var delegate: ApplicationDelegate?

    @objc public convenience override init() {
        self.init(locationService: LocationService())
    }

    @objc public init(locationService: LocationService) {
        self.locationService = locationService
        

        super.init()

        self.locationService.addDelegate(self)
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
