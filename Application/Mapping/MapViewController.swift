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
public class MapViewController: UIViewController,
    FloatingPanelControllerDelegate,
    LocationServiceDelegate,
    MapRegionDelegate,
    ModalDelegate,
    NearbyDelegate {

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
        self.application.mapRegionManager.addDelegate(self)
        self.application.locationService.addDelegate(self)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UIViewController

    public override func viewDidLoad() {
        super.viewDidLoad()

        let mapView = mapRegionManager.mapView
        view.addSubview(mapView)
        mapView.pinToSuperview(.edges)

        floatingPanel.addPanel(toParent: self)

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

        navigationController?.setNavigationBarHidden(true, animated: false)

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

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        navigationController?.setNavigationBarHidden(false, animated: false)
    }

    // MARK: - Public Methods

    @objc public func centerMapOnUserLocation() {
        guard isLoadedAndOnScreen else { return }

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

    // MARK: - Floating Panel Controller

    private var semiModalPanel: FloatingPanelController?

    private func showSemiModalPanel(childController: UIViewController) {
        semiModalPanel?.removePanelFromParent(animated: false)

        let panel = FloatingPanelController()
        panel.surfaceView.cornerRadius = ThemeMetrics.cornerRadius

        // Set a content view controller.
        panel.set(contentViewController: childController)

        if childController is Scrollable {
            panel.track(scrollView: (childController as! Scrollable).scrollView) // swiftlint:disable:this force_cast
        }

        panel.addPanel(toParent: self, belowView: nil, animated: true)

        semiModalPanel = panel
    }

    /// The floating panel controller, which displays a drawer at the bottom of the map.
    private lazy var floatingPanel: FloatingPanelController = {
        let panel = FloatingPanelController(delegate: self)
        panel.isRemovalInteractionEnabled = false
        panel.surfaceView.cornerRadius = ThemeMetrics.cornerRadius

        // Set a content view controller.
        panel.set(contentViewController: nearbyController)

        // Track a scroll view(or the siblings) in the content view controller.
        panel.track(scrollView: nearbyController.collectionController.collectionView)

        return panel
    }()

    public func floatingPanel(_ vc: FloatingPanelController, layoutFor newCollection: UITraitCollection) -> FloatingPanelLayout? {
        return MapPanelLayout(initialPosition: .tip)
    }

    // MARK: - Modal Delegate

    public func dismissModalController(_ controller: UIViewController) {
        if controller == semiModalPanel?.contentViewController {
            mapRegionManager.cancelSearch()
            semiModalPanel?.removePanelFromParent(animated: true)
        }
        else {
            controller.dismiss(animated: true, completion: nil)
        }
    }

    // MARK: - Nearby Controller

    private lazy var nearbyController = NearbyViewController(application: application, mapRegionManager: application.mapRegionManager, delegate: self)

    public func nearbyController(_ nearbyController: NearbyViewController, didSelectStop stop: Stop) {
        show(stop: stop)
    }

    public func nearbyControllerDisplaySearch(_ nearbyController: NearbyViewController) {
        floatingPanel.move(to: .full, animated: true)
    }

    public func nearbyController(_ nearbyController: NearbyViewController, moveTo position: FloatingPanelPosition, animated: Bool) {
        floatingPanel.move(to: position, animated: animated)
    }

    // MARK: - MapRegionDelegate

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

    public func mapRegionManager(_ manager: MapRegionManager, noSearchResults response: SearchResponse) {
        // abxoxo todo!
    }

    public func mapRegionManager(_ manager: MapRegionManager, disambiguateSearch response: SearchResponse) {
        let searchResults = SearchResultsController(searchResponse: response, application: application, delegate: self)
        let nav = UINavigationController(rootViewController: searchResults)
        application.viewRouter.present(nav, from: self, isModalInPresentation: true)
    }

    // abxoxo - todo!
    public func mapRegionManager(_ manager: MapRegionManager, showSearchResult response: SearchResponse) {
        guard let result = response.results.first else { return }

        switch result {
        case let result as MKMapItem:
            let mapItemController = MapItemViewController(application: application, mapItem: result, delegate: self)
            showSemiModalPanel(childController: mapItemController)
        case let result as StopsForRoute:
            let routeStopController = RouteStopsViewController(application: application, stopsForRoute: result, delegate: self)
            showSemiModalPanel(childController: routeStopController)
        case let result as Stop:
            show(stop: result)
        case let result as VehicleStatus:
            AlertPresenter.show(errorMessage: "abxoxo - Add ability to show vehicle status!", presentingController: self)
            print("Show vehicle status: \(result)")
        default:
            fatalError()
        }
    }

    // MARK: - LocationServiceDelegate

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
