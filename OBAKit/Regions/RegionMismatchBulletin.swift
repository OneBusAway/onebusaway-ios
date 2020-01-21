//
//  RegionMismatchBulletin.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/21/20.
//

import Foundation
import BLTNBoard
import OBAKitCore

/// Displays a modal card UI that informs the user about a mismatch between their physical location and current `Region`.
class RegionMismatchBulletin: NSObject {
    private let bulletinManager: BLTNItemManager
    private let page: BLTNPageItem
    private let application: Application

    init?(application: Application) {
        guard
            let currentRegion = application.regionsService.currentRegion,
            let physicalRegion = application.regionsService.physicallyLocatedRegion
        else { return nil }

        self.application = application

        page = BLTNPageItem(title: OBALoc("region_mismatch_bulletin.title", value: "Change Region?", comment: "Alert title shown when there is a mismatch between the user location and selected region."))

        let bodyFormat = OBALoc("region_mismatch_bulletin.body_fmt", value: "Your region is set to %@, but you appear to be in %@.", comment: "Formatted alert body shown when there is a mismatch between the user location and selected region. e.g. 'Your region is set to Puget Sound, but you appear to be in San Diego.'")
        page.descriptionText = String(format: bodyFormat, currentRegion.name, physicalRegion.name)

        bulletinManager = BLTNItemManager(rootItem: page)

        super.init()

        let actionFmt = OBALoc("region_mismatch_bulletin.change_region_button_fmt", value: "Change to %@", comment: "A button on the region mismatch alert that changes the user's current region. e.g. 'Change to San Diego'")
        page.actionButtonTitle = String(format: actionFmt, physicalRegion.name)
        page.actionHandler = { [weak self] _ in
            guard let self = self else { return }

            self.application.regionsService.currentRegion = physicalRegion
            self.application.regionsService.automaticallySelectRegion = true
            self.bulletinManager.dismissBulletin()
        }

        let altFmt = OBALoc("region_mismatch_bulletin.update_map_button_fmt", value: "Show %@ on the map", comment: "A button on the region mismatch alert that updates the map's current location to be the specified region. e.g. 'Show Puget Sound on the map'")
        page.alternativeButtonTitle = String(format: altFmt, currentRegion.name)
        page.alternativeHandler = { [weak self] _ in
            guard let self = self else { return }

            self.application.mapRegionManager.mapView.visibleMapRect = currentRegion.serviceRect
            self.bulletinManager.dismissBulletin()
        }
    }

    func show(in app: UIApplication) {
        bulletinManager.showBulletin(in: app)
    }
}
