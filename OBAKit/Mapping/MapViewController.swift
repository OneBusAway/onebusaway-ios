//
//  MapViewController.swift
//  OBANext
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import MapKit
import FloatingPanel
import OBAKitCore

/// Displays a map, a set of stops rendered as annotation views, and the user's location if authorized.
///
/// `MapViewController` is the average user's primary means of interacting with OneBusAway data.
public class MapViewController: UIViewController,
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
        weatherOperation?.cancel()
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

        if #available(iOS 15.0, *) {
            let appearance = UITabBarAppearance()
            appearance.configureWithDefaultBackground()
            tabBarItem.scrollEdgeAppearance = appearance
        }

        view.insertSubview(toolbar, aboveSubview: mapView)

        NSLayoutConstraint.activate([
            toolbar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -ThemeMetrics.controllerMargin),
            toolbar.topAnchor.constraint(equalTo: mapStatusView.bottomAnchor, constant: ThemeMetrics.controllerMargin),
            toolbar.widthAnchor.constraint(equalToConstant: 42.0),
            locationButton.heightAnchor.constraint(equalTo: locationButton.widthAnchor),
            weatherButton.heightAnchor.constraint(equalTo: weatherButton.widthAnchor),
            toggleMapTypeButton.heightAnchor.constraint(equalTo: toggleMapTypeButton.widthAnchor)
        ])

        mapRegionManager.statusOverlay = statusOverlay
        view.addSubview(statusOverlay)

        NSLayoutConstraint.activate([
            statusOverlay.bottomAnchor.constraint(equalTo: floatingPanel.surfaceView.topAnchor, constant: -ThemeMetrics.padding),
            statusOverlay.leadingAnchor.constraint(equalTo: floatingPanel.surfaceView.leadingAnchor, constant: ThemeMetrics.padding),
            statusOverlay.trailingAnchor.constraint(equalTo: floatingPanel.surfaceView.trailingAnchor, constant: -ThemeMetrics.padding)
        ])
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
        application.analytics?.reportEvent?(.userAction, label: AnalyticsLabels.mapShowUserLocationButtonTapped, value: nil)
        centerMapOnUserLocation()
    }

    func centerMapOnUserLocation() {
        guard isLoadedAndOnScreen else { return }
        let userLocation = mapRegionManager.mapView.userLocation
        guard userLocation.isValid else { return }

        var zoomLevel = 17

        if #available(iOS 14.0, *), application.locationService.accuracyAuthorization == .reducedAccuracy {
            zoomLevel = 11
        }

        mapRegionManager.mapView.setCenterCoordinate(centerCoordinate: userLocation.coordinate, zoomLevel: zoomLevel, animated: true)

        // It is possible to activate the center map button via Voiceover. When the user
        // centers the map on their location, partially collapse the sheet to enable mapview interaction.
        if floatingPanel.position == .full {
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
            alert.addAction(title: OBALoc("locationservices_alert_request_access.button", value: "Allow Access to Location", comment: "")) { _ in
                self.application.locationService.requestInUseAuthorization()
            }
            alert.addAction(keepLocationOffButton)
        case .locationServicesOff:
            alert.addAction(goToSettingsButton)
            alert.addAction(keepLocationOffButton)
        case .impreciseLocation:
            alert.addAction(goToSettingsButton)
            if #available(iOS 14, *) {
                alert.addAction(title: OBALoc("locationservices_alert_request_precise_location_once.button", value: "Allow Once", comment: "")) { _ in
                    self.application.locationService.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "MapStatusView")
                }
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

        let alert = UIAlertController(title: forecast.todaySummary, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction.dismissAction)
        present(alert, animated: true, completion: nil)
    }

    private var weatherOperation: DecodableOperation<WeatherForecast>?

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

        let op = apiService.getWeather()
        op.complete { [weak self] result in
            guard let self = self else { return }

            self.forecast = try? result.get()
            if case let .failure(error) = result {
                Logger.error(error.localizedDescription)
            }
        }
        weatherOperation = op
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

    private let statusOverlay = StatusOverlayView.autolayoutNew()
    private let mapStatusView = MapStatusView.autolayoutNew()

    /// Sets the margins for the map view to keep the scale and legal info within the viewable area.
    /// Call this when you modify top level UI.
    func layoutMapMargins() {
        let panelViewHeight = floatingPanel.layout.insetFor(position: .tip) ?? 0

        let top = mapStatusView.frame.height - view.safeAreaInsets.top
        let bottom = panelViewHeight + ThemeMetrics.compactPadding

        if traitCollection.horizontalSizeClass == .regular {
            self.mapRegionManager.mapView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: top, leading: MapPanelLandscapeLayout.WidthSize + ThemeMetrics.padding, bottom: 0, trailing: 0)
        } else {
            self.mapRegionManager.mapView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: top, leading: 0, bottom: bottom, trailing: 0)
        }
    }

    // MARK: - Floating Panel Controller

    private var semiModalPanel: FloatingPanelController?

    private func showSemiModalPanel(childController: UIViewController) {
        semiModalPanel?.removePanelFromParent(animated: false)

        let panel = FloatingPanelController()
        panel.surfaceView.cornerRadius = ThemeMetrics.cornerRadius
        panel.surfaceView.backgroundColor = .clear

        // Set a content view controller.
        panel.set(contentViewController: childController)

        if childController is Scrollable {
            panel.track(scrollView: (childController as! Scrollable).scrollView) // swiftlint:disable:this force_cast
        }

        panel.addPanel(toParent: self, belowView: nil, animated: true)

        semiModalPanel = panel
    }

    /// The floating panel controller, which displays a drawer at the bottom of the map.
    private lazy var floatingPanel: OBAFloatingPanelController = {
        let panel = OBAFloatingPanelController(application, delegate: self)
        panel.isRemovalInteractionEnabled = false
        panel.surfaceView.cornerRadius = ThemeMetrics.cornerRadius
        panel.surfaceView.backgroundColor = .clear

        // Set a content view controller.
        panel.set(contentViewController: mapPanelController)

        // Track a scroll view (or the siblings) in the content view controller.
        panel.track(scrollView: mapPanelController.listView)

        return panel
    }()

    public func floatingPanel(_ vc: FloatingPanelController, layoutFor newCollection: UITraitCollection) -> FloatingPanelLayout? {
        switch newCollection.horizontalSizeClass {
        case .regular:
            return MapPanelLandscapeLayout(initialPosition: .half)
        default:
            return MapPanelLayout(initialPosition: .tip)
        }
    }

    public func floatingPanelDidChangePosition(_ vc: FloatingPanel.FloatingPanelController) {
        // Don't allow the status overlay to be shown when the
        // Floating Panel is fully open because it looks weird.
        let floatingPanelPositionIsCollapsed = vc.position == .tip || vc.position == .hidden
        statusOverlay.isHidden = vc.position == .full
        mapPanelController.listView.accessibilityElementsHidden = floatingPanelPositionIsCollapsed

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

    // MARK: - Map Panel Controller

    private lazy var mapPanelController = MapFloatingPanelController(application: application, mapRegionManager: application.mapRegionManager, delegate: self)

    func mapPanelController(_ controller: MapFloatingPanelController, didSelectStop stopID: Stop.ID) {
        application.viewRouter.navigateTo(stopID: stopID, from: self)
    }

    func mapPanelControllerDisplaySearch(_ controller: MapFloatingPanelController) {
        floatingPanel.move(to: .full, animated: true)
    }

    func mapPanelController(_ controller: MapFloatingPanelController, moveTo position: FloatingPanelPosition, animated: Bool) {
        floatingPanel.move(to: position, animated: animated)
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
            application.analytics?.reportEvent?(.userAction, label: AnalyticsLabels.mapStopAnnotationTapped, value: nil)
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
            application.analytics?.reportEvent?(.userAction, label: AnalyticsLabels.mapStopAnnotationTapped, value: nil)
            show(stop: stop)
        } else if let bookmark = view.annotation as? Bookmark {
            application.analytics?.reportEvent?(.userAction, label: AnalyticsLabels.mapStopAnnotationTapped, value: nil)
            show(stop: bookmark.stop)
        }
    }

    public func mapRegionManager(_ manager: MapRegionManager, noSearchResults response: SearchResponse) {
        AlertPresenter.show(errorMessage: OBALoc("map_controller.no_search_results_found", value: "No search results were found.", comment: "A generic message shown when the user's search query produces no search results."), presentingController: self)
    }

    public func mapRegionManager(_ manager: MapRegionManager, disambiguateSearch response: SearchResponse) {
        let searchResults = SearchResultsController(searchResponse: response, application: application, delegate: self)
        let nav = UINavigationController(rootViewController: searchResults)
        application.viewRouter.present(nav, from: self, isModal: true)
    }

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
                let msg = OBALoc("map_controller.vehicle_not_on_trip_error", value: "The vehicle you chose doesn't appear to be on a trip right now, which means we don't know how to show it to you.", comment: "This message appears when a searched-for vehicle doesn't have an assigned trip.")
                AlertPresenter.show(errorMessage: msg, presentingController: self)
            }
        default:
            fatalError()
        }
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
                if
                    let regionMismatchBulletin = RegionMismatchBulletin(application: application),
                    let uiApp = application.delegate?.uiApplication
                {
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
