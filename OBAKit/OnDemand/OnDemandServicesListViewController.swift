//
//  OnDemandServicesListViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import SwiftUI
import UIKit

/// UIKit host for `OnDemandServicesListView`, pushed from the Agencies screen.
final class OnDemandServicesListViewController: UIHostingController<OnDemandServicesListView> {

    init(application: Application, agency: Agency) {
        let model = OnDemandServicesListModel(
            agencyID: agency.id,
            apiService: application.apiService,
            regionName: application.currentRegionName
        )
        weak var weakApplication = application
        // `self` isn't available before super.init; the closure resolves the
        // host lazily through the hosting controller it is installed in.
        var pushFromHost: ((OnDemandService) -> Void)?
        super.init(rootView: OnDemandServicesListView(model: model, onSelect: { service in pushFromHost?(service) }))
        pushFromHost = { [weak self] service in
            guard let self, let application = weakApplication else { return }
            application.viewRouter.navigateTo(onDemandService: service, from: self)
        }
        title = Strings.onDemandListTitle
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
