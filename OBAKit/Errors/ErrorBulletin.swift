//
//  ErrorBulletin.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 2/4/20.
//

import Foundation
import BLTNBoard
import OBAKitCore

/// Displays a modal card UI that presents an error.
class ErrorBulletin: NSObject {
    private let bulletinManager: BLTNItemManager
    private let page: BLTNPageItem
    private let application: Application

    init(application: Application, message: String, image: UIImage? = nil, title: String? = nil) {
        self.application = application

        page = BLTNPageItem(title: title ?? Strings.error)

        page.descriptionText = message

        page.isDismissable = false
        page.image = image ?? Icons.errorOutline

        bulletinManager = BLTNItemManager(rootItem: page)

        super.init()

        page.actionButtonTitle = Strings.dismiss
        page.actionHandler = { [weak self] _ in
            guard let self = self else { return }
            self.bulletinManager.dismissBulletin()
        }
    }

    func show(in app: UIApplication) {
        bulletinManager.showBulletin(in: app)
    }
}
