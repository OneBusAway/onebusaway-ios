//
//  VehiclesViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import SwiftUI
import OBAKitCore

/// A view controller that wraps the SwiftUI VehiclesMapView for use in UIKit tab bar
class VehiclesViewController: UIViewController, AppContext {
    let application: Application

    private var hostingController: UIHostingController<VehiclesMapView>?

    init(application: Application) {
        self.application = application
        super.init(nibName: nil, bundle: nil)

        title = Strings.vehicles
        tabBarItem.image = Icons.vehiclesTabIcon
        tabBarItem.selectedImage = Icons.vehiclesSelectedTabIcon
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let vehiclesMapView = VehiclesMapView(application: application)
        let hostingController = UIHostingController(rootView: vehiclesMapView)

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        hostingController.didMove(toParent: self)
        self.hostingController = hostingController
    }
}
