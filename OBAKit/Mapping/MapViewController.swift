//
//  MapViewController.swift
//  OBANext
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

// swiftlint:disable file_length

import UIKit
import MapKit
import FloatingPanel
import OBAKitCore
import SwiftUI
import OTPKit

/// Displays a map, a set of stops rendered as annotation views, and the user's location if authorized.
///
/// `MapViewController` is the average user's primary means of interacting with OneBusAway data.
class MapViewController: UIViewController,
    FloatingPanelControllerDelegate,
    LocationServiceDelegate,
    MapRegionDelegate,
    MapRegionMapViewDelegate,
    ModalDelegate,
    MapPanelDelegate,
    UIContextMenuInteractionDelegate,
    UILargeContentViewerInteractionDelegate {

    // MARK: - Hoverbar

    lazy var toolbar: HoverBar = {
        let hover = HoverBar.autolayoutNew()
        hover.tintColor = ThemeColors.shared.label
        hover.stackView.addArrangedSubview(locationButton)

        locationButton.isHidden = !application.locationService.isLocationUseAuthorized

        hover.stackView.addArrangedSubview(HoverBarSeparator())
        hover.stackView.addArrangedSubview(toggleMapTypeButton)
        setMapTypeButtonImage(toggleMapTypeButton)

        if application.features.obaco == .running {
            hover.stackView.addArrangedSubview(HoverBarSeparator())
            hover.stackView.addArrangedSubview(weatherButton)
        }

        return hover
    }()

    // MARK: - Data

    let application: Application

    var mapRegionManager: MapRegionManager {
        return application.mapRegionManager
    }

    // MARK: - Init

    public init(application: Application) {
        self.application = application

        super.init(nibName: nil, bundle: nil)

        title = Strings.map
        tabBarItem.image = Icons.mapTabIcon
        tabBarItem.selectedImage = Icons.mapSelectedTabIcon

        // Assign delegates
        self.application.mapRegionManager.addDelegate(self)
        self.application.locationService.addDelegate(self)

        self.application.notificationCenter.addObserver(self, selector: #selector(applicationDidBecomeActive(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)
        self.application.notificationCenter.addObserver(self, selector: #selector(applicationWillResignActive(_:)), name: UIApplication.willResignActiveNotification, object: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        application.mapRegionManager.removeDelegate(self)
        application.locationService.removeDelegate(self)
    }

    // MARK: - UIViewController

    public override func viewDidLoad() {
        super.viewDidLoad()

        let mapView = mapRegionManager.mapView
        view.addSubview(mapView)
        mapView.pinToSuperview(.edges)

        mapStatusView.configure(with: application.locationService)
        mapStatusView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapMapStatus)))
        view.addSubview(mapStatusView)
        NSLayoutConstraint.activate([
            mapStatusView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapStatusView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapStatusView.topAnchor.constraint(equalTo: view.topAnchor)
        ])

        mapStatusView.addInteraction(UILargeContentViewerInteraction(delegate: self))

        floatingPanel.addPanel(toParent: self)

        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        tabBarItem.scrollEdgeAppearance = appearance

        view.insertSubview(toolbar, aboveSubview: mapView)

        NSLayoutConstraint.activate([
            toolbar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -ThemeMetrics.controllerMargin),
            toolbar.topAnchor.constraint(equalTo: mapStatusView.bottomAnchor, constant: ThemeMetrics.controllerMargin),
            toolbar.widthAnchor.constraint(equalToConstant: 42.0),
            locationButton.heightAnchor.constraint(equalTo: locationButton.widthAnchor),
            weatherButton.heightAnchor.constraint(equalTo: weatherButton.widthAnchor),
            toggleMapTypeButton.heightAnchor.constraint(equalTo: toggleMapTypeButton.widthAnchor)
        ])

        // Long press gesture to add a pin to the map

        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.5
        mapView.addGestureRecognizer(longPressGesture)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Only one map will be visible on screen at any given time,
        // and so we can swap this delegate on the MapRegionManager
        // at different times. I think this expectation will become
        // unfounded when UIScene gets adopted in the app. TODO.
        application.mapRegionManager.mapViewDelegate = self
        application.mapRegionManager.bookmarks = application.userDataStore.findBookmarks(in: application.currentRegion)

        navigationController?.setNavigationBarHidden(true, animated: false)

        updateVisibleMapRect()
        layoutMapMargins()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        loadWeather()
        updateVoiceover()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        navigationController?.setNavigationBarHidden(false, animated: false)
    }

    // MARK: - User Location

    @objc func centerMapOnUserLocationViaTap(_ sender: Any?) {
        guard isLoadedAndOnScreen else { return }
        application.analytics?.reportEvent(pageURL: "app://localhost/map", label: AnalyticsLabels.mapShowUserLocationButtonTapped, value: nil)
        centerMapOnUserLocation()
    }

    func centerMapOnUserLocation() {
        guard isLoadedAndOnScreen else { return }
        let userLocation = mapRegionManager.mapView.userLocation
        guard userLocation.isValid else { return }

        var zoomLevel = 17

        if application.locationService.accuracyAuthorization == .reducedAccuracy {
            zoomLevel = 11
        }

        mapRegionManager.mapView.setCenterCoordinate(centerCoordinate: userLocation.coordinate, zoomLevel: zoomLevel, animated: true)

        // It is possible to activate the center map button via Voiceover. When the user
        // centers the map on their location, partially collapse the sheet to enable mapview interaction.
        if floatingPanel.state == .full {
            floatingPanel.move(to: .half, animated: true)
        }
    }

    @objc func didTapMapStatus(_ sender: Any) {
        guard isLoadedAndOnScreen else { return }
        let mapStatusViewState = mapStatusView.state(for: application.locationService)
        guard let alert = MapStatusView.alert(for: mapStatusViewState) else { return }

        var keepLocationOffButton: UIAlertAction {
            return UIAlertAction(title: OBALoc("locationservices_alert_keepoff.button", value: "Keep Location Off", comment: ""), style: .default)
        }

        var goToSettingsButton: UIAlertAction {
            let title = OBALoc("locationservices_alert_gotosettings.button", value: "Turn On in Settings", comment: "")
            return UIAlertAction(title: title, style: .default, handler: { _ in
                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
            })
        }

        switch mapStatusViewState {
        case .notDetermined:
            alert.addAction(title: Strings.continue) { _ in
                self.application.locationService.requestInUseAuthorization()
            }
            alert.addAction(keepLocationOffButton)
        case .locationServicesOff:
            alert.addAction(goToSettingsButton)
            alert.addAction(keepLocationOffButton)
        case .impreciseLocation:
            alert.addAction(goToSettingsButton)
            alert.addAction(title: OBALoc("locationservices_alert_request_precise_location_once.button", value: "Allow Once", comment: "")) { _ in
                self.application.locationService.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "MapStatusView")
            }
            alert.addAction(title: OBALoc("locationservices_alert_keep_precise_location_off.button", value: "Keep Precise Location Off", comment: ""), handler: nil)
        case .locationServicesUnavailable, .locationServicesOn:
            // We shouldn't hit this state, but if we do, that's OK.
            alert.addAction(UIAlertAction(title: Strings.ok, style: .default))
        }
        self.present(alert, animated: true)
    }

    private lazy var locationButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(Icons.nearMe, for: .normal)
        button.addTarget(self, action: #selector(centerMapOnUserLocationViaTap), for: .touchUpInside)
        button.accessibilityLabel = OBALoc("map_controller.center_user_location", value: "Center map on current location", comment: "Map controller for centering the map on the user's current location.")
        return button
    }()

    // MARK: - Weather

    private lazy var weatherButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("—", for: .normal)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.addTarget(self, action: #selector(showWeather), for: .touchUpInside)
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body).bold
        button.accessibilityLabel = OBALoc("map_controller.show_weather_button", value: "Show Weather Forecast", comment: "Accessibility label for a button that provides the current forecast")
        return button
    }()

    @objc private func showWeather() {
        guard let forecast = forecast else { return }
        let formattedTemp = MeasurementFormatter.unitlessConversion(temperature: forecast.currentForecast.temperature, unit: .fahrenheit, to: application.locale)
        let formattedFeelsLikeTemp = MeasurementFormatter.unitlessConversion(temperature: forecast.currentForecast.temperatureFeelsLike, unit: .fahrenheit, to: application.locale)
        
        let measurementSystem = Locale.current.measurementSystem
        let windSpeed: String
        switch measurementSystem {
        case .us, .uk:
            let mph = forecast.currentForecast.windSpeed / 1.60934
            windSpeed = "\(Int(mph)) mph"
        default:
            windSpeed = "\(Int(forecast.currentForecast.windSpeed)) km/h"
        }

        let alert = UIAlertController(
            title: forecast.todaySummary,
            message: """
                Temp: \(formattedTemp) (Feels like \(formattedFeelsLikeTemp))
                Wind: \(windSpeed)
                Precipitation: \(Int(forecast.currentForecast.precipProbability * 100))% chance
                """,
            preferredStyle: .alert
        )
        alert.addAction(.dismissAction)
        present(alert, animated: true)
    }

    private var forecast: WeatherForecast? {
        didSet {
            if let forecast = forecast {
                let formattedTemp = MeasurementFormatter.unitlessConversion(temperature: forecast.currentForecast.temperature, unit: .fahrenheit, to: application.locale)
                weatherButton.setTitle(formattedTemp, for: .normal)
                weatherButton.isHidden = false
            }
            else {
                weatherButton.isHidden = true
            }
        }
    }

    private func loadWeather() {
        guard let apiService = application.obacoService else { return }

        Task {
            do {
                let forecast = try await apiService.getWeather()
                await MainActor.run {
                    self.forecast = forecast
                }
            } catch {
                weatherButton.isHidden = true
                Logger.error(error.localizedDescription)
            }
        }
    }

    // MARK: - Long Press Gesture

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        // Only handle the began state to avoid multiple pins
        guard gesture.state == .began else { return }
        mapRegionManager.userPressedMap(gesture)
    }

    // MARK: - Trip Planner

    private var semiModalTripPlannerController: FloatingPanelController?

    private var tripPlanner: TripPlanner?
    private var tripPlannerHostingController: UIViewController?
    private lazy var tripPlannerMapView: MKMapView = {
        let mapView = MKMapView.autolayoutNew()
        mapView.alpha = 0
        view.insertSubview(mapView, belowSubview: mapRegionManager.mapView)
        mapView.pinToSuperview(.edges)
        return mapView
    }()

    private func showTripPlannerMapView() {
        tripPlannerMapView.mapType = mapRegionManager.mapView.mapType

        tripPlannerMapView.isHidden = false

        UIView.animate(withDuration: 0.3) {
            self.mapRegionManager.mapView.alpha = 0
            self.tripPlannerMapView.alpha = 1
        } completion: { _ in
            self.mapRegionManager.mapView.isHidden = true
        }
    }

    private func hideTripPlannerMapView() {
        mapRegionManager.mapView.mapType = tripPlannerMapView.mapType
        mapRegionManager.mapView.region = tripPlannerMapView.region

        mapRegionManager.mapView.isHidden = false

        UIView.animate(withDuration: 0.3) {
            self.mapRegionManager.mapView.alpha = 1
            self.tripPlannerMapView.alpha = 0
        } completion: { _ in
            self.tripPlannerMapView.isHidden = true
        }
    }

    private func buildTripPlanner(otpURL: URL) -> TripPlanner {
        let config = OTPConfiguration(
            otpServerURL: otpURL,
            themeConfiguration: .init(
                primaryColor: Color(uiColor: ThemeColors().brand)
            )
        )

        let apiService = RestAPIService(baseURL: otpURL)
        let mapViewProvider = MKMapViewAdapter(mapView: tripPlannerMapView)

        let tripPlanner = TripPlanner(
            otpConfig: config,
            apiService: apiService,
            mapProvider: mapViewProvider,
            notificationCenter: application.notificationCenter
        )

        return tripPlanner
    }

    func showTripPlanner(destination: MKMapItem? = nil) {
        guard let currentRegion = application.regionsService.currentRegion,
              let otpURL = currentRegion.openTripPlannerURL else {
            return
        }

        // Get current location for origin
        var origin: Location?
        if let currentLocation = application.locationService.currentLocation {
            origin = Location(
                title: "Current Location",
                subTitle: "Your current location",
                latitude: currentLocation.coordinate.latitude,
                longitude: currentLocation.coordinate.longitude
            )
        }

        // Convert MKMapItem destination to Location if provided
        var destinationLocation: Location?
        if let destination {
            destinationLocation = Location(
                title: destination.name ?? "Destination",
                subTitle: destination.placemark.title ?? "",
                latitude: destination.placemark.coordinate.latitude,
                longitude: destination.placemark.coordinate.longitude
            )
        }

        subscribeToTripPlannerNotifications()

        let tripPlanner = buildTripPlanner(otpURL: otpURL)

        let tripPlannerView = tripPlanner.createTripPlannerView(origin: origin, destination: destinationLocation) { [weak self] in
            guard let self else { return }
            self.dismissTripPlannerController()
        }

        self.floatingPanel.move(to: .tip, animated: true)

        let hostingController = UIHostingController(rootView: tripPlannerView)
        hostingController.view.backgroundColor = .clear

        let semiModal = createSemiModalPanel(childController: hostingController)
        semiModal.addPanel(toParent: self)
        self.semiModalTripPlannerController = semiModal
        self.tripPlanner = tripPlanner
        self.tripPlannerHostingController = hostingController
    }

    private func dismissTripPlannerController() {
        guard let tripPlannerHostingController else { return }
        dismissModalController(tripPlannerHostingController)

        self.semiModalTripPlannerController = nil
        self.tripPlannerHostingController = nil
        self.tripPlanner = nil
        hideTripPlannerMapView()

        unsubscribeFromTripPlannerNotifications()
    }

    private func subscribeToTripPlannerNotifications() {
        application.notificationCenter.addObserver(self, selector: #selector(itinerariesUpdated), name: Notifications.itinerariesUpdated, object: nil)
        application.notificationCenter.addObserver(self, selector: #selector(itineraryPreviewStarted), name: Notifications.itineraryPreviewStarted, object: nil)
        application.notificationCenter.addObserver(self, selector: #selector(itineraryPreviewEnded), name: Notifications.itineraryPreviewEnded, object: nil)
        application.notificationCenter.addObserver(self, selector: #selector(tripStarted), name: Notifications.tripStarted, object: nil)
    }

    private func unsubscribeFromTripPlannerNotifications() {
        application.notificationCenter.removeObserver(self, name: Notifications.itinerariesUpdated, object: nil)
        application.notificationCenter.removeObserver(self, name: Notifications.itineraryPreviewStarted, object: nil)
        application.notificationCenter.removeObserver(self, name: Notifications.itineraryPreviewEnded, object: nil)
        application.notificationCenter.removeObserver(self, name: Notifications.tripStarted, object: nil)
    }

    @objc private func itinerariesUpdated(_ note: NSNotification) {
        semiModalTripPlannerController?.move(to: .full, animated: true)
    }

    @objc private func itineraryPreviewStarted(_ note: NSNotification) {
        // nop
    }

    @objc private func itineraryPreviewEnded(_ note: NSNotification) {
        //
    }

    @objc private func tripStarted(_ note: NSNotification) {
        showTripPlannerMapView()

        semiModalTripPlannerController?.move(to: .tip, animated: true)
    }

    // MARK: - Map Type
    public lazy var toggleMapTypeButton: UIButton = {
        let button = UIButton(type: .system)
        button.addTarget(self, action: #selector(toggleMapType), for: .touchUpInside)
        button.accessibilityLabel = OBALoc("map_controller.map_type.accessibility_label", value: "Map type", comment: "Voiceover text indicating that this button toggles the base map type.")
        return button
    }()

    @objc private func toggleMapType() {
        if application.mapRegionManager.userSelectedMapType == .mutedStandard {
            application.mapRegionManager.userSelectedMapType = .hybrid
        } else {
            application.mapRegionManager.userSelectedMapType = .mutedStandard
        }

        setMapTypeButtonImage(toggleMapTypeButton)
    }

    private func setMapTypeButtonImage(_ button: UIButton) {
        if application.mapRegionManager.userSelectedMapType == .mutedStandard {
            button.setImage(UIImage(systemName: "map"), for: .normal)
            button.accessibilityValue = OBALoc("map_controller.map_type.standard.accessibility_value", value: "standard", comment: "Voiceover text indicating the current map type as the standard base map.")
        } else {
            button.setImage(UIImage(systemName: "globe"), for: .normal)
            button.accessibilityValue = OBALoc("map_controller.map_type.hybrid.accessibility_value", value: "hybrid", comment: "Voiceover text indicating the current map type as the hybrid base map (satellite view with labels).")
        }
    }

    // MARK: - Application State

    private var resignedActiveAt: Date?

    @objc func applicationWillResignActive(_ notification: NSNotification) {
        resignedActiveAt = Date()
    }

    @objc func applicationDidBecomeActive(_ notification: NSNotification) {
        guard
            let resignedActiveAt = resignedActiveAt,
            abs(resignedActiveAt.timeIntervalSinceNow) > 600
        else {
            return
        }

        centerMapOnUserLocation()
    }

    // MARK: - Content Presentation

    /// Displays the specified stop.
    ///
    /// - Parameter stop: The stop to display.
    func show(stop: Stop) {
        application.viewRouter.navigateTo(stop: stop, from: self)
    }

    // MARK: - Overlays

    private let mapStatusView = MapStatusView.autolayoutNew()

    /// Sets the margins for the map view to keep the scale and legal info within the viewable area.
    /// Call this when you modify top level UI.
    func layoutMapMargins() {
        if traitCollection.horizontalSizeClass == .regular {
            self.mapRegionManager.mapView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: MapPanelLandscapeLayout.WidthSize + ThemeMetrics.padding, bottom: 0, trailing: 0)
        } else {
            self.mapRegionManager.mapView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: MapPanelLayout.EstimatedDrawerTipStateHeight, trailing: 0)
        }
    }

    // MARK: - Semi Modals

    private var semiModalPanel: FloatingPanelController?

    private func createFloatingPanelSurfaceAppearance() -> SurfaceAppearance {
        let appearance = SurfaceAppearance()
        appearance.cornerRadius = ThemeMetrics.cornerRadius
        appearance.backgroundColor = .clear
        return appearance
    }

    private func createSemiModalPanel(childController: UIViewController) -> FloatingPanelController {
        let panel = FloatingPanelController()
        panel.surfaceView.appearance = createFloatingPanelSurfaceAppearance()

        // Set a content view controller.
        panel.set(contentViewController: childController)

        panel.contentInsetAdjustmentBehavior = .never

        if let scrollableChildController = childController as? Scrollable {
            panel.track(scrollView: scrollableChildController.scrollView)
        }

        return panel
    }

    private func removeSemiModalPanel(_ panel: FloatingPanelController, animated: Bool = true) {
        panel.willMove(toParent: nil)

        panel.hide(animated: animated) {
            panel.view.removeFromSuperview()
            panel.removeFromParent()
        }
    }

    private func showSemiModalPanel(childController: UIViewController) {
        semiModalPanel?.removePanelFromParent(animated: false)

        let panel = createSemiModalPanel(childController: childController)
        panel.addPanel(toParent: self)

        semiModalPanel = panel
    }

    // MARK: - Floating Panel Controller

    /// The floating panel controller, which displays a drawer at the bottom of the map.
    private lazy var floatingPanel: OBAFloatingPanelController = {
        let panel = OBAFloatingPanelController(application, delegate: self)
        panel.isRemovalInteractionEnabled = false
        panel.surfaceView.appearance = createFloatingPanelSurfaceAppearance()

        // Set a content view controller.
        panel.set(contentViewController: mapPanelController)

        panel.contentMode = .fitToBounds

        // Content Inset Adjustment + OBAListView don't play well together and causes undefined behavior,
        // as described in "OBAListView "sticky" row behavior while scrolling in panel" (#321)
        panel.contentInsetAdjustmentBehavior = .never

        return panel
    }()

    public func floatingPanel(_ vc: FloatingPanelController, layoutFor newCollection: UITraitCollection) -> FloatingPanelLayout {
        switch newCollection.horizontalSizeClass {
        case .regular:
            return MapPanelLandscapeLayout(initialState: .half)
        default:
            return MapPanelLayout(initialState: .tip)
        }
    }

    public func floatingPanelDidChangeState(_ vc: FloatingPanel.FloatingPanelController) {
        // Don't allow the status overlay to be shown when the
        // Floating Panel is fully open because it looks weird.
        let floatingPanelPositionIsCollapsed = vc.state == .tip || vc.state == .hidden
        mapPanelController.currentScrollView?.accessibilityElementsHidden = floatingPanelPositionIsCollapsed

        if let controller = vc.contentViewController as? MapFloatingPanelController {
            controller.didCollapse(floatingPanelPositionIsCollapsed)
        }

        // Disables voiceover interacting with map elements (such as streets and POIs).
        // See #431.
        mapRegionManager.mapView.accessibilityElementsHidden = !floatingPanelPositionIsCollapsed

        if mapPanelController.inSearchMode && floatingPanelPositionIsCollapsed {
            mapPanelController.exitSearchMode()
        }
    }

    func updateVoiceover() {
        mapRegionManager.preferredLoadDataRegionFudgeFactor = UIAccessibility.isVoiceOverRunning ? 1.5 : MapRegionManager.DefaultLoadDataRegionFudgeFactor

        if UIAccessibility.isVoiceOverRunning {
            floatingPanel.move(to: .full, animated: true)

            if !floatingPanel.userHasSeenFullSheetVoiceoverChange {
                self.present(floatingPanel.fullSheetVoiceoverAlert(), animated: true)
                floatingPanel.userHasSeenFullSheetVoiceoverChange = true
            }
        }
    }

    // MARK: - Modal Delegate

    public func dismissModalController(_ controller: UIViewController) {
        // TODO: this is clearly buggy. Fix it.
        if controller == semiModalPanel?.contentViewController {
            mapRegionManager.cancelSearch()
            semiModalPanel?.removePanelFromParent(animated: true)
        }
        else {
            controller.dismiss(animated: true, completion: nil)
        }
    }

    // MARK: - Map Item Controller

    private var semiModalMapItemController: FloatingPanelController?

    /// Presents a `MapItemController` with the provided `MKMapItem` as a semi-modal panel.
    /// - Parameter mapItem: The map item to display
    private func displayMapItemController(_ mapItem: MKMapItem) {
        let viewModel = MapItemViewModel(mapItem: mapItem, application: application, delegate: self) { [weak self] in
            guard let self else { return }

            if let semiModalMapItemController = self.semiModalMapItemController {
                self.removeSemiModalPanel(semiModalMapItemController, animated: true)
            }

            self.showTripPlanner(destination: mapItem)
            self.semiModalPanel?.move(to: .tip, animated: false)
        }

        self.floatingPanel.move(to: .tip, animated: true)

        let mapItemController = MapItemViewController(viewModel)
        let semiModal = createSemiModalPanel(childController: mapItemController)
        semiModal.addPanel(toParent: self)
        self.semiModalMapItemController = semiModal
    }

    // MARK: - Map Panel Controller

    private lazy var mapPanelController = MapFloatingPanelController(application: application, mapRegionManager: application.mapRegionManager, delegate: self)

    func mapPanelController(_ controller: MapFloatingPanelController, didSelectStop stopID: Stop.ID) {
        application.viewRouter.navigateTo(stopID: stopID, from: self)
    }

    func mapPanelController(_ controller: MapFloatingPanelController, didSelectMapItem mapItem: MKMapItem) {
        floatingPanel.move(to: .half, animated: false)

        let mapDestination = mapItem.placemark.coordinate

        let animated: Bool
        if let currentLocation = application.locationService.currentLocation {
            let distance = mapDestination.distance(from: currentLocation.coordinate)
            animated = distance <= 1609 // roughly 1 mile
        }
        else {
            animated = false
        }

        mapRegionManager.mapView.setCenter(mapDestination, animated: animated)
        displayMapItemController(mapItem)
    }

    func mapPanelControllerDisplaySearch(_ controller: MapFloatingPanelController) {
        floatingPanel.move(to: .full, animated: true)
    }

    func mapPanelControllerDidChangeChildViewController(_ controller: MapFloatingPanelController) {
        // If there is a new scroll view, tell floating panel to track the new scroll view.
        // Else, untrack its currently tracking scroll view.
        if let newScrollView = controller.currentScrollView {
            floatingPanel.track(scrollView: newScrollView)
        } else if let currentTrackingScrollView = floatingPanel.trackingScrollView {
            floatingPanel.untrack(scrollView: currentTrackingScrollView)
        }
    }

    func mapPanelController(_ controller: MapFloatingPanelController, moveTo state: FloatingPanelState, animated: Bool) {
        floatingPanel.move(to: state, animated: animated)
    }

    // MARK: - MapRegionDelegate

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        if let region = view.annotation as? Region {
            let title = OBALoc("map_controller.change_region_alert.title", value: "Change Region?", comment: "Title of the alert that appears when the user is updating their current region manually.")
            let messageFmt = OBALoc("map_controller.change_region_alert.message_fmt", value: "Would you like to change your region to %@?", comment: "Body of the alert that appears when the user is updating their current region manually.")
            let alert = UIAlertController(title: title, message: String(format: messageFmt, region.name), preferredStyle: .alert)
            alert.addAction(UIAlertAction.cancelAction)
            alert.addAction(UIAlertAction(title: OBALoc("map_controller.change_region_alert.button", value: "Change Region", comment: "Change Region button on the alert that appears when the user is updating their current region manually."), style: .default, handler: { _ in
                self.application.regionsService.automaticallySelectRegion = false
                self.application.regionsService.currentRegion = region
            }))

            present(alert, animated: true) {
                mapView.deselectAnnotation(view.annotation, animated: true)
            }
        } else if let stop = view.annotation as? Stop, UIAccessibility.isVoiceOverRunning {
            // When VoiceOver is running, StopAnnotationView does not display a callout due to
            // VoiceOver limitations with MKMapView. Therefore, we should skip any callouts
            // and just go directly to pushing the stop onto the navigation stack.
            application.analytics?.reportEvent(pageURL: "app://localhost/map", label: AnalyticsLabels.mapStopAnnotationTapped, value: nil)
            show(stop: stop)
        }
    }

    func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
        // nop.
    }

    func mapRegionManager(_ manager: MapRegionManager, customize stopAnnotationView: StopAnnotationView) {
        if stopAnnotationView.interactions.count == 0 {
            let interaction = UIContextMenuInteraction(delegate: self)
            stopAnnotationView.addInteraction(interaction)
        }
    }

    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        if let stop = view.annotation as? Stop {
            application.analytics?.reportEvent(pageURL: "app://localhost/map", label: AnalyticsLabels.mapStopAnnotationTapped, value: nil)
            show(stop: stop)
        } else if let bookmark = view.annotation as? Bookmark {
            application.analytics?.reportEvent(pageURL: "app://localhost/map", label: AnalyticsLabels.mapStopAnnotationTapped, value: nil)
            show(stop: bookmark.stop)
        }
    }

    public func mapRegionManager(_ manager: MapRegionManager, noSearchResults response: SearchResponse) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await AlertPresenter.show(errorMessage: OBALoc("map_controller.no_search_results_found", value: "No search results were found.", comment: "A generic message shown when the user's search query produces no search results."), presentingController: self)
        }
    }

    public func mapRegionManager(_ manager: MapRegionManager, disambiguateSearch response: SearchResponse) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let searchResults = SearchResultsController(searchResponse: response, application: application, delegate: self)
            let nav = UINavigationController(rootViewController: searchResults)
            application.viewRouter.present(nav, from: self, isModal: true)
        }
    }

    public func mapRegionManager(_ manager: MapRegionManager, showSearchResult response: SearchResponse) {
        Task { @MainActor [weak self] in
            guard let self, let result = response.results.first else { return }

            switch result {
            case let result as MKMapItem:
                displayMapItemController(result)
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
                    let msg = OBALoc("map_controller.vehicle_not_on_trip_error", value: "The vehicle you chose doesn't appear to be on a trip right now, which means we don't know how to show it to you.", comment: "This message appears when a searched-for vehicle doesn't have an assigned trip.")
                    await AlertPresenter.show(errorMessage: msg, presentingController: self)
                }
            default:
                fatalError()
            }
        }
    }

    @objc public func mapRegionManagerShowZoomInStatus(_ manager: MapRegionManager, showStatus: Bool) {
        mapStatusView.configure(
            for: mapStatusView.state(for: application.locationService),
            zoomInStatus: showStatus
        )
    }

    // MARK: Loading Indicator

    lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator: UIActivityIndicatorView

        indicator = UIActivityIndicatorView(style: .medium)
        indicator.color = ThemeColors.shared.brand

        indicator.hidesWhenStopped = true
        return indicator
    }()

    var loadingIndicatorTimer: Timer?

    public func mapRegionManagerDataLoadingStarted(_ manager: MapRegionManager) {
        // If loading takes more than a second, show the activity indicator.
        loadingIndicatorTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            UIView.transition(with: self.toolbar.stackView, duration: 0.25, options: .allowAnimatedContent, animations: {
                self.toolbar.stackView.addArrangedSubview(self.loadingIndicator)
                self.loadingIndicator.startAnimating()
            })
        }
    }

    public func mapRegionManagerDataLoadingFinished(_ manager: MapRegionManager) {
        loadingIndicatorTimer?.invalidate()
        loadingIndicatorTimer = nil

        UIView.transition(with: self.toolbar.stackView, duration: 0.25, options: .allowAnimatedContent, animations: {
            self.toolbar.stackView.removeArrangedSubview(self.loadingIndicator)
            self.loadingIndicator.stopAnimating()
        })
    }

    public func mapRegionManagerDismissSearch(_ manager: MapRegionManager) {
        mapPanelController.exitSearchMode()
    }

    // MARK: - LocationServiceDelegate

    private var initialMapChangeMade = false

    private var promptUserOnRegionMismatch = true

    private static let programmaticRadiusInMeters = 200.0

    private var regionMismatchBulletin: RegionMismatchBulletin?

    /// Updates the visible area on the map view based on the user's selected `Region` and current location.
    private func updateVisibleMapRect() {
        guard let currentRegion = application.regionsService.currentRegion else { return }

        if let location = application.locationService.currentLocation, promptUserOnRegionMismatch {
            if currentRegion.contains(location: location) {
                programmaticallyUpdateVisibleMapRegion(location: location)
            }
            else {
                promptUserOnRegionMismatch = false
                if let regionMismatchBulletin = RegionMismatchBulletin(application: application),
                   let uiApp = application.delegate?.uiApplication {
                    self.regionMismatchBulletin = regionMismatchBulletin
                    self.regionMismatchBulletin?.show(in: uiApp)
                }
            }
        }
        else if let lastVisibleRegion = mapRegionManager.lastVisibleMapRect {
            mapRegionManager.mapView.visibleMapRect = lastVisibleRegion
        }
        else {
            mapRegionManager.mapView.visibleMapRect = currentRegion.serviceRect
        }
    }

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

    public func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus) {
        mapStatusView.configure(with: service)
        layoutMapMargins()
        locationButton.isHidden = !service.isLocationUseAuthorized
    }

    // MARK: - Context Menus

    public func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard
            let annotationView = interaction.view as? MKAnnotationView,
            let stop = annotationView.annotation as? Stop
        else { return nil }

        let previewController = { () -> UIViewController in
            let stopController = StopViewController(application: self.application, stop: stop)
            stopController.enterPreviewMode()
            return stopController
        }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: previewController, actionProvider: nil)
    }

    public func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
        guard let viewController = animator.previewViewController else { return }

        animator.addCompletion {
            if let previewable = viewController as? Previewable {
                previewable.exitPreviewMode()
            }

            self.application.viewRouter.navigate(to: viewController, from: self, animated: false)
        }
    }

    public func largeContentViewerInteraction(_ interaction: UILargeContentViewerInteraction, didEndOn item: UILargeContentViewerItem?, at point: CGPoint) {
        if mapStatusView.frame.contains(point) {
            didTapMapStatus(interaction)
        }
    }
}

// swiftlint:enable file_length
