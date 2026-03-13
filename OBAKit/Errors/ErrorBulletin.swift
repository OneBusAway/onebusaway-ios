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
    private let error: Error
    private let page: ThemedBulletinPage
    private let application: Application

    init(application: Application, message: String? = nil, error: Error, regionName: String? = nil, image: UIImage? = nil, title: String? = nil) {
        self.application = application

        let classified = ErrorClassifier.classify(error, regionName: regionName)
        self.error = classified

        let displayMessage = message ?? classified.localizedDescription

        page = ThemedBulletinPage(title: title ?? Strings.error)
        page.descriptionText = displayMessage
        page.isDismissable = false

        let squircleRenderer = ImageBadgeRenderer(fillColor: .white, backgroundColor: ThemeColors.shared.errorColor)
        page.image = squircleRenderer.drawImageOnRoundedRect(image ?? Icons.errorOutline)

        bulletinManager = BLTNItemManager(rootItem: page)

        super.init()

        page.actionButtonTitle = Strings.dismiss
        page.actionHandler = { [weak self] _ in
            guard let self else { return }
            self.bulletinManager.dismissBulletin()
        }
    }

    /// Convenience initializer for call sites that pass an explicit message.
    convenience init(application: Application, message: String, error: Error, image: UIImage? = nil, title: String? = nil) {
        self.init(
            application: application,
            message: Optional(message),
            error: error,
            regionName: nil,
            image: image,
            title: title
        )
    }

    func show(in app: UIApplication) {
        guard !bulletinManager.isShowingBulletin else {
            return
        }

        bulletinManager.showBulletin(in: app)
    }
}
