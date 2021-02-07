//
//  AgencyAlertBulletin.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import BLTNBoard
import OBAKitCore
import UIKit

/// Displays a modal card UI that informs the user about high severity `AgencyAlert`s.
class AgencyAlertBulletin: NSObject {
    private let bulletinManager: BLTNItemManager

    private let alertPage: ThemedBulletinPage

    public var showMoreInformationHandler: ((URL) -> Void)?

    init?(agencyAlert: AgencyAlert, locale: Locale) {
        guard let title = agencyAlert.title(forLocale: locale) else {
            return nil
        }

        alertPage = ThemedBulletinPage(title: title)
        alertPage.descriptionText = agencyAlert.body(forLocale: locale)

        let squircleRenderer = ImageBadgeRenderer(fillColor: .white, backgroundColor: ThemeColors.shared.errorColor)
        alertPage.image = squircleRenderer.drawImageOnRoundedRect(Icons.errorOutline)

        bulletinManager = BLTNItemManager(rootItem: alertPage)

        super.init()

        if let url = agencyAlert.url(forLocale: locale) {
            alertPage.actionButtonTitle = Strings.learnMore
            alertPage.actionHandler = { [weak self] _ in
                guard let self = self else { return }
                self.showMoreInformationHandler?(url)
            }
        }

        alertPage.alternativeButtonTitle = Strings.dismiss
        alertPage.alternativeHandler = { [weak self] _ in
            self?.bulletinManager.dismissBulletin()
        }
    }

    func show(in application: UIApplication) {
        bulletinManager.showBulletin(in: application)
    }
}
