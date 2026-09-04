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
    private let bridge: TripPresentationBridge

    public init(application: Application) {
        let bridge = TripPresentationBridge()
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let displayModel = MapSearchDisplayModel()
        // Built here, not inside `MapPanelRootView`, because the factory is
        // constructed first and the home sheet's nearby section must observe
        // the same instance the map renders from. Same reasoning as
        // `displayModel` above.
        let stopsObserver = MapStopsObserver(application: application)
        // Same reasoning for the map models: `AppSheetViewFactory` needs the
        // very instances the map renders from — `MapSheetModel` reads and
        // writes the map type through `MapViewModel`, so a second copy would
        // let the Map settings sheet and the map disagree.
        let initialMapType = MapBaseType(application.mapRegionManager.userSelectedMapType)
        let mapViewModel = MapViewModel(application: application, initialMapType: initialMapType)
        let layersModel = MapPanelLayersModel(application: application)
        let factory = AppSheetViewFactory(
            application: application,
            mapViewModel: mapViewModel,
            layersModel: layersModel,
            onPresentTrip: { [weak bridge] arrival in bridge?.present(arrival) },
            onPresentVehicleTrip: { [weak bridge] vehicleStatus in bridge?.present(vehicleStatus: vehicleStatus) },
            presentingController: { [weak bridge] in bridge?.topmostController() },
            coordinator: coordinator,
            searchDisplayModel: displayModel,
            stopsObserver: stopsObserver
        )
        let rootView = MapPanelRootView(
            application: application,
            mapViewModel: mapViewModel,
            layersModel: layersModel,
            factory: factory,
            coordinator: coordinator,
            searchDisplayModel: displayModel,
            stopsObserver: stopsObserver
        )
        self.host = UIHostingController(rootView: rootView)
        self.bridge = bridge
        super.init(nibName: nil, bundle: nil)
        self.bridge.host = self
        self.bridge.application = application
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

        /// Topmost presented controller, so modals land above the sheet stack
        /// rather than underneath it — UIKit ignores `present` on a controller
        /// that already has a `presentedViewController`.
        func topmostController() -> UIViewController? {
            guard let host else { return nil }
            var presenter: UIViewController = host
            while let next = presenter.presentedViewController {
                presenter = next
            }
            return presenter
        }

        func present(_ arrival: ArrivalDeparture) {
            // `topmostController()` is nil exactly when `host` is, so this one
            // guard covers both — and folds in the resolution that used to
            // return silently further down.
            guard let application, let presenter = topmostController() else {
                Logger.error("TripPresentationBridge: dropping present for trip \(arrival.tripID) — host or application is nil")
                return
            }
            let trip = TripViewController(application: application, arrivalDeparture: arrival)
            presentTripController(trip, application: application, presenter: presenter)
        }

        func present(vehicleStatus: VehicleStatus) {
            // As above: `topmostController()` is nil exactly when `host` is.
            guard let application, let presenter = topmostController() else {
                Logger.error("TripPresentationBridge: dropping vehicle present — host or application is nil")
                return
            }

            guard let convertible = TripConvertible(vehicleStatus: vehicleStatus) else {
                // Same message the UIKit map shows: the vehicle exists but isn't
                // assigned to a trip, so there's nothing to display.
                let message = OBALoc(
                    "map_controller.vehicle_not_on_trip_error",
                    value: "The vehicle you chose doesn't appear to be on a trip right now, which means we don't know how to show it to you.",
                    comment: "This message appears when a searched-for vehicle doesn't have an assigned trip."
                )
                // `presenter`, not `host`, for the reason spelled out in
                // `presentTripController` below: UIKit ignores `present` on a
                // controller that already has a `presentedViewController`, and by the
                // time we get here the base sheet is still up on `host`. Presenting
                // from `host` silently drops the alert, leaving the rider on home with
                // no explanation for why their vehicle search went nowhere.
                Task { await AlertPresenter.show(errorMessage: message, presentingController: presenter) }
                return
            }

            let trip = TripViewController(application: application, tripConvertible: convertible)
            presentTripController(trip, application: application, presenter: presenter)
        }

        private func presentTripController(_ trip: TripViewController, application: Application, presenter: UIViewController) {
            // Wrap in our own UINavigationController and modally present from
            // the topmost presented controller, not `host` directly:
            //
            // 1. `ViewRouter.navigate(to:from:)` asserts the source controller
            //    has a `navigationController`. The SwiftUI host is the root of
            //    the window's hierarchy — no nav stack wraps it — so the UIKit
            //    "push" path can't be reused here.
            // 2. The floating sheet system uses SwiftUI `.sheet(...)`, which
            //    UIKit-bridges as modals on the host. By the time we're
            //    invoked, `host.presentedViewController` chains up through the
            //    base sheet (`.home`), the picker (`.routePicker`), and the
            //    stacked CurrentTrip sheet. Presenting from `host` would land
            //    underneath that chain (UIKit ignores presents on a controller
            //    that already has a `presentedViewController`); we have to
            //    walk up to the top and present from there so the trip view
            //    lands above the sheet stack.
            //
            // Done button dismisses back to the (still-intact) sheet stack.
            trip.navigationItem.leftBarButtonItem = UIBarButtonItem(
                systemItem: .done,
                primaryAction: UIAction { [weak trip] _ in
                    trip?.dismiss(animated: true)
                }
            )
            let navigation = application.viewRouter.buildNavigation(controller: trip)
            // Skip if the topmost presented controller is already a
            // `TripViewController` (or a nav rooted at one). `CurrentTripView`
            // stays mounted under the modal trip and its 20-second refresh
            // timer keeps firing — without this guard, repeat single-match
            // hits would stack a fresh `TripViewController` on top of the
            // existing one each tick.
            if presenter is TripViewController { return }
            if let nav = presenter as? UINavigationController, nav.viewControllers.first is TripViewController {
                return
            }
            presenter.present(navigation, animated: true)
        }
    }
}
