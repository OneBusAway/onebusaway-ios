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
import CocoaLumberjackSwift

/// Displays a map, a set of stops rendered as annotation views, and the user's location if authorized.
///
/// `MapViewController` is the average user's primary means of interacting with OneBusAway data.
public class MapViewController: UIViewController {

    // MARK: - Floating Panel and Hoverbar
    var floatingToolbar: HoverBar = {
        let hover = HoverBar.autolayoutNew()
        hover.isHidden = true
        hover.orientation = .horizontal
        hover.tintColor = .black
        return hover
    }()

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

    public override func viewDidLoad() {
        super.viewDidLoad()

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

    public override func viewWillAppear(_ animated: Bool) {
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

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Start showing the status overlay on the map once this controller has appeared.
        mapRegionManager.addStatusOverlayToMap()
    }

    // MARK: - Public Methods

    @objc public func centerMapOnUserLocation() {
        guard isViewLoaded, view.window != nil else { return }

        let userLocation = mapRegionManager.mapView.userLocation.coordinate
        mapRegionManager.mapView.setCenterCoordinate(centerCoordinate: userLocation, zoomLevel: 17, animated: true)
    }

    // MARK: - Content Presentation

    /// Displays the specified stop.
    ///
    /// - Parameter stop: The stop to display.
    func show(stop: Stop) {
        application.viewRouter.navigateTo(stop: stop, from: self)
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
                let msg = NSLocalizedString("map_view_controller.error_messages.display_walking_route_failed", value: "Unable to fetch walking directions.", comment: "An error message displayed when the app is unable to fetch walking directions to show to the user.")
                AlertPresenter.show(errorMessage: msg, presentingController: self)
                return
            }

            let directions = MKDirections.walkingDirections(to: stop.coordinate)
            directions.calculate { [weak self] response, error in
                guard
                    let unwrappedResponse = response,
                    let self = self
                else { return }

                if let error = error {
                    DDLogError("Error retrieving walking directions: \(error)")
                    AlertPresenter.show(error: error, presentingController: self)
                }

                for route in unwrappedResponse.routes {
                    self.mapRegionManager.addWalkingDirectionsOverlay(route.polyline, for: stop)
                }
            }
        }
    }
}

// MARK: - MapRegionDelegate

extension MapViewController: MapRegionDelegate {
    public func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard
            !application.theme.behaviors.mapShowsCallouts,
            let stop = view.annotation as? Stop else {
            return
        }

        show(stop: stop)
    }

    public func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        guard let stop = view.annotation as? Stop else {
            return
        }

        show(stop: stop)
    }

    public func mapRegionManager(_ manager: MapRegionManager, searchUpdated search: SearchResponse) {
//        if search.needsDisambiguation {
//            let searchResults = SearchResultsController(searchResponse: search, application: application, floatingPanelDelegate: self, delegate: self)
//            presentFloatingPanel(contentController: searchResults, scrollView: searchResults.collectionController.collectionView, animated: true)
//        }
//        else {
//            SearchResultsController.presentResult(from: search, delegate: self)
//        }
    }
}

// MARK: - SearchResultsDelegate

extension MapViewController: SearchResultsDelegate {
    public func searchResults(controller: SearchResultsController?, showRoute route: Route) {
        // render polyline and what else?
    }

    public func searchResults(controller: SearchResultsController?, showMapItem mapItem: MKMapItem) {
        // scroll/zoom to pin, show card.
    }

    public func searchResults(controller: SearchResultsController?, showStop stop: Stop) {
        show(stop: stop)
    }

    public func searchResults(controller: SearchResultsController?, showVehicleStatus vehicleStatus: VehicleStatus) {
        // ???
    }
}

// MARK: - LocationServiceDelegate

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

    public func locationService(_ service: LocationService, locationChanged location: CLLocation) {
        programmaticallyUpdateVisibleMapRegion(location: location)
    }
}
