//
//  ThemedBulletinPage.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 7/28/20.
//

import UIKit
import OBAKitCore
import BLTNBoard

/// A `BLTNPageItem` subclass that applies the app's brand colors to the buttons and image view.
class ThemedBulletinPage: BLTNPageItem {

    override init(title: String) {
        super.init(title: title)
        customizeAppearance()
    }

    private func customizeAppearance() {
        appearance.actionButtonColor = ThemeColors.shared.brand
        appearance.alternativeButtonTitleColor = ThemeColors.shared.brand
        appearance.imageViewTintColor = ThemeColors.shared.brand
    }
}

extension BLTNItemManager {
    /// Presents the bulletin in a dedicated overlay `UIWindow` attached to the
    /// active scene.
    ///
    /// Avoid `showBulletin(in:)` (BLTNBoard's built-in): it creates a `UIWindow`
    /// without a `windowScene`, which iOS won't display in a scene-based app.
    /// Avoid presenting from `keyWindowFromScene?.topViewController` directly:
    /// in the SwiftUI map-panel experience that walk lands inside the home
    /// sheet's hosting controller, and `UISheetPresentationController` clamps
    /// modal presentations to the sheet's current detent — the bulletin then
    /// renders inside the collapsed sheet's ~80pt strip.
    ///
    /// `rootItem` is the item passed to `BLTNItemManager.init(rootItem:)`; it
    /// has to be supplied here because the manager keeps its reference private,
    /// and we hook its `dismissalHandler` to retire the overlay window.
    func show(in application: UIApplication, rootItem: BLTNItem) {
        guard
            !isShowingBulletin,
            let scene = application.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else {
            return
        }

        let host = BulletinOverlayWindow.shared.install(in: scene, rootItem: rootItem)
        showBulletin(above: host)
    }
}
