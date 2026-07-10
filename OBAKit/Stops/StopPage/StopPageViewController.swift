//
//  StopPageViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import SwiftUI
import OBAKitCore

/// Hosting shell for the redesigned SwiftUI Stop page. Owns UIKit-side chrome
/// (nav bar items, menus) and keeps parity entry points (`Previewable` etc.)
/// working while `FeatureFlags.useNewStopPageKey` is enabled.
class StopPageViewController: UIHostingController<StopPageView>, AppContext {
    let application: Application
    let viewModel: StopViewModel

    var bookmarkContext: Bookmark? {
        get { viewModel.bookmarkContext }
        set { viewModel.bookmarkContext = newValue }
    }

    var transferContext: TransferContext? {
        get { viewModel.transferContext }
        set { viewModel.transferContext = newValue }
    }

    convenience init(application: Application, stop: Stop) {
        self.init(application: application, stopID: stop.id, stop: stop)
    }

    convenience init(application: Application, stopID: StopID) {
        self.init(application: application, stopID: stopID, stop: nil)
    }

    private init(application: Application, stopID: StopID, stop: Stop?) {
        self.application = application
        self.viewModel = StopViewModel(application: application, stopID: stopID, stop: stop)
        super.init(rootView: StopPageView(viewModel: viewModel))
        hidesBottomBarWhenPushed = false
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = viewModel.stop.map(Formatters.formattedTitle(stop:)) ?? Strings.loading
        navigationItem.largeTitleDisplayMode = .never
    }
}
