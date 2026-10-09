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
        let coordinator = SheetCoordinator<AppSheetRoute>(root: .home)
        let bridge = TripPresentationBridge(coordinator: coordinator)
        let displayModel = MapSearchDisplayModel()
        // Built here, not inside `MapPanelRootView`, because the factory is
        // constructed first and the home sheet's nearby section must observe
        // the same instance the map renders from. Same reasoning as
        // `displayModel` below.
        let tripPlannerMapDisplayModel = TripPlannerMapDisplayModel()
        // Built here for the same reason: the factory must have the instance so the
        // trip planner sheet can push the same model instance the map renders from.
        let stopsObserver = MapStopsObserver(application: application)
        // Built here for the same reason: the trip sheet hands its trip to this
        // instance, and the map draws from it. The rider's location only frames
        // the trip when the app may use it.
        let tripFocusMapDisplayModel = TripFocusMapDisplayModel(userLocation: { [weak application] in
            guard let locationService = application?.locationService,
                  locationService.isLocationUseAuthorized else { return nil }
            return locationService.currentLocation?.coordinate
        })
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
            stopsObserver: stopsObserver,
            tripPlannerMapDisplayModel: tripPlannerMapDisplayModel,
            tripFocusMapDisplayModel: tripFocusMapDisplayModel
        )
        let rootView = MapPanelRootView(
            application: application,
            mapViewModel: mapViewModel,
            layersModel: layersModel,
            factory: factory,
            coordinator: coordinator,
            searchDisplayModel: displayModel,
            stopsObserver: stopsObserver,
            tripPlannerMapDisplayModel: tripPlannerMapDisplayModel,
            tripFocusMapDisplayModel: tripFocusMapDisplayModel
        )
        self.host = UIHostingController(rootView: rootView)
        self.bridge = bridge
        super.init(nibName: nil, bundle: nil)
        self.bridge.host = self
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

    /// Opens the trips `CurrentTripView` and vehicle search hand over as the
    /// `.tripDetails` sheet, over the map it's showing, and resolves where the
    /// stop sheet's UIKit modals present from. A separate type because `self`
    /// isn't available before `super.init`, and the closures baked into the
    /// factory need to reach it.
    @MainActor
    final class TripPresentationBridge {
        weak var host: UIViewController?
        private let coordinator: SheetCoordinator<AppSheetRoute>
        private let presentError: (String, UIViewController) -> Void

        /// - Parameter presentError: Shows an error message from a controller.
        ///   Injectable so a test can see the vehicle-not-on-trip alert fire.
        init(
            coordinator: SheetCoordinator<AppSheetRoute>,
            presentError: @escaping (String, UIViewController) -> Void = { message, presenter in
                Task { await AlertPresenter.show(errorMessage: message, presentingController: presenter) }
            }
        ) {
            self.coordinator = coordinator
            self.presentError = presentError
        }

        /// Topmost presented controller, so modals land above the sheet stack
        /// rather than underneath it — UIKit ignores `present` on a controller
        /// that already has a `presentedViewController`.
        func topmostController() -> UIViewController? {
            host?.topmostPresentedController
        }

        func present(_ arrival: ArrivalDeparture) {
            open(TripConvertible(arrivalDeparture: arrival))
        }

        func present(vehicleStatus: VehicleStatus) {
            guard let convertible = TripConvertible(vehicleStatus: vehicleStatus) else {
                showVehicleNotOnTrip()
                return
            }
            open(convertible)
        }

        /// Opens the trip over the home sheet, unless it is already open.
        ///
        /// The sheets that led here are closed first, as search closes itself
        /// before opening a result. The trip is drawn on the map, and My Trip's
        /// route picker and results sit at full height under a `.medium` trip
        /// sheet, covering that map. They would also stay draggable through it,
        /// and dragging one away strands the trip sheet with no route behind it.
        private func open(_ convertible: TripConvertible) {
            let route = AppSheetRoute.tripDetails(convertible)
            // Already open: unwinding would close it only to open it again.
            guard !coordinator.allRoutes.contains(route) else { return }

            coordinator.popToRoot()
            coordinator.push(route)
        }

        /// Same message the UIKit map shows: the vehicle exists but isn't assigned
        /// to a trip, so there's nothing to display.
        private func showVehicleNotOnTrip() {
            // `topmostController()` is nil exactly when `host` is.
            guard let presenter = topmostController() else {
                Logger.error("TripPresentationBridge: dropping the vehicle-not-on-trip alert — host is nil")
                return
            }
            let message = OBALoc(
                "map_controller.vehicle_not_on_trip_error",
                value: "The vehicle you chose doesn't appear to be on a trip right now, which means we don't know how to show it to you.",
                comment: "This message appears when a searched-for vehicle doesn't have an assigned trip."
            )
            // `presenter`, not `host`: by the time we get here the base sheet is
            // still up on `host`, and UIKit ignores `present` on a controller that
            // already has a `presentedViewController`. Presenting from `host`
            // silently drops the alert, leaving the rider on home with no
            // explanation for why their vehicle search went nowhere.
            presentError(message, presenter)
        }
    }
}
