//
//  MapItemViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import SwiftUI
import MapKit
import OBAKitCore

/// A view controller that displays information about a map item (location/place) in a modal presentation.
///
/// This view controller acts as a UIKit wrapper around a SwiftUI view (`MapItemView`), using `UIHostingController`
/// to bridge between the two frameworks. It displays location details such as address, phone number, and website,
/// and provides a link to view nearby transit stops.
///
class MapItemViewController: UIViewController, AppContext {
    var application: Application {
        viewModel.application
    }

    /// The hosting controller that embeds the SwiftUI view
    private var hostingController: UIHostingController<AnyView>?

    /// The view model that manages the business logic
    private let viewModel: MapItemViewModel

    init(_ viewModel: MapItemViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear

        viewModel.setPresentingViewController(self)

        let mapItemView = MapItemView(viewModel: viewModel)
            .environment(\.coreApplication, viewModel.application)

        let hostingController = UIHostingController(rootView: AnyView(mapItemView))
        hostingController.view.backgroundColor = .clear

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.pinToSuperview(.edges)
        hostingController.didMove(toParent: self)

        self.hostingController = hostingController
    }
}
