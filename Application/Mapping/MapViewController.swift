//
//  MapViewController.swift
//  OBANext
//
//  Created by Aaron Brethorst on 11/24/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit
import MapKit
import FloatingPanel

class MapViewController: UIViewController, FloatingPanelContainer, NearbyDelegate {

    // MARK: - Floating Panel and Hoverbar
    var floatingToolbar: HoverBar = {
        let hover = HoverBar.autolayoutNew()
        hover.isHidden = true
        hover.orientation = .horizontal
        hover.tintColor = .black
        return hover
    }()

    var childFloatingPanel: FloatingPanelController?

    var previousFloatingPanelPosition: FloatingPanelPosition = .half

    /// The 'root' floating panel controller for this view controller.
    lazy var floatingPanelController = createFloatingPanelController(contentController: nearbyController, scrollView: nearbyController.collectionController.collectionView)

    // MARK: - Data

    let application: Application

    var mapRegionManager: MapRegionManager {
        return application.mapRegionManager
    }

    private var initialMapChangeMade = false

    // MARK: - Init

    public init(application: Application) {
        self.application = application

        super.init(nibName: nil, bundle: nil)

        title = Strings.map
        tabBarItem.image = Icons.mapTabIcon

        // Assign delegates
        self.mapRegionManager.addDelegate(self)
        self.application.locationService.addDelegate(self)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationController?.isNavigationBarHidden = true

        let mapView = mapRegionManager.mapView
        view.addSubview(mapView)
        mapView.pinToSuperview(.edges)

        view.addSubview(floatingToolbar)

        NSLayoutConstraint.activate([
            floatingToolbar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            floatingToolbar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            floatingToolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            floatingToolbar.heightAnchor.constraint(greaterThanOrEqualToConstant: 44.0)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if let currentRegion = application.regionsService.currentRegion {
            if let location = application.locationService.currentLocation {
                programmaticallyUpdateVisibleMapRegion(location: location)
            }
            else {
                mapRegionManager.mapView.visibleMapRect = currentRegion.serviceRect
            }
        }
        else {
            application.manuallySelectRegion()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        //  Add FloatingPanel to the view with animation.
        floatingPanelController.addPanel(toParent: self, belowView: floatingToolbar, animated: animated)

        // Start showing the status overlay on the map once this controller has appeared.
        mapRegionManager.addStatusOverlayToMap()
    }

    // MARK: - Nearby Controller and Delegate

    /// The 'nearby' controller shows recent stops, bookmarks, nearby stops, and more.
    private lazy var nearbyController: NearbyViewController = {
        let nearby = NearbyViewController(application: application, mapRegionManager: mapRegionManager, delegate: self)
        return nearby
    }()

    func nearbyController(_ nearbyController: NearbyViewController, didSelectStopID stopID: String) {
        showStop(id: stopID)
    }

    func nearbyControllerRequestFullScreen(_ nearbyController: NearbyViewController) {
        floatingPanelController.move(to: .full, animated: true)
    }

    func nearbyControllerRequestDefaultLayout(_ nearbyController: NearbyViewController) {
        floatingPanelController.move(to: .half, animated: true)
    }
}

// MARK: - Actions
extension MapViewController {

    // MARK: - Content Presentation

    /// Displays the stop with the specified ID.
    ///
    /// - Parameter id: The agency-prefixed stop ID.
    func showStop(id: String) {
        let stopController = FloatingStopViewController(application: application, stopID: id, delegate: self)

        displayWalkingRoute(stopID: id)
        presentFloatingPanel(contentController: stopController, scrollView: stopController.stackView, animated: true)
    }

    func panelForModelDidClose(_ model: AnyObject?) {
        if let stop = model as? Stop {
            mapRegionManager.removeWalkingDirectionsOverlay(for: stop)
        }
        else {
            // nop.
        }
    }

    // MARK: - Routes

    /// Renders walking directions to the specified stop ID as a map overlay.
    ///
    /// - Parameter stopID: The agency-prefixed stop ID.
    func displayWalkingRoute(stopID: String) {
        mapRegionManager.fetchStopWithID(stopID) { (stop) in
            guard let stop = stop else {
                // abxoxo - todo show an error.
                return
            }

            let directions = MKDirections.walkingDirections(to: stop.coordinate)

            directions.calculate { [weak self] response, error in
                guard
                    let unwrappedResponse = response,
                    let self = self
                else { return }

                for route in unwrappedResponse.routes {
                    self.mapRegionManager.addWalkingDirectionsOverlay(route.polyline, for: stop)
                }
            }
        }
    }
}

// MARK: - MapRegionDelegate

extension MapViewController: MapRegionDelegate {
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard let stop = view.annotation as? Stop else {
            return
        }

        showStop(id: stop.id)
    }

    func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
        guard
            let stop = view.annotation as? Stop,
            let childFloatingPanel = childFloatingPanel,
            let stopController = childFloatingPanel.contentViewController as? FloatingStopViewController,
            stopController.stopID == stop.id
        else {
            return
        }

        closePanel(containing: stopController, model: stop)
    }

    public func mapRegionManager(_ manager: MapRegionManager, searchUpdated search: SearchResponse) {
        if search.needsDisambiguation {
            let searchResults = SearchResultsController(searchResponse: search, application: application, floatingPanelDelegate: self, delegate: self)
            presentFloatingPanel(contentController: searchResults, scrollView: searchResults.collectionController.collectionView, animated: true)
        }
        else {
            SearchResultsController.presentResult(from: search, delegate: self)
        }
    }
}

extension MapViewController: SearchResultsDelegate {
    func searchResults(controller: SearchResultsController?, showRoute route: Route) {
        // render polyline and what else?
    }

    func searchResults(controller: SearchResultsController?, showMapItem mapItem: MKMapItem) {
        // scroll/zoom to pin, show card.
    }

    func searchResults(controller: SearchResultsController?, showStop stop: Stop) {
        showStop(id: stop.id)
    }

    func searchResults(controller: SearchResultsController?, showVehicleStatus vehicleStatus: VehicleStatus) {
        // ???
    }
}

extension MapViewController: LocationServiceDelegate {
    private static let programmaticRadiusInMeters = 200.0

    func programmaticallyUpdateVisibleMapRegion(location: CLLocation) {
        guard !initialMapChangeMade else {
            return
        }

        initialMapChangeMade = true
        let region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: MapViewController.programmaticRadiusInMeters, longitudinalMeters: MapViewController.programmaticRadiusInMeters)
        mapRegionManager.mapView.setRegion(region, animated: false)
    }

    func locationService(_ service: LocationService, locationChanged location: CLLocation) {
        programmaticallyUpdateVisibleMapRegion(location: location)
    }
}
