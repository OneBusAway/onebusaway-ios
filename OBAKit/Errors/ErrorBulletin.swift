//
//  ErrorBulletin.swift
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

/// Displays a modal card UI that presents an error.
class ErrorBulletin: NSObject {
    private let bulletinManager: BLTNItemManager
    private let page: ThemedBulletinPage
    private let application: Application

    init(application: Application, message: String, image: UIImage? = nil, title: String? = nil) {
        self.application = application

        page = ThemedBulletinPage(title: title ?? Strings.error)

        page.descriptionText = message

        page.isDismissable = false

        let squircleRenderer = ImageBadgeRenderer(fillColor: .white, backgroundColor: ThemeColors.shared.errorColor)
        page.image = squircleRenderer.drawImageOnRoundedRect(image ?? Icons.errorOutline)

        bulletinManager = BLTNItemManager(rootItem: page)

        super.init()

        page.actionButtonTitle = Strings.dismiss
        page.actionHandler = { [weak self] _ in
            guard let self = self else { return }
            self.bulletinManager.dismissBulletin()
        }
    }

    func show(in app: UIApplication) {
        guard !bulletinManager.isShowingBulletin else {
            return
        }

        bulletinManager.showBulletin(in: app)
    }
}
