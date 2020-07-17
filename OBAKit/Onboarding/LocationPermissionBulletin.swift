//
//  LocationPermissionBulletin.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import BLTNBoard
import OBAKitCore

// MARK: - LocationPermissionItem

class LocationPermissionItem: BLTNPageItem, LocationServiceDelegate {
    private let locationService: LocationService
    private let completion: VoidBlock

    init(locationService: LocationService, completion: @escaping VoidBlock) {
        self.locationService = locationService
        self.completion = completion

        super.init(title: OBALoc("location_permission_bulletin.title", value: "Welcome!", comment: "Title of the alert that appears to request your location."))

        self.locationService.addDelegate(self)

        isDismissable = false

        let squircleRenderer = ImageBadgeRenderer(fillColor: .white, backgroundColor: ThemeColors.shared.brand)
        image = squircleRenderer.drawImageOnRoundedRect(Icons.nearMe)

        descriptionText = OBALoc("location_permission_bulletin.description_text", value: "Please allow the app to access your location to make it easier to find your transit stops.", comment: "Description of why we need location services")

        actionButtonTitle = OBALoc("location_permission_bulletin.buttons.give_permission", value: "Allow Access", comment: "This button signals the user is willing to grant location access to the app.")

        alternativeButtonTitle = OBALoc("location_permission_bulletin.buttons.deny_permission", value: "Maybe Later", comment: "This button rejects the application's request to see the user's location.")

        actionHandler = { [weak self] _ in
            self?.locationService.requestInUseAuthorization()
        }

        alternativeHandler = { [weak self] _ in
            guard let self = self else { return }
            self.locationService.canPromptUserForPermission = false
            self.completion()
        }
    }

    func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus) {
        self.completion()
    }
}
