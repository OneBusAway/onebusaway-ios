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
    /// Presents the bulletin above the topmost view controller of the application's key window.
    ///
    /// Use this instead of `showBulletin(in:)`: that method presents inside a `UIWindow`
    /// it creates without a `windowScene`, and iOS never displays such a window in a
    /// scene-based app, so the bulletin silently fails to appear.
    func show(in application: UIApplication) {
        guard
            !isShowingBulletin,
            let topViewController = application.keyWindowFromScene?.topViewController
        else {
            return
        }

        showBulletin(above: topViewController)
    }
}
