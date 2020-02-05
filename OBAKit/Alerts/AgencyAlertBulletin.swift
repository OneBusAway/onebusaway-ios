//
//  AgencyAlertBulletin.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 12/30/19.
//

import Foundation
import BLTNBoard
import OBAKitCore

/// Displays a modal card UI that informs the user about high severity `AgencyAlert`s.
class AgencyAlertBulletin: NSObject {
    private let bulletinManager: BLTNItemManager

    private let alertPage: BLTNPageItem

    public var showMoreInformationHandler: ((URL) -> Void)?

    init?(agencyAlert: AgencyAlert, locale: Locale) {
        guard let title = agencyAlert.titleForLocale(locale) else {
            return nil
        }

        alertPage = BLTNPageItem(title: title)
        alertPage.descriptionText = agencyAlert.bodyForLocale(locale)

        let squircleRenderer = ImageBadgeRenderer(fillColor: .white, backgroundColor: ThemeColors.shared.errorColor)
        alertPage.image = squircleRenderer.drawImageOnRoundedRect(Icons.errorOutline)

        bulletinManager = BLTNItemManager(rootItem: alertPage)

        super.init()

        if let url = agencyAlert.URLForLocale(locale) {
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
