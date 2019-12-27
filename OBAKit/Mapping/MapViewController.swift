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
import OBAKitCore

/// Displays a map, a set of stops rendered as annotation views, and the user's location if authorized.
///
/// `MapViewController` is the average user's primary means of interacting with OneBusAway data.
public class MapViewController: UIViewController,
    FloatingPanelControllerDelegate,
    LocationServiceDelegate,
    MapRegionDelegate,
    ModalDelegate,
    NearbyDelegate {

    // MARK: - Hoverbar

    lazy var toolbar: HoverBar = {
        let hover = HoverBar.autolayoutNew()
        hover.tintColor = ThemeColors.shared.label
        hover.stackView.addArrangedSubview(locationButton)
        hover.stackView.addArrangedSubview(weatherButton)
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

    deinit {
        weatherOperation?.cancel()
    }

    // MARK: - UIViewController

    public override func viewDidLoad() {
        super.viewDidLoad()

        let mapView = mapRegionManager.mapView
        mapView.showsCompass = false
        view.addSubview(mapView)
        mapView.pinToSuperview(.edges)

        floatingPanel.addPanel(toParent: self)

        view.insertSubview(toolbar, aboveSubview: mapView)
        view.addSubview(compassButton)

        NSLayoutConstraint.activate([
            toolbar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -ThemeMetrics.controllerMargin),
            toolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: ThemeMetrics.controllerMargin),
            toolbar.widthAnchor.constraint(equalToConstant: 40.0),
            locationButton.heightAnchor.constraint(equalTo: locationButton.widthAnchor),
            weatherButton.heightAnchor.constraint(equalTo: weatherButton.widthAnchor),
            compassButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -ThemeMetrics.controllerMargin),
            compassButton.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: ThemeMetrics.padding)
        ])

        mapRegionManager.statusOverlay = statusOverlay
        view.addSubview(statusOverlay)

        NSLayoutConstraint.activate([
            statusOverlay.bottomAnchor.constraint(equalTo: floatingPanel.surfaceView.topAnchor, constant: -8.0),
            statusOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8.0),
            statusOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8.0)
        ])
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.setNavigationBarHidden(true, animated: false)

        if let currentRegion = application.regionsService.currentRegion {
            if let location = application.locationService.currentLocation {
                programmaticallyUpdateVisibleMapRegion(location: location)
            }
            else if let lastVisibleRegion = mapRegionManager.lastVisibleMapRect {
                mapRegionManager.mapView.visibleMapRect = lastVisibleRegion
            }
            else {
                mapRegionManager.mapView.visibleMapRect = currentRegion.serviceRect
            }
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        loadWeather()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        navigationController?.setNavigationBarHidden(false, animated: false)
    }

    // MARK: - User Location

    @objc public func centerMapOnUserLocation() {
        guard isLoadedAndOnScreen else { return }

        let userLocation = mapRegionManager.mapView.userLocation
        guard userLocation.isValid else { return }

        mapRegionManager.mapView.setCenterCoordinate(centerCoordinate: userLocation.coordinate, zoomLevel: 17, animated: true)
    }

    private let locationButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(Icons.mapTabIcon, for: .normal)
        button.addTarget(self, action: #selector(centerMapOnUserLocation), for: .touchUpInside)
        button.accessibilityLabel = NSLocalizedString("map_controller.center_user_location", value: "Center map on current location", comment: "Map controller for centering the map on the user's current location.")
        return button
    }()

    // MARK: - Map Compass

    private lazy var compassButton: MKCompassButton = {
        let compassBtn = MKCompassButton(mapView: mapRegionManager.mapView)
        compassBtn.translatesAutoresizingMaskIntoConstraints = false
        compassBtn.compassVisibility = .adaptive
        return compassBtn
    }()

    // MARK: - Weather

    private let weatherButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("—", for: .normal)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.addTarget(self, action: #selector(showWeather), for: .touchUpInside)
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body).bold
        button.accessibilityLabel = NSLocalizedString("map_controller.show_weather_button", value: "Show Weather Forecast", comment: "Accessibility label for a button that provides the current forecast")
        return button
    }()

    @objc private func showWeather() {
        guard let forecast = forecast else { return }

        let alert = UIAlertController(title: forecast.todaySummary, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction.dismissAction)
        present(alert, animated: true, completion: nil)
    }

    private var weatherOperation: WeatherModelOperation?

    private var forecast: WeatherForecast? {
        didSet {
            if let forecast = forecast {
                let formattedTemp = MeasurementFormatter.unitlessConversion(temperature: forecast.currentForecast.temperature, unit: .fahrenheit, to: application.locale)
                weatherButton.setTitle(formattedTemp, for: .normal)
            }
            else {
                weatherButton.setTitle("—", for: .normal)
            }
        }
    }

    private func loadWeather() {
        guard let apiService = application.obacoService else { return }

        let op = apiService.getWeather()
        op.then { [weak self] in
            guard let self = self else { return }
            self.forecast = op.weatherForecast
        }
        weatherOperation = op
    }

    // MARK: - Content Presentation

    /// Displays the specified stop.
    ///
    /// - Parameter stop: The stop to display.
    func show(stop: Stop) {
        application.viewRouter.navigateTo(stop: stop, from: self)
    }

    // MARK: - Status Overlay

    private let statusOverlay = StatusOverlayView.autolayoutNew()

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

    public func floatingPanelDidChangePosition(_ vc: FloatingPanel.FloatingPanelController) {
        // Don't allow the status overlay to be shown when the
        // Floating Panel is fully open because it looks weird.
        statusOverlay.isHidden = vc.position == .full
    }

    // MARK: - Modal Delegate

    public func dismissModalController(_ controller: UIViewController) {
        if controller == semiModalPanel?.contentViewController {
            if statusOverlay.isHidden {
                statusOverlay.isHidden = floatingPanel.position != .full
            }

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
        if let region = view.annotation as? Region {
            let title = NSLocalizedString("map_controller.change_region_alert.title", value: "Change Region?", comment: "Title of the alert that appears when the user is updating their current region manually.")
            let messageFmt = NSLocalizedString("map_controller.change_region_alert.message_fmt", value: "Would you like to change your region to %@?", comment: "Body of the alert that appears when the user is updating their current region manually.")
            let alert = UIAlertController(title: title, message: String(format: messageFmt, region.name), preferredStyle: .alert)
            alert.addAction(UIAlertAction.cancelAction)
            alert.addAction(UIAlertAction(title: NSLocalizedString("map_controller.change_region_alert.button", value: "Change Region", comment: "Change Region button on the alert that appears when the user is updating their current region manually."), style: .default, handler: { _ in
                self.application.regionsService.currentRegion = region
            }))

            present(alert, animated: true) {
                mapView.deselectAnnotation(view.annotation, animated: true)
            }
        }
    }

    public func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        guard let stop = view.annotation as? Stop else {
            return
        }

        show(stop: stop)
    }

    public func mapRegionManager(_ manager: MapRegionManager, noSearchResults response: SearchResponse) {
        AlertPresenter.show(errorMessage: NSLocalizedString("map_controller.no_search_results_found", value: "No search results were found.", comment: "A generic message shown when the user's search query produces no search results."), presentingController: self)
    }

    public func mapRegionManager(_ manager: MapRegionManager, disambiguateSearch response: SearchResponse) {
        let searchResults = SearchResultsController(searchResponse: response, application: application, delegate: self)
        let nav = UINavigationController(rootViewController: searchResults)
        application.viewRouter.present(nav, from: self, isModalInPresentation: true)
    }

    // abxoxo - todo!
    public func mapRegionManager(_ manager: MapRegionManager, showSearchResult response: SearchResponse) {
        guard let result = response.results.first else { return }

        statusOverlay.isHidden = true

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
            if let convertible = TripConvertible(vehicleStatus: result) {
                let tripController = TripViewController(application: application, tripConvertible: convertible)
                application.viewRouter.navigate(to: tripController, from: self)
            }
            else {
                let msg = NSLocalizedString("map_controller.vehicle_not_on_trip_error", value: "The vehicle you chose doesn't appear to be on a trip right now, which means we don't know how to show it to you.", comment: "This message appears when a searched-for vehicle doesn't have an assigned trip.")
                AlertPresenter.show(errorMessage: msg, presentingController: self)
            }
        default:
            fatalError()
        }
    }

    public func mapRegionManagerDismissSearch(_ manager: MapRegionManager) {
        nearbyController.exitSearchMode()
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
