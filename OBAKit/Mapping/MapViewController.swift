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
import Combine
import FloatingPanel
import OBAKitCore
import SwiftUI
import OTPKit
import SafariServices

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
    UILargeContentViewerInteractionDelegate,
    UIGestureRecognizerDelegate {

    // MARK: - Hoverbar

    lazy var toolbar: HoverBar = {
        let hover = HoverBar.autolayoutNew()
        hover.tintColor = ThemeColors.shared.label
        hover.stackView.addArrangedSubview(locationButton)

        locationButton.isHidden = !application.locationService.isLocationUseAuthorized

        hover.stackView.addArrangedSubview(HoverBarSeparator())
        hover.stackView.addArrangedSubview(toggleMapTypeButton)
        setMapTypeButtonImage(toggleMapTypeButton, mapType: viewModel.mapType)

        if application.features.obaco == .running {
            hover.stackView.addArrangedSubview(HoverBarSeparator())
            hover.stackView.addArrangedSubview(weatherButton)
        }

        hover.stackView.addArrangedSubview(HoverBarSeparator())
        hover.stackView.addArrangedSubview(myTripButton)

        return hover
    }()

    // MARK: - Data

    let application: Application

    var mapRegionManager: MapRegionManager {
        return application.mapRegionManager
    }

    let viewModel: MapViewModel
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Surveys

    private var surveyCardView: SurveyLauncherCardView?

    // MARK: - Init

    public init(application: Application) {
        self.application = application
        let initialMapType = MapBaseType(application.mapRegionManager.userSelectedMapType)
        self.viewModel = MapViewModel(application: application, initialMapType: initialMapType)

        super.init(nibName: nil, bundle: nil)

        title = Strings.map
        tabBarItem.image = Icons.mapTabIcon
        tabBarItem.selectedImage = Icons.mapSelectedTabIcon

        // Assign delegates
        self.application.mapRegionManager.addDelegate(self)
        self.application.locationService.addDelegate(self)
        self.application.regionsService.addDelegate(self)

        self.application.notificationCenter.addObserver(self, selector: #selector(applicationDidBecomeActive(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)
        self.application.notificationCenter.addObserver(self, selector: #selector(applicationWillResignActive(_:)), name: UIApplication.willResignActiveNotification, object: nil)
        self.application.notificationCenter.addObserver(self, selector: #selector(reloadBookmarkAnnotations), name: .bookmarksDidChange, object: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    isolated deinit {
        application.mapRegionManager.removeDelegate(self)
        application.locationService.removeDelegate(self)
        application.regionsService.removeDelegate(self)
        application.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - UIViewController

    public override func viewDidLoad() {
        super.viewDidLoad()

        let mapView = mapRegionManager.mapView
        view.addSubview(mapView)
        mapView.pinToSuperview(.edges)

        mapStatusView.configure(with: application.locationService)

        let statusTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleMapStatusTap(_:)))
        mapStatusView.addGestureRecognizer(statusTapGesture)

        view.addSubview(mapStatusView)

        mapStatusView.addInteraction(UILargeContentViewerInteraction(delegate: self))

        floatingPanel.addPanel(toParent: self)

        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        tabBarItem.scrollEdgeAppearance = appearance

        // Add toolbar before constraining the status pill, since the pill's
        // trailing constraint references toolbar.leadingAnchor.
        view.insertSubview(toolbar, aboveSubview: mapView)

        // Toolbar: anchored to safe area top-right, independent of status pill.
        // This matches Apple Maps where right-side buttons stay fixed regardless
        // of whether a floating status element is visible.
        NSLayoutConstraint.activate([
            toolbar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -ThemeMetrics.controllerMargin),
            toolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: ThemeMetrics.controllerMargin),
            toolbar.widthAnchor.constraint(equalToConstant: 42.0),
            locationButton.heightAnchor.constraint(equalTo: locationButton.widthAnchor),
            weatherButton.heightAnchor.constraint(equalTo: weatherButton.widthAnchor),
            toggleMapTypeButton.heightAnchor.constraint(equalTo: toggleMapTypeButton.widthAnchor),
            myTripButton.heightAnchor.constraint(equalTo: myTripButton.widthAnchor)
        ])

        // Status pill: centered horizontally, anchored to safe area top.
        // Max width prevents overflow on long status text or large Dynamic Type.
        // Trailing constraint keeps the pill from overlapping the toolbar on narrow devices.
        NSLayoutConstraint.activate([
            mapStatusView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            mapStatusView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: ThemeMetrics.padding),
            mapStatusView.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.85),
            mapStatusView.trailingAnchor.constraint(lessThanOrEqualTo: toolbar.leadingAnchor, constant: -ThemeMetrics.padding),
        ])

        // Long press gesture to add a pin to the map

        longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.5
        longPressGesture.delegate = self
        mapView.addGestureRecognizer(longPressGesture)

        configureMapLayers()
        NotificationCenter.default.addObserver(self, selector: #selector(mapLayerStateDidChange(_:)), name: .mapLayerEnabledStateDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(mapLayerStateDidChange(_:)), name: .mapLayerAvailabilityDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(rentalRangeFilterDidChange(_:)), name: .rentalRangeFilterDidChange, object: nil)

        bindViewModel()
    }

    private func bindViewModel() {
        bindWeather()
        bindMapStatus()
        bindMapType()
        bindSurveyPrompt()
    }

    private func bindSurveyPrompt() {
        viewModel.surveyToPresent
            .receive(on: DispatchQueue.main)
            .sink { [weak self] survey in self?.presentSurvey(survey) }
            .store(in: &cancellables)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Only one map will be visible on screen at any given time,
        // and so we can swap this delegate on the MapRegionManager
        // at different times. I think this expectation will become
        // unfounded when UIScene gets adopted in the app. TODO.
        application.mapRegionManager.mapViewDelegate = self
        viewModel.reloadBookmarks()

        // Settings is the only thing that can change the callout rule, and getting back here is
        // the first thing that happens after it closes.
        application.mapRegionManager.refreshStopAnnotationCallouts()

        navigationController?.setNavigationBarHidden(true, animated: false)

        updateVisibleMapRect()
        layoutMapMargins()

    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        viewModel.start()
        updateVoiceover()
        showMapLayersNudgeIfNeeded()
        Task { @MainActor [weak viewModel] in await viewModel?.checkForSurveyPrompt() }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        navigationController?.setNavigationBarHidden(false, animated: false)

        // A rider who dismisses a stop sheet and immediately switches tabs shouldn't be
        // chased by an alert from a screen they've left.
        cancelScheduledFeedbackPrompt()
    }

    // MARK: - Surveys

    /// Called from `bindViewModel()` when `MapViewModel.surveyToPresent` emits.
    /// The VM owns "once per session" + reminder scheduling; the VC owns the UI.
    private func presentSurvey(_ survey: Survey) {
        // Guard against a stray double-emit from racing the floating card. If
        // a card is already up, tell the VM we didn't present so it rolls back
        // its session flag and a later check can re-emit.
        guard surveyCardView == nil else {
            viewModel.didPresentSurveyPrompt(survey, presented: false)
            return
        }
        presentMapSurveyCard(for: survey)
        // Reminder advances on confirmed presentation; the VM rolls back its
        // session flag if `presented` is false.
        viewModel.didPresentSurveyPrompt(survey, presented: true)
    }

    /// Presents the floating survey launcher card above the search panel. The
    /// card is the single entry point for every map survey: tapping `Take survey`
    /// opens an external survey, or presents the full in-app survey for others.
    private func presentMapSurveyCard(for survey: Survey) {
        var title = survey.name
        if survey.isExternalSurvey, let hero = survey.heroQuestion {
            title = hero.content.labelText
        }
        let card = SurveyLauncherCardView(style: .floating)
        card.configure(title: title, subtitle: nil)
        card.onTakeSurvey = { [weak self] in self?.handleMapSurveyTakeSurvey(survey) }
        card.onDismiss = { [weak self] in self?.handleMapSurveyDismiss(survey) }

        // 16pt insets and gap above the search panel, per the design handoff.
        let cardInset: CGFloat = 16.0
        view.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: cardInset),
            card.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -cardInset),
            card.bottomAnchor.constraint(equalTo: floatingPanel.surfaceView.topAnchor, constant: -cardInset)
        ])
        surveyCardView = card

        card.alpha = 0
        card.transform = CGAffineTransform(translationX: 0, y: 12)
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
            card.alpha = 1
            card.transform = .identity
        }
    }

    private func handleMapSurveyTakeSurvey(_ survey: Survey) {
        if survey.isExternalSurvey {
            let launcher = ExternalSurveyLauncher(surveyService: application.surveyService)
            launcher.launch(
                survey: survey,
                stop: nil,
                onSuccess: { [weak self] in self?.dismissMapSurveyCard() },
                onFailure: { [weak self] in
                    self?.dismissMapSurveyCard()
                    self?.showMapExternalSurveyError()
                }
            )
        } else {
            let surveyVC = SurveyViewController(survey: survey, surveyService: application.surveyService)
            let navigation = UINavigationController(rootViewController: surveyVC)
            present(navigation, animated: true)
            dismissMapSurveyCard()
        }
    }

    private func handleMapSurveyDismiss(_ survey: Survey) {
        application.surveyService.markSurveyForLater(survey)
        application.surveyService.setNextReminderDate()
        dismissMapSurveyCard()
    }

    private func dismissMapSurveyCard() {
        guard let card = surveyCardView else { return }
        surveyCardView = nil
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseIn, animations: {
            card.alpha = 0
            card.transform = CGAffineTransform(translationX: 0, y: 12)
        }, completion: { _ in
            card.removeFromSuperview()
        })
    }

    private func showMapExternalSurveyError() {
        let alert = UIAlertController(
            title: OBALoc("survey_launcher.external_survey_error.title", value: "Can't Open Survey", comment: "Title shown when an external survey link cannot be opened"),
            message: OBALoc("survey_launcher.external_survey_error.message", value: "This survey link couldn't be opened. Please try again later.", comment: "Message shown when an external survey link cannot be opened"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: Strings.ok, style: .default))
        present(alert, animated: true)
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

        mapRegionManager.mapView.setCenterCoordinate(
            centerCoordinate: userLocation.coordinate,
            zoomLevel: viewModel.zoomLevelForCurrentLocation(),
            animated: true
        )

        // It is possible to activate the center map button via Voiceover. When the user
        // centers the map on their location, partially collapse the sheet to enable mapview interaction.
        if floatingPanel.state == .full {
            floatingPanel.move(to: .half, animated: true)
        }
    }

    // MARK: - Status View Handlers

    @objc private func handleMapStatusTap(_ sender: UITapGestureRecognizer) {
        if viewModel.showZoomWarning {
            didTapZoomInForStops()
        } else {
            didTapMapStatus(sender)
        }
    }

    private func didTapZoomInForStops() {
        let currentCenter = mapRegionManager.mapView.region.center

        let targetSpan = MKCoordinateSpan(
            latitudeDelta: MapViewModel.zoomInForStopsSpan,
            longitudeDelta: MapViewModel.zoomInForStopsSpan
        )

        let newRegion = MKCoordinateRegion(center: currentCenter, span: targetSpan)
        mapRegionManager.mapView.setRegion(newRegion, animated: true)
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

    // MARK: - My Trip

    private lazy var myTripButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(Icons.busButton, for: .normal)
        button.addTarget(self, action: #selector(showCurrentTrip), for: .touchUpInside)
        button.accessibilityLabel = OBALoc(
            "map_controller.my_trip_button",
            value: "My Trip",
            comment: "Accessibility label for the My Trip button on the map toolbar."
        )
        return button
    }()

    @objc private func showCurrentTrip() {
        application.viewRouter.navigateToCurrentTrip(from: self)
    }

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
        guard weatherDisplay != nil else { return }

        let host = UIHostingController(
            rootView: WeatherDetailPopupHost(viewModel: viewModel)
        )
        host.modalPresentationStyle = .overFullScreen
        host.modalTransitionStyle = .crossDissolve
        host.view.backgroundColor = .clear
        present(host, animated: true)
    }

    private var weatherDisplay: WeatherDisplay? {
        didSet {
            if let display = weatherDisplay {
                weatherButton.setTitle(display.buttonTitle, for: .normal)
                weatherButton.isHidden = false
            } else {
                weatherButton.isHidden = true
            }
        }
    }

    // MARK: - Long Press Gesture

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        // Only handle the began state to avoid multiple pins
        guard gesture.state == .began else { return }
        mapRegionManager.userPressedMap(gesture)
    }

    // MARK: - UIGestureRecognizerDelegate

    /// Must return `true` for user-dropped pin removal to work alongside MKMapView's internal gestures.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    // MARK: - Trip Planner

    private var semiModalTripPlannerController: FloatingPanelController?

    private var tripPlanner: TripPlanner?
    private var tripPlannerHostingController: UIViewController?
    private var longPressGesture: UILongPressGestureRecognizer!

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

    private func buildTripPlanner(region: Region) -> TripPlanner? {
        // GraphQL (OTP 2.x) is the preferred trip-planning API whenever the region
        // provides it; OTP 1.x REST is the fallback. Only the GraphQL service can
        // support vehicle rental features.
        let serverURL: URL
        let apiService: OTPKit.APIService
        if let graphQLURL = region.openTripPlannerGraphQLURL {
            serverURL = graphQLURL
            apiService = GraphQLAPIService(baseURL: graphQLURL)
        } else if let restURL = region.openTripPlannerURL {
            serverURL = restURL
            apiService = RestAPIService(baseURL: restURL)
        } else {
            return nil
        }

        var enabledModes: [TransportMode] = [.transit, .walk, .bike, .car]
        if region.isBikeshareEnabled {
            // The capability filter in OTPKit hides these again if the service
            // can't actually plan rental trips (e.g. the REST fallback).
            enabledModes.append(contentsOf: [.transitBikeRental, .bikeRental])
        }

        let searchRect = application.currentRegion?.serviceRect ?? mapRegionManager.mapView.visibleMapRect

        let config = OTPConfiguration(
            otpServerURL: serverURL,
            enabledTransportModes: enabledModes,
            themeConfiguration: .init(
                primaryColor: Color(uiColor: ThemeColors().brand)
            ),
            searchRegion: MKCoordinateRegion(searchRect)
        )

        let mapViewProvider = MKMapViewAdapter(mapView: tripPlannerMapView)

        let tripPlanner = TripPlanner(
            otpConfig: config,
            apiService: apiService,
            mapProvider: mapViewProvider,
            notificationCenter: application.notificationCenter
        )

        return tripPlanner
    }

    /// Presents the trip planner.
    /// - Parameters:
    ///   - destination: Optional prefilled destination.
    ///   - viaPoint: Optional coordinate every planned trip must pass through — used by
    ///     "Plan a trip using this bike" with the vehicle's location.
    ///   - preselectedMode: Optional transport mode to preselect, e.g. `.transitBikeRental`.
    func showTripPlanner(destination: MKMapItem? = nil, viaPoint: CLLocationCoordinate2D? = nil, preselectedMode: TransportMode? = nil) {
        guard let currentRegion = application.regionsService.currentRegion,
              currentRegion.supportsOTP,
              application.userDataStore.isTripPlanningEnabled(for: currentRegion) else {
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

        guard let tripPlanner = buildTripPlanner(region: currentRegion) else { return }

        subscribeToTripPlannerNotifications()

        let tripPlannerView = tripPlanner.createTripPlannerView(
            origin: origin,
            destination: destinationLocation,
            viaPoint: viaPoint,
            transportMode: preselectedMode
        ) { [weak self] in
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
        application.notificationCenter.addObserver(self, selector: #selector(tripStarted), name: Notifications.tripStarted, object: nil)
    }

    private func unsubscribeFromTripPlannerNotifications() {
        application.notificationCenter.removeObserver(self, name: Notifications.itinerariesUpdated, object: nil)
        application.notificationCenter.removeObserver(self, name: Notifications.tripStarted, object: nil)
    }

    @objc private func itinerariesUpdated(_ note: NSNotification) {
        semiModalTripPlannerController?.move(to: .full, animated: true)
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

        button.addSubview(mapLayerBadge)
        NSLayoutConstraint.activate([
            mapLayerBadge.topAnchor.constraint(equalTo: button.topAnchor, constant: 2),
            mapLayerBadge.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -2),
            mapLayerBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 15),
            mapLayerBadge.heightAnchor.constraint(equalToConstant: 15)
        ])

        return button
    }()

    /// The active-layer count on the basemap button — the primary discoverability
    /// lever for the Map sheet: layer state is readable without opening anything.
    lazy var mapLayerBadge: UILabel = {
        let label = UILabel.autolayoutNew()
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = ThemeColors.shared.brand
        label.layer.cornerRadius = 7.5
        label.layer.masksToBounds = true
        label.isHidden = true
        label.isUserInteractionEnabled = false
        return label
    }()

    /// The basemap button opens the Map sheet, which absorbs the old
    /// standard/hybrid toggle as its basemap tiles.
    @objc private func toggleMapType() {
        presentMapSheet()
    }

    private func setMapTypeButtonImage(_ button: UIButton, mapType: MapBaseType) {
        if mapType == .standard {
            button.setImage(UIImage(systemName: "map"), for: .normal)
            button.accessibilityValue = OBALoc("map_controller.map_type.standard.accessibility_value", value: "standard", comment: "Voiceover text indicating the current map type as the standard base map.")
        } else {
            button.setImage(UIImage(systemName: "globe"), for: .normal)
            button.accessibilityValue = OBALoc("map_controller.map_type.hybrid.accessibility_value", value: "hybrid", comment: "Voiceover text indicating the current map type as the hybrid base map (satellite view with labels).")
        }
    }

    // MARK: - Map Layers

    var rentalLayerCoordinator: RentalLayerCoordinator?

    /// The region `StopRouteFocusMapLayer` was last (re)registered for, so
    /// `configureMapLayers()` can tell an actual region change (rebuild, with a
    /// fresh `ShapeCache`) apart from `updatedRegionsList` firing with the same
    /// region — which happens routinely and must not tear the layer down.
    var stopRouteFocusLayerRegionIdentifier: Int?

    // The layer/sheet/nudge machinery lives in MapViewController+MapLayers.swift.

    // MARK: - Application State

    private var resignedActiveAt: Date?

    @objc func applicationWillResignActive(_ notification: NSNotification) {
        resignedActiveAt = Date()
    }

    @objc func applicationDidBecomeActive(_ notification: NSNotification) {
        // EC12: notify ViewModel so it can refresh data (e.g. weather) without UIKit imports.
        viewModel.onAppBecameActive()

        guard
            let resignedActiveAt = resignedActiveAt,
            abs(resignedActiveAt.timeIntervalSinceNow) > 600
        else {
            return
        }

        centerMapOnUserLocation()
    }

    @objc private func reloadBookmarkAnnotations() {
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.reloadBookmarks()
        }
    }

    // MARK: - Content Presentation

    /// Displays the specified stop.
    ///
    /// - Parameters:
    ///   - stop: The stop to display.
    ///   - annotation: The annotation the stop was opened from, if any. Deselected when the
    ///     stop sheet closes so the map doesn't keep a pin highlighted for a dismissed sheet.
    func show(stop: Stop, deselecting annotation: MKAnnotation? = nil) {
        guard prefersPushedStopPage else {
            present(stopController: application.viewRouter.makeStopController(stop: stop, showToolbarOnBottom: true), deselecting: annotation)
            return
        }
        deselectForPushedStopPage(annotation)
        application.viewRouter.navigateTo(stop: stop, from: self)
    }

    /// Displays the specified stop by ID.
    func show(stopID: StopID) {
        guard prefersPushedStopPage else {
            present(stopController: application.viewRouter.makeStopController(stopID: stopID, showToolbarOnBottom: true))
            return
        }
        application.viewRouter.navigateTo(stopID: stopID, from: self)
    }

    /// `true` while VoiceOver is running, where the Stop page opens as a full-screen push
    /// instead of the map's half-detent sheet.
    ///
    /// A partial-height FloatingPanel over a live map is a poor modal for VoiceOver — the map
    /// behind it stays in the accessibility tree, and the detents, swipe-to-dismiss, and
    /// collapse-to-`.tip` behaviors are drag gestures VoiceOver can't perform. The pushed
    /// presentation the router builds is a standard, opaque screen with a nav-bar back button
    /// and contained focus, and it skips the sheet path's map-focus wiring (route highlight,
    /// recentering, tab-bar hiding, `stopSheetStopID`) — map-visual bookkeeping that means
    /// nothing while a pushed screen covers the map, exactly as the legacy push path skips it.
    ///
    /// Read at open time only: a sheet already onscreen when VoiceOver is switched on is left
    /// as-is.
    private var prefersPushedStopPage: Bool {
        UIAccessibility.isVoiceOverRunning
    }

    /// A full-screen push covers the map, so leaving the tapped pin selected only strands a
    /// highlight for the rider to find on the way back.
    private func deselectForPushedStopPage(_ annotation: MKAnnotation?) {
        guard let annotation else { return }
        mapRegionManager.mapView.deselectAnnotation(annotation, animated: false)
    }

    /// Routes a stop screen to the presentation that suits it: the redesigned Stop page comes
    /// up as a half-detent sheet over the map, the legacy screen still pushes.
    ///
    /// The branch keys off the controller `makeStopController` actually returned rather than
    /// re-reading `FeatureFlags.isNewStopPageEnabled`. That factory has a second reason to fall
    /// back to the legacy screen — a non-nil transfer context — so a duplicated flag check here
    /// would eventually disagree with it and drop `StopViewController` into a panel it was
    /// never built for.
    private func present(stopController: UIViewController, deselecting annotation: MKAnnotation? = nil) {
        guard let stopPageVC = stopController as? StopPageViewController else {
            application.viewRouter.navigate(to: stopController, from: self)
            return
        }

        stopPageVC.onClose = { [weak self] in self?.stopSheet.dismiss() }

        // This is the map the trip page will hang over, whichever affordance
        // opened it.
        stopPageVC.onTripPagePush = { [weak self] tripPage in
            self?.wireTripFocus(for: tripPage)
        }

        // Only one sheet at a time: clear whatever else is occupying this space first.
        dismissExistingMapItemController()
        semiModalPanel?.removePanelFromParent(animated: false)
        semiModalPanel = nil

        floatingPanel.move(to: .tip, animated: true)

        stopSheet.present(stopPageVC, from: self) { [weak self] in
            guard let self else { return }

            if let annotation {
                self.mapRegionManager.mapView.deselectAnnotation(annotation, animated: true)
            }

            self.stopFocusCancellables.removeAll()
            (self.mapRegionManager.mapLayer(id: StopRouteFocusMapLayer.layerID) as? StopRouteFocusMapLayer)?.end()
            self.stopSheetStopID = nil

            self.scheduleFeedbackPrompt()
        }

        // ORDERING IS LOAD-BEARING. `StopSheetPresenter.present` tears the outgoing
        // presentation down as its FIRST statement, which synchronously runs the
        // outgoing dismiss handler — and that handler ends the layer. Building and
        // activating the new focus before this call would have the outgoing handler
        // immediately tear down what we just set up: a blank map on every
        // stop-to-stop tap.
        let focus = StopMapFocus()
        stopPageVC.attach(focus: focus)
        beginRouteFocus(focus: focus, stopPageVC: stopPageVC)

        // Camera framing is not layer content, so it must not answer to the
        // "Route lines & vehicles" Map-sheet toggle the way `beginRouteFocus`
        // does — a rider who turns that layer off must not also lose stop
        // recentering. Unconditional, but still after `stopSheet.present`
        // above for the same outgoing-teardown ordering reason.
        beginRecentering(stopPageVC: stopPageVC)

        // Also after `stopSheet.present`, and for the same reason: a stop-to-stop
        // swap runs the outgoing sheet's dismiss handler inside that call, and
        // that handler clears this.
        stopSheetStopID = stopPageVC.viewModel.stopID

        // `StopSheetPresenter.present` tears the outgoing presentation down as its first
        // statement, which runs the handler above synchronously — so a stop-to-stop swap
        // arms the prompt for a sheet that is being replaced, not dismissed. Cancelling
        // *after* the call is what unschedules that, whereas cancelling before it would
        // be undone a line later.
        cancelScheduledFeedbackPrompt()
    }

    /// Points this map at a trip for as long as its page is on the stack.
    ///
    /// While the trip page is up the map shows that trip and nothing else: the
    /// stop's own routes and vehicles stand down, and come back intact when the
    /// rider pops out. Suppression rather than `end()` — the stop sheet
    /// underneath is still presented.
    private func wireTripFocus(for tripPage: TripPageViewController) {
        tripPage.onMapFocusChanged = { [weak self] tripFocus in
            guard let self else { return }

            // Gated on the layer's own Map-sheet toggle, for the same reason
            // `beginRouteFocus` is: annotation and overlay dispatch consults
            // every registered layer with no enabled check, so a disabled layer
            // that gets begun would still draw. A rider who turned this off keeps
            // the stop's routes instead — which is why the suppression flag
            // follows enablement rather than the push.
            guard mapRegionManager.isMapLayerEnabled(id: TripFocusMapLayer.layerID),
                  let tripLayer = mapRegionManager.mapLayer(id: TripFocusMapLayer.layerID) as? TripFocusMapLayer else { return }

            let stopLayer = mapRegionManager.mapLayer(id: StopRouteFocusMapLayer.layerID) as? StopRouteFocusMapLayer
            stopLayer?.setSuppressed(tripFocus != nil)

            if let tripFocus {
                // Evaluated when the layer frames, not now: the sheet is still
                // animating up at this point.
                tripLayer.cameraInsets = { [weak self] in self?.sheetCameraInsets() ?? .zero }
                tripLayer.begin(focus: tripFocus)
            } else {
                tripLayer.end()
            }
        }
    }

    /// Feeds the route-focus layer from the stop page's view model, and routes
    /// "Follow this trip" into the sheet's navigation stack. Owns ONLY the
    /// focus/layer wiring — camera recentering is a separate concern, see
    /// `beginRecentering(stopPageVC:)`.
    ///
    /// Gated on the layer's Map-sheet toggle: `MapRegionManager`'s annotation
    /// and overlay dispatch deliberately consults every registered layer with
    /// no enabled check (mirroring the rendering path), so a disabled layer
    /// must never be wired up to begin with — starting the arrivals sink here
    /// would give it a live feed no toggle turns off. `update(model:)` still
    /// carries its own `focus == nil` guard as a second line of defense, for
    /// the case where the layer is disabled mid-presentation.
    private func beginRouteFocus(focus: StopMapFocus, stopPageVC: StopPageViewController) {
        guard mapRegionManager.isMapLayerEnabled(id: StopRouteFocusMapLayer.layerID),
              let layer = mapRegionManager.mapLayer(id: StopRouteFocusMapLayer.layerID) as? StopRouteFocusMapLayer else { return }
        layer.begin(focus: focus)

        let viewModel = stopPageVC.viewModel
        // Routed through the stop page rather than pushing from here, so the
        // callout's "Follow this trip" and the page's own "View full trip" and
        // "Show Trip Details" all land on one screen by one path. `showTripPage`
        // calls back into `onTripPagePush` below.
        layer.onFollowTrip = { [weak stopPageVC] departure in
            stopPageVC?.showTripPage(for: departure)
        }

        // Combine over a @MainActor ObservableObject from UIKit: the exact pattern
        // `StopViewController.bindArrivalsSink()` already ships under Swift 6
        // strict concurrency. `sink(receiveValue:)` takes a plain non-Sendable
        // closure, so it inherits @MainActor and crosses no isolation boundary.
        //
        // Everything the layer needs comes from the closure's parameters. Nothing
        // here may re-read `viewModel.stopArrivals`: `@Published` fires in
        // `willSet`, so inside this sink that property still holds the OLD value —
        // nil on the first load. `apply` exists to make that mistake unavailable.
        viewModel.$stopArrivals
            .combineLatest(viewModel.$isListFiltered, viewModel.$stopPreferences)
            .sink { [weak layer] arrivals, isListFiltered, preferences in
                layer?.apply(arrivals: arrivals, isListFiltered: isListFiltered, preferences: preferences)
            }
            .store(in: &stopFocusCancellables)
    }

    /// Keeps the tapped stop visible above the sheet, independent of whether the
    /// "Route lines & vehicles" layer is enabled — camera framing is not layer
    /// content, so a rider who disables that layer must not also lose
    /// recentering (the bug the spec's "Camera" section exists to fix).
    ///
    /// Subscribing to `$stop` — rather than reading `viewModel.stop` once at
    /// present time — also covers `show(stopID:)` (deep links, nearby-stop
    /// rows), where the stop loads asynchronously after the sheet is already
    /// up; a one-time read there would see nil and leave the stop behind the
    /// sheet. `@Published` replays its current value to a new subscriber, so
    /// this still fires immediately when the stop is already loaded (the
    /// `show(stop:)` path).
    private func beginRecentering(stopPageVC: StopPageViewController) {
        stopPageVC.viewModel.$stop
            .compactMap { $0 }
            .first()
            .sink { [weak self] stop in
                self?.centerMapAboveSheet(on: stop.coordinate)
            }
            .store(in: &stopFocusCancellables)
    }

    /// Torn down alongside the layer when the sheet closes.
    private var stopFocusCancellables = Set<AnyCancellable>()

    /// Owns the half-detent panel that shows the redesigned Stop page over the map.
    private lazy var stopSheet = StopSheetPresenter()

    /// The stop whose sheet is up, or nil between presentations — the single
    /// switch behind both of the things the map does differently while a sheet
    /// owns the screen: the zoom pill stays down, and every stop but this one
    /// recedes to a background dot.
    ///
    /// Tracked here rather than read from `stopSheet.isPresenting` because the
    /// presenter's own flag flips at points inside `present`/`dismiss` that this
    /// controller doesn't observe; a stop-to-stop swap in particular runs the
    /// outgoing dismissal in the middle of the incoming presentation.
    private var stopSheetStopID: StopID? {
        didSet {
            guard oldValue != stopSheetStopID else { return }
            mapRegionManager.stopSheetSelection = stopSheetStopID
            renderMapStatus()
        }
    }

    /// Presents the feedback prompt after a stop sheet is dismissed — a natural
    /// stopping point, and the only one available in the new stop page flow.
    private lazy var feedbackPromptPresenter = FeedbackPromptPresenter(application: application)

    // MARK: - Feedback Prompt

    /// The pending delayed presentation, held so it can be cancelled when the map fills
    /// the space the dismissed sheet left behind.
    private var feedbackPromptWorkItem: DispatchWorkItem?

    /// Arms the feedback prompt a beat after a stop sheet leaves the screen.
    ///
    /// The delay keeps the alert from racing the sheet's dismissal animation, per Apple's
    /// sample guidance on delaying review asks. It also means the map can change out from
    /// under the scheduled block — another sheet, a place card, a tab switch, a trip to the
    /// background — so eligibility is re-checked when the timer fires rather than when it
    /// is set.
    private func scheduleFeedbackPrompt() {
        cancelScheduledFeedbackPrompt()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.feedbackPromptWorkItem = nil
            self.feedbackPromptPresenter.presentIfEligible(from: self) { [weak self] in
                self?.mapIsAtANaturalStoppingPoint ?? false
            }
        }

        feedbackPromptWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func cancelScheduledFeedbackPrompt() {
        feedbackPromptWorkItem?.cancel()
        feedbackPromptWorkItem = nil
    }

    /// Clears the stop sheet because something else is about to occupy its space —
    /// another panel, a search result, or a region change that invalidates the stop
    /// the sheet is showing.
    ///
    /// The dismissal runs the sheet's handler synchronously, which arms the prompt — so the
    /// cancel has to follow it, not precede it. The two belong together at every call site,
    /// which is why they live here rather than being spelled out at each one.
    func dismissStopSheetForReplacement() {
        stopSheet.dismiss(animated: false)
        cancelScheduledFeedbackPrompt()
    }

    /// Whether the map is still the quiet, unoccupied screen it was when the prompt was armed.
    ///
    /// `presentIfEligible`'s own `presentedViewController == nil` check can't see any of this:
    /// the stop sheet and the semi-modal panels are FloatingPanel *children* of this controller,
    /// not modal presentations. The spec's rule that the prompt never appears on the stop screen
    /// depends entirely on the first three clauses here.
    private var mapIsAtANaturalStoppingPoint: Bool {
        !stopSheet.isPresenting
            && semiModalPanel == nil
            && semiModalMapItemController == nil
            && view.window != nil
            && UIApplication.shared.applicationState == .active
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
        dismissStopSheetForReplacement()
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
        // Only hide the map from VoiceOver if the sheet is covering the ENTIRE screen.
        // This allows users to interact with map pins when the sheet is in .half or .tip state.
        mapRegionManager.mapView.accessibilityElementsHidden = (vc.state == .full)

        if mapPanelController.inSearchMode && floatingPanelPositionIsCollapsed {
            mapPanelController.exitSearchMode()
        }
    }

    func updateVoiceover() {
        mapRegionManager.preferredLoadDataRegionFudgeFactor = UIAccessibility.isVoiceOverRunning ? 1.5 : MapRegionManager.DefaultLoadDataRegionFudgeFactor

        if UIAccessibility.isVoiceOverRunning {
            floatingPanel.move(to: .half, animated: true)

            if !floatingPanel.userHasSeenFullSheetVoiceoverChange {
                self.present(floatingPanel.fullSheetVoiceoverAlert(), animated: true)
                floatingPanel.userHasSeenFullSheetVoiceoverChange = true
            }
        }
    }

    // MARK: - Modal Delegate

    public func dismissModalController(_ controller: UIViewController) {
        // Check if it's the map item controller
        if controller == semiModalMapItemController?.contentViewController,
           let panel = semiModalMapItemController {
            // Only deselect user-dropped pin annotations — other annotation types
            // (stops, bookmarks) manage their own selection state.
            mapRegionManager.mapView.selectedAnnotations.forEach { annotation in
                if annotation is UserDroppedPin {
                    mapRegionManager.mapView.deselectAnnotation(annotation, animated: true)
                }
            }

            removeSemiModalPanel(panel, animated: true)
            semiModalMapItemController = nil
        }
        // Check if it's the semi modal panel
        else if controller == semiModalPanel?.contentViewController {
            mapRegionManager.cancelSearch()
            semiModalPanel?.removePanelFromParent(animated: true)
        }
        else {
            controller.dismiss(animated: true, completion: nil)
        }
    }

    // MARK: - Map Item Controller

    private var semiModalMapItemController: FloatingPanelController?

    /// Dismisses the currently displayed map item controller panel, if one exists.
    /// Ensures proper cleanup before displaying a new map item or when the associated pin is removed.
    /// - Parameter animated: Whether to animate the dismissal. Use `false` for immediate replacement,
    ///   `true` for user-initiated actions like pin removal.
    private func dismissExistingMapItemController(animated: Bool = false) {
        if let existingController = semiModalMapItemController {
            removeSemiModalPanel(existingController, animated: animated)
            semiModalMapItemController = nil
        }
    }

    /// Presents a `MapItemController` with the provided `MKMapItem` as a semi-modal panel.
    /// - Parameters:
    ///   - mapItem: The map item to display
    ///   - userPin: Optional user-dropped pin associated with this map item (for removal functionality)
    private func displayMapItemController(_ mapItem: MKMapItem, userPin: UserDroppedPin? = nil) {
        dismissStopSheetForReplacement()
        dismissExistingMapItemController()
        // Create remove pin handler if this is a user-dropped pin
        let removePinHandler: (() -> Void)?
        if let pin = userPin {
            removePinHandler = { [weak self] in
                self?.mapRegionManager.removeUserAnnotation(pin)
            }
        } else {
            removePinHandler = nil
        }

        let viewModel = MapItemViewModel(mapItem: mapItem, application: application, delegate: self, removePinHandler: removePinHandler) { [weak self] in
            guard let self else { return }

            self.dismissExistingMapItemController(animated: true)
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
        show(stopID: stopID)
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
        // Layer-owned annotations (rental vehicles, rental clusters) present
        // their own detail sheets.
        if let annotation = view.annotation, presentLayerDetail(for: annotation, in: mapView) {
            return
        }

        if let vehicleAnnotation = view.annotation as? StopVehicleAnnotation {
            // The layer decides what a marker tap means — focus the route, or
            // clear it. Which one depends on whether this is the marker focus is
            // already standing on, so it needs the annotation, not just its route.
            (mapRegionManager.mapLayer(id: StopRouteFocusMapLayer.layerID) as? StopRouteFocusMapLayer)?
                .didSelectVehicle(vehicleAnnotation)
            return
        }

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
        } else if !view.canShowCallout, let stop = selectableStop(for: view.annotation) {
            // No callout means there is no chevron to tap, so selection is the open gesture.
            // `StopAnnotationView.updateCalloutVisibility()` owns that decision — don't duplicate
            // its reasoning here, or the two will drift and leave annotations that select but
            // never open.
            application.analytics?.reportEvent(pageURL: "app://localhost/map", label: AnalyticsLabels.mapStopAnnotationTapped, value: nil)
            show(stop: stop, deselecting: view.annotation)
        } else if let annotation = view.annotation as? UserDroppedPin {
            // Sheet presentation for user-dropped pins is handled via
            // mapRegionManager(_:didSelectUserAnnotation:) delegate callback.
            // Early return here prevents falling through to the MKPlacemark case.
            mapView.setCenter(annotation.coordinate, animated: true)
            return
        } else if let placemark = view.annotation as? MKPlacemark {
            let mapItem = MKMapItem(placemark: placemark)
            displayMapItemController(mapItem)
            mapView.deselectAnnotation(view.annotation, animated: true)
        }
    }

    public func mapRegionManager(_ manager: MapRegionManager, didSelectUserAnnotation annotation: UserDroppedPin) {
        presentMapItem(for: annotation)
    }

    private func presentMapItem(for userPin: UserDroppedPin) {
        if let storedMapItem = mapRegionManager.mapItem(for: userPin) {
            displayMapItemController(storedMapItem, userPin: userPin)
        } else {
            let placemark = MKPlacemark(coordinate: userPin.coordinate)
            let mapItem = MKMapItem(placemark: placemark)
            mapItem.name = userPin.title ?? "Dropped Pin"
            displayMapItemController(mapItem, userPin: userPin)
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
        guard let stop = selectableStop(for: view.annotation) else { return }
        application.analytics?.reportEvent(pageURL: "app://localhost/map", label: AnalyticsLabels.mapStopAnnotationTapped, value: nil)
        show(stop: stop, deselecting: view.annotation)
    }

    /// The stop an annotation opens, for the two annotation types that render as a
    /// `StopAnnotationView`. Bookmarked stops appear on the map as `Bookmark` rather than `Stop`
    /// (see `MapRegionManager.displayUniqueStopAnnotations`), so anything that opens stops from
    /// the map has to handle both or bookmarked stops quietly stop responding to taps.
    private func selectableStop(for annotation: MKAnnotation?) -> Stop? {
        switch annotation {
        case let stop as Stop: return stop
        case let bookmark as Bookmark: return bookmark.stop
        default: return nil
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
                // Check if this MapItem is associated with a user-dropped pin
                let userPin = manager.findUserPin(for: result)
                displayMapItemController(result, userPin: userPin)
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

    public func mapRegionManager(_ manager: MapRegionManager, didRemoveUserAnnotation annotation: UserDroppedPin) {
        // Dismiss any open map item controller when a pin is removed
        dismissExistingMapItemController(animated: true)
    }

    @objc public func mapRegionManagerShowZoomInStatus(_ manager: MapRegionManager, showStatus: Bool) {
        // EC6: Update ViewModel so both UIKit and future SwiftUI consumers share the same state.
        viewModel.updateZoomWarning(showStatus)
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
        loadingIndicatorTimer = Timer.scheduledMainActorTimer(withTimeInterval: 1, repeats: false) { [weak self] in
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

    // MARK: - Context Menus

    public func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard
            let annotationView = interaction.view as? MKAnnotationView,
            let stop = annotationView.annotation as? Stop
        else { return nil }

        let previewController = { () -> UIViewController in
            // Built for the sheet, because that's where committing the peek lands it. The
            // toolbar stays suppressed until `exitPreviewMode()`, so the glance itself is bare.
            let stopController = self.application.viewRouter.makeStopController(stop: stop, showToolbarOnBottom: true)
            (stopController as? Previewable)?.enterPreviewMode()
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

            // The preview controller was built by `makeStopController`, so it lands in the same
            // sheet a tap would produce — peek-and-pop and tap shouldn't disagree about what
            // opening a stop looks like.
            let annotation = (interaction.view as? MKAnnotationView)?.annotation
            self.present(stopController: viewController, deselecting: annotation)
        }
    }

    public func largeContentViewerInteraction(_ interaction: UILargeContentViewerInteraction, didEndOn item: UILargeContentViewerItem?, at point: CGPoint) {
        if mapStatusView.frame.contains(point) {
            didTapMapStatus(interaction)
        }
    }

}

// MARK: - ViewModel Binding

private extension MapViewController {
    func bindWeather() {
        viewModel.$weatherDisplay
            .sink { [weak self] display in self?.weatherDisplay = display }
            .store(in: &cancellables)
    }

    func bindMapStatus() {
        // EC6: Observe zoom-warning state from ViewModel so UIKit and future SwiftUI share the same source of truth.
        viewModel.$showZoomWarning
            .sink { [weak self] _  in
                guard let self else { return }
                self.renderMapStatus()
            }
            .store(in: &cancellables)

        viewModel.$locationAuthStatus
            .sink { [weak self] _ in
                guard let self else { return }
                self.renderMapStatus()
            }
            .store(in: &cancellables)
    }

    func bindMapType() {
        viewModel.$mapType
            .sink { [weak self] mapType in
                guard let self else { return }
                // Persistence is owned by `MapViewModel.toggleMapType()`; the
                // sink here only mirrors the selection onto MapKit's mapView
                // and refreshes the toolbar icon so both stay in step when
                // the value changes through any path (VM toggle, external
                // defaults edit, cross-view sync).
                mapRegionManager.mapView.mapType = mapType.mkMapType
                setMapTypeButtonImage(toggleMapTypeButton, mapType: mapType)
            }
            .store(in: &cancellables)
    }

    func renderMapStatus() {
        let locationState = mapStatusView.state(for: application.locationService)
        // "Zoom in for stops" stays down while a stop sheet is up: it would sit on
        // top of the route lines the sheet came up to show, to tell the rider about
        // stops they are no longer looking for. Location warnings still surface —
        // those are actionable, and tapping the pill is how you act on them.
        mapStatusView.configure(
            for: locationState,
            zoomInStatus: viewModel.showZoomWarning && stopSheetStopID == nil
        )
        locationButton.isHidden = !application.locationService.isLocationUseAuthorized
        layoutMapMargins()
    }
}

// swiftlint:enable file_length
