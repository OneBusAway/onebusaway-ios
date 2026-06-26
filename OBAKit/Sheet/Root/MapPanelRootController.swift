//
//  MapPanelRootController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore

/// UIKit root for the experimental SwiftUI map-panel experience. Hosts
/// `MapPanelRootView` as its single child controller and surfaces nothing
/// else — the SwiftUI tree owns the entire visible UI.
///
/// Lives alongside `ClassicApplicationRootController` rather than inside it
/// so the classic class stays a `UITabBarController` with non-optional tab VCs.
/// The AppDelegates pick between the two via `ApplicationRootControllerFactory`.
public final class MapPanelRootController: UIViewController {

    private let host: UIHostingController<MapPanelRootView>

    public init(application: Application) {
        let bridge = TripPresentationBridge()
        let factory = AppSheetViewFactory(
            application: application,
            onPresentTrip: { [weak bridge] arrival in bridge?.present(arrival) }
        )
        let rootView = MapPanelRootView(application: application, factory: factory)
        self.host = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
        bridge.host = self
        bridge.application = application
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }

    /// Bridges single-match navigation from `CurrentTripView` back to the UIKit
    /// `TripViewController`. Exists as a separate type because `self` isn't
    /// available before `super.init`, and the closure baked into the factory
    /// needs to reach it.
    @MainActor
    private final class TripPresentationBridge {
        weak var host: UIViewController?
        weak var application: Application?

        func present(_ arrival: ArrivalDeparture) {
            guard let host, let application else { return }
            let trip = TripViewController(application: application, arrivalDeparture: arrival)
            application.viewRouter.navigate(to: trip, from: host)
        }
    }
}
