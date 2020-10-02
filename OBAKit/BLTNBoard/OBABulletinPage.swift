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
