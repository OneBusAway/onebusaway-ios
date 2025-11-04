//
//  TripViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import MapKit
import FloatingPanel
import OBAKitCore

class TripViewController: UIViewController,
    AppContext,
    FloatingPanelControllerDelegate,
    Idleable,
    MKMapViewDelegate,
    Previewable {

    public let application: Application

    private(set) var tripConvertible: TripConvertible

    private lazy var dataLoadFeedbackGenerator = DataLoadFeedbackGenerator(application: application)

    init(application: Application, tripConvertible: TripConvertible) {
        self.application = application
        self.tripConvertible = tripConvertible

        super.init(nibName: nil, bundle: nil)

        registerTraitChangeCallback()
    }

    init(application: Application, arrivalDeparture: ArrivalDeparture) {
        self.application = application
        self.tripConvertible = TripConvertible(arrivalDeparture: arrivalDeparture)

        super.init(nibName: nil, bundle: nil)

        registerTraitChangeCallback()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func registerTraitChangeCallback() {
        let sizeTraits: [UITrait] = [UITraitVerticalSizeClass.self, UITraitHorizontalSizeClass.self, UITraitPreferredContentSizeCategory.self]
        registerForTraitChanges(sizeTraits) { (self: Self, _) in
            self.updateTitleView()
        }
    }

    // MARK: - UIViewController

    lazy var reloadButton: UIBarButtonItem = {
        let button = UIBarButtonItem(image: Icons.refresh, style: .plain, target: self, action: #selector(refresh))
        button.title = Strings.refresh
        return button
    }()

    let activityIndicatorButton = UIActivityIndicatorView.asNavigationItem()

    override func viewDidLoad() {
        super.viewDidLoad()

        // Don't show user location if accuracy is reduced to avoid user confusion.
        mapView.showsUserLocation = application.locationService.isLocationUseAuthorized && application.locationService.accuracyAuthorization == .fullAccuracy

        mapView.showsTraffic = application.mapRegionManager.mapViewShowsTraffic
        mapView.showsScale = application.mapRegionManager.mapViewShowsScale
        application.mapRegionManager.registerAnnotationViews(mapView: mapView)

        updateTitleView()

        view.addSubview(mapView)
        mapView.pinToSuperview(.edges)

        loadData(isProgrammatic: true)

        if !isBeingPreviewed {
            floatingPanel.addPanel(toParent: self)
        }

        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        navigationItem.scrollEdgeAppearance = appearance
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        disableIdleTimer()
        beginUserActivity()

        setContentScrollView(tripDetailsController.listView, for: .bottom)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateVoiceover()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        enableIdleTimer()
    }

    // MARK: - NSUserActivity

    /// Creates and assigns an `NSUserActivity` object corresponding to this trip.
    private func beginUserActivity() {
        guard
            let region = application.regionsService.currentRegion,
            let activity = application.userActivityBuilder?.userActivity(for: tripConvertible, region: region)
        else {
            return
        }

        self.userActivity = activity
    }

    // MARK: Previewable

    /// Set this to `true` before `viewDidLoad` to present the UI in a stripped-down 'preview mode'
    /// suitable for display in a context menu.
    var isBeingPreviewed = false

    func enterPreviewMode() {
        isBeingPreviewed = true
    }

    func exitPreviewMode() {
        isBeingPreviewed = false

        if isViewLoaded, floatingPanel.parent == nil {
            floatingPanel.addPanel(toParent: self)
            floatingPanel.move(to: .half, animated: true)
        }

        tripDetailsController.listView.applyData()
    }

    // MARK: - Idle Timer

    public var idleTimerFailsafe: Timer?

    // MARK: - Title View

    private let titleView = StackedMarqueeTitleView(width: 178.0)

    private func updateTitleView() {
        navigationItem.titleView = isAccessibility ? nil : titleView

        guard let tripStatus = tripConvertible.tripStatus else {
            title = nil
            titleView.topLabel.text = ""
            titleView.bottomLabel.text = ""
            return
        }

        let parts = [tripStatus.vehicleID, tripStatus.activeTrip.route.shortName].compactMap { $0 }

        if parts.count > 0 {
            titleView.topLabel.text = parts.joined(separator: " - ")
        }

        if let vehicleID = tripStatus.vehicleID {
            title = vehicleID
        }

        if let lastUpdate = tripStatus.lastUpdate {
            let format = OBALoc("trip_details_controller.last_report_fmt", value: "Last report: %@", comment: "Last report: <TIME>")
            let time = application.formatters.timeFormatter.string(from: lastUpdate)
            titleView.bottomLabel.text = String(format: format, time)
        }
    }

    // MARK: - Drawer/Trip Details UI

    var showTripDetails: Bool = false {
        didSet {
            guard oldValue != self.showTripDetails else { return }
            UIView.animate(withDuration: 0.1) {
                self.tripDetailsController.setListVisibility(isVisible: self.showTripDetails)
            }
        }
    }

    private lazy var tripDetailsController = TripFloatingPanelController(
        application: application,
        tripConvertible: tripConvertible,
        parentTripViewController: self
    )

    /// The floating panel controller, which displays a drawer at the bottom of the map.
    private lazy var floatingPanel: OBAFloatingPanelController = {
        let panel = OBAFloatingPanelController(application, delegate: self)
        panel.isRemovalInteractionEnabled = false
        panel.surfaceView.appearance.cornerRadius = ThemeMetrics.cornerRadius
        panel.contentMode = .fitToBounds

        // Set a content view controller.
        panel.set(contentViewController: tripDetailsController)

        return panel
    }()

    public func floatingPanel(_ vc: FloatingPanelController, layoutFor newCollection: UITraitCollection) -> FloatingPanelLayout {
        let layout: FloatingPanelLayout
        switch newCollection.horizontalSizeClass {
        case .regular:
            layout = MapPanelLandscapeLayout(initialState: .tip)
        default:
            layout = MapPanelLayout(initialState: .tip)
        }

        return layout
    }

    func floatingPanelDidMove(_ vc: FloatingPanelController) {
        showTripDetails = true
    }

    func floatingPanelDidChangeState(_ fpc: FloatingPanelController) {
        showTripDetails = fpc.state != .tip
        tripDetailsController.configureView(for: fpc.state)

        if fpc.state != .full {
            if traitCollection.horizontalSizeClass == .regular {
                mapView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: MapPanelLandscapeLayout.WidthSize + ThemeMetrics.padding, bottom: 0, trailing: 0)
            } else {
                let bottom: CGFloat
                if fpc.state == .half {
                    bottom = self.view.safeAreaLayoutGuide.layoutFrame.height / 2
                } else {
                    bottom = MapPanelLayout.EstimatedDrawerTipStateHeight
                }

                mapView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: bottom, trailing: 0)
            }
        }
    }

    func showStopOnMap(_ tripStop: TripStopViewModel) {
        self.floatingPanel.move(to: .half, animated: true) {
            self.skipNextStopTimeHighlight = true
            self.selectedStopTime = tripStop.stopTime
        }
    }

    func updateVoiceover() {
        if UIAccessibility.isVoiceOverRunning {
            self.floatingPanel.move(to: .full, animated: true)
        }
    }

    // MARK: - Trip Details Data
    private var currentTripStatus: TripStatus? {
        didSet {
            guard let currentTripStatus = currentTripStatus else {
                vehicleAnnotation = nil
                return
            }

            if let vehicleAnnotation = vehicleAnnotation {
                vehicleAnnotation.tripStatus = currentTripStatus
            }
            else {
                vehicleAnnotation = VehicleAnnotation(tripStatus: currentTripStatus)
                self.mapView.addAnnotation(vehicleAnnotation!)
            }

            updateTitleView()
        }
    }

    private func loadTripConvertible(isProgrammatic: Bool) async throws {
        guard let apiService = application.apiService else {
            return
        }

        guard let arrivalDeparture = tripConvertible.arrivalDeparture else {
            return
        }

        let newArrDep = try await apiService.getTripArrivalDepartureAtStop(
            stopID: arrivalDeparture.stopID,
            tripID: arrivalDeparture.tripID,
            serviceDate: arrivalDeparture.serviceDate,
            vehicleID: arrivalDeparture.vehicleID,
            stopSequence: arrivalDeparture.stopSequence
        ).entry

        await MainActor.run {
            self.tripConvertible = TripConvertible(arrivalDeparture: newArrDep)
            self.tripDetailsController.tripConvertible = TripConvertible(arrivalDeparture: newArrDep)
        }
    }

    private func loadTripDetails(isProgrammatic: Bool) async throws {
        guard let apiService = application.apiService else {
            return
        }

        // Let the user still look at data if there was already details from a previous request.
        self.floatingPanel.surfaceView.grabberHandle.isHidden = self.tripDetailsController.tripDetails == nil

        let trip = try await apiService.getTrip(tripID: tripConvertible.trip.id, vehicleID: tripConvertible.vehicleID, serviceDate: tripConvertible.serviceDate).entry

        await MainActor.run {
            self.tripDetailsController.tripDetails = trip

            self.mapView.updateAnnotations(with: trip.stopTimes)

            self.currentTripStatus = trip.status

            // In cases where TripStatus.coordinates is (0,0), we don't want to show it.
            var annotationsToShow = self.mapView.annotations.filter { !($0 is MKUserLocation) }
            annotationsToShow.removeAll(where: { $0.coordinate.isNullIsland })

            if !self.mapView.hasBeenTouched {
                self.mapView.showAnnotations(annotationsToShow, animated: true)
            }

            if let arrivalDeparture = self.tripConvertible.arrivalDeparture {
                let userDestinationStopTime = trip.stopTimes.filter { $0.stopID == arrivalDeparture.stopID }.first
                self.selectedStopTime = userDestinationStopTime
            }

            self.floatingPanel.surfaceView.grabberHandle.isHidden = false
        }
    }

    // MARK: - Map Data

    private var routePolyline: MKPolyline?

    private func loadMapPolyline(isProgrammatic: Bool) async throws {
        guard
            let apiService = application.apiService,
            routePolyline == nil // No need to reload the polyline if we already have it
        else {
            return
        }

        let response = try await apiService.getShape(id: tripConvertible.trip.shapeID)
        await MainActor.run {
            guard let polyline = response.entry.polyline else {
                return
            }
            self.routePolyline = polyline
            self.mapView.addOverlay(polyline)
            if !self.mapView.hasBeenTouched {
                self.mapView.visibleMapRect = self.mapView.mapRectThatFits(polyline.boundingMapRect, edgePadding: UIEdgeInsets(top: 60, left: 20, bottom: 128, right: 20))
            }
        }
    }

    // MARK: - Load Data

    @objc private func refresh(_ sender: Any) {
        loadData(isProgrammatic: false)
    }

    private var loadDataTask: Task<Void, Never>?
    private func loadData(isProgrammatic: Bool) {
        if let loadDataTask {
            loadDataTask.cancel()
        }

        loadDataTask = Task {
            self.navigationItem.rightBarButtonItem = self.activityIndicatorButton

            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        try await self.loadTripDetails(isProgrammatic: isProgrammatic)
                    }

                    group.addTask {
                        try await self.loadTripConvertible(isProgrammatic: isProgrammatic)
                    }

                    group.addTask {
                        try await self.loadMapPolyline(isProgrammatic: isProgrammatic)
                    }

                    try await group.waitForAll()
                }

                await MainActor.run {
                    self.dataLoadFeedbackGenerator.dataLoad(.success)
                }
            } catch {
                await self.application.displayError(error)
                await MainActor.run {
                    self.dataLoadFeedbackGenerator.dataLoad(.failed)
                }
            }

            self.navigationItem.rightBarButtonItem = self.reloadButton
        }
    }

    // MARK: - Map View

    /// A subclass of MKMapView that tells you if it has ever been touched by the user.
    class TouchesMapView: MKMapView {

        /// True if the user touched the map and false otherwise.
        var hasBeenTouched = false

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            hasBeenTouched = true
            super.touchesBegan(touches, with: event)
        }
    }

    private lazy var mapView: TouchesMapView = {
        let map = TouchesMapView.autolayoutNew()
        map.delegate = self
        map.mapType = application.mapRegionManager.userSelectedMapType
        map.accessibilityElementsHidden = true
        return map
    }()

    public var skipNextStopTimeHighlight = false
    public func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard let stopTime = view.annotation as? TripStopTime else { return }
        defer { skipNextStopTimeHighlight = false }
        guard !skipNextStopTimeHighlight else { return }

        func mapViewAnnotationSelectionComplete() {
            self.tripDetailsController.highlightStopInList(stopTime.stop)
        }

        if self.mapView.hasBeenTouched {
            mapViewAnnotationSelectionComplete()
        } else {
            if traitCollection.horizontalSizeClass == .regular {
                floatingPanel.move(to: .full, animated: true, completion: mapViewAnnotationSelectionComplete)
            } else {
                floatingPanel.move(to: .half, animated: true, completion: mapViewAnnotationSelectionComplete)
            }
        }
    }

    public func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
        guard let stopTime = view.annotation as? TripStopTime,
            stopTime == self.selectedStopTime else { return }

        self.selectedStopTime = nil
    }

    public func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        guard let stopTime = view.annotation as? TripStopTime else { return }
        application.viewRouter.navigateTo(stop: stopTime.stop, from: self)
    }

    // TODO FIXME: DRY up with MapRegionManager

    public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        let renderer = MKPolylineRenderer(polyline: overlay as! MKPolyline) // swiftlint:disable:this force_cast

        // Tries to use an agency provided color, if available.
        var strokeColor = tripConvertible.arrivalDeparture?.route.color ?? ThemeColors.shared.brand

        // If the user has High Contrast or Reduce Transparency turned ON in iOS,
        // don't apply the transparency to the stroke color.
        let needsIncreasedVisibility =
            traitCollection.userInterfaceStyle == .dark ||
            traitCollection.accessibilityContrast == .high ||
            UIAccessibility.isReduceTransparencyEnabled

        if !needsIncreasedVisibility {
            strokeColor = strokeColor.withAlphaComponent(0.75)
        }
        renderer.strokeColor = strokeColor

        renderer.lineWidth = 6.0
        renderer.lineCap = .round

        return renderer
    }

    private var userLocationAnnotationView: PulsingAnnotationView?

    private var vehicleAnnotationView: PulsingAnnotationView?
    private var vehicleAnnotation: VehicleAnnotation?

    public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let reuseIdentifier = reuseIdentifier(for: annotation) else {
            return nil
        }

        let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier, for: annotation)

        if let annotationView = annotationView as? PulsingVehicleAnnotationView {
            vehicleAnnotationView = annotationView
            if let color = tripConvertible.arrivalDeparture?.route.color {
                annotationView.realTimeAnnotationColor = color
            }
        }
        else if let annotationView = annotationView as? PulsingAnnotationView {
            userLocationAnnotationView = annotationView
        }
        else if let view = annotationView as? MinimalStopAnnotationView, let arrivalDeparture = tripConvertible.arrivalDeparture {
            view.selectedArrivalDeparture = arrivalDeparture

            if let stopTime = annotation as? TripStopTime {
                view.rightCalloutAccessoryView = UIButton.chevronButton

                let calloutLabel = UILabel.autolayoutNew()
                calloutLabel.textColor = ThemeColors.shared.secondaryLabel
                calloutLabel.text = application.formatters.timeFormatter.string(from: stopTime.arrivalDate)
                view.detailCalloutAccessoryView = calloutLabel
            }

            view.canShowCallout = true
        }

        return annotationView
    }

    private func reuseIdentifier(for annotation: MKAnnotation) -> String? {
        switch annotation {
        case is VehicleAnnotation: return MKMapView.reuseIdentifier(for: PulsingVehicleAnnotationView.self)
        case is MKUserLocation: return MKMapView.reuseIdentifier(for: PulsingAnnotationView.self)
        case is TripStopTime: return MKMapView.reuseIdentifier(for: MinimalStopAnnotationView.self)
        default: return nil
        }
    }

    public var selectedStopTime: TripStopTime? {
        didSet {
            guard !isBeingPreviewed else { return }

            var animated = true
            if isFirstStopTimeLoad {
                animated = false
                isFirstStopTimeLoad.toggle()
            }
            self.mapView.deselectAnnotation(oldValue, animated: animated)

            guard oldValue != self.selectedStopTime,
                let selectedStopTime = self.selectedStopTime else { return }

            // Fixes #220: Find matching trip stop using stop ID instead of using pointers.
            if let annotation = self.mapView.annotations
                .filter(type: TripStopTime.self)
                .filter({ $0.stopID == selectedStopTime.stopID }).first {
                self.mapView.selectAnnotation(annotation, animated: true)
            }
        }
    }
    private var isFirstStopTimeLoad = true
}
