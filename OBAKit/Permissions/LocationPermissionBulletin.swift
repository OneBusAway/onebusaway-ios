//
//  LocationPermissionBulletin.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 12/21/19.
//

import Foundation
import BLTNBoard
import OBAKitCore

/// Displays a modal 'card' UI that prompts the user for access to their location.
class LocationPermissionBulletin: NSObject {
    private let bulletinManager: BLTNItemManager

    private let introPage: BLTNPageItem

    private let locationService: LocationService

    init(locationService: LocationService) {
        introPage = BLTNPageItem(title: NSLocalizedString("location_permission_bulletin.title", value: "Welcome!", comment: "Title of the alert that appears to request your location."))
        bulletinManager = BLTNItemManager(rootItem: introPage)

        self.locationService = locationService

        super.init()

        introPage.isDismissable = false
        introPage.image = Icons.nearMe

        introPage.descriptionText = NSLocalizedString("location_permission_bulletin.description_text", value: "Please allow the app to access your location to make it easier to find your transit stops.", comment: "Description of why we need location services")

        introPage.actionButtonTitle = NSLocalizedString("location_permission_bulletin.buttons.give_permission", value: "Allow Access", comment: "This button signals the user is willing to grant location access to the app.")
        introPage.actionHandler = { [weak self] _ in
            self?.bulletinManager.dismissBulletin()
            self?.locationService.requestInUseAuthorization()
        }

        introPage.alternativeButtonTitle = NSLocalizedString("location_permission_bulletin.buttons.deny_permission", value: "Maybe Later", comment: "This button rejects the application's request to see the user's location.")
        introPage.alternativeHandler = { [weak self] _ in
            self?.locationService.canPromptUserForPermission = false
            self?.bulletinManager.dismissBulletin()
        }
    }

    func show(in application: UIApplication) {
        bulletinManager.showBulletin(in: application)
    }
}
