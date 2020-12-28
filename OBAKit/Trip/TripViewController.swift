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

    private let tripConvertible: TripConvertible

    init(application: Application, tripConvertible: TripConvertible) {
        self.application = application
        self.tripConvertible = tripConvertible

        super.init(nibName: nil, bundle: nil)
    }

    init(application: Application, arrivalDeparture: ArrivalDeparture) {
        self.application = application
        self.tripConvertible = TripConvertible(arrivalDeparture: arrivalDeparture)

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        shapeOperation?.cancel()
        enableIdleTimer()
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
        if #available(iOS 14, *) {
            mapView.showsUserLocation = application.locationService.isLocationUseAuthorized && application.locationService.accuracyAuthorization == .fullAccuracy
        } else {
            mapView.showsUserLocation = application.locationService.isLocationUseAuthorized
        }
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
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        disableIdleTimer()
        beginUserActivity()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        enableIdleTimer()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateTitleView()
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
        }
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

        if let vehicleID = tripStatus.vehicleID {
            titleView.topLabel.text = vehicleID
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
                self.tripDetailsController.collectionController.view.alpha = self.showTripDetails ? 1.0 : 0.0
            }
        }
    }

    private lazy var tripDetailsController = TripFloatingPanelController(
        application: application,
        tripConvertible: tripConvertible,
        parentTripViewController: self
    )

    /// The floating panel controller, which displays a drawer at the bottom of the map.
    private lazy var floatingPanel: FloatingPanelController = {
        let panel = FloatingPanelController(delegate: self)
        panel.isRemovalInteractionEnabled = false
        panel.surfaceView.cornerRadius = ThemeMetrics.cornerRadius
        panel.contentMode = .fitToBounds

        // Set a content view controller.
        panel.set(contentViewController: tripDetailsController)

        return panel
    }()

    public func floatingPanel(_ vc: FloatingPanelController, layoutFor newCollection: UITraitCollection) -> FloatingPanelLayout? {
        let layout: FloatingPanelLayout
        switch newCollection.horizontalSizeClass {
        case .regular:
            layout = MapPanelLandscapeLayout(initialPosition: .tip)
        default:
            layout = MapPanelLayout(initialPosition: .tip)
        }

        return layout
    }

    func floatingPanelShouldBeginDragging(_ vc: FloatingPanelController) -> Bool {
        // If data is loading, don't allow panel change.
        // If operation is nil, data has probably never loaded.
        return !(self.tripDetailsOperation?.isExecuting ?? true)
    }

    func floatingPanelDidMove(_ vc: FloatingPanelController) {
        showTripDetails = true
    }

    func floatingPanelDidChangePosition(_ vc: FloatingPanel.FloatingPanelController) {
        showTripDetails = vc.position != .tip

        // We don't need to set the map view's margins if the drawer will take up the whole screen.
        if vc.position != .full {
            let drawerHeight = vc.layout.insetFor(position: vc.position) ?? 0
            mapView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: drawerHeight, trailing: 0)
        }

        self.tripDetailsController.configureView(for: vc.position)
    }

    // MARK: - Trip Details Data

    private var tripDetailsOperation: DecodableOperation<RESTAPIResponse<TripDetails>>?

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

    private func loadTripDetails(isProgrammatic: Bool) {
        guard let apiService = application.restAPIService else {
            return
        }

        tripDetailsOperation?.cancel()

        self.navigationItem.rightBarButtonItem = self.activityIndicatorButton

        // Let the user still look at data if there was already details from a previous request.
        self.floatingPanel.surfaceView.grabberHandle.isHidden = self.tripDetailsController.tripDetails == nil

        let op = apiService.getTrip(tripID: tripConvertible.trip.id, vehicleID: tripConvertible.vehicleID, serviceDate: tripConvertible.serviceDate)
        op.complete { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                self.application.displayError(error)
            case .success(let response):
                self.tripDetailsController.tripDetails = response.entry
                self.mapView.updateAnnotations(with: response.entry.stopTimes)

                self.currentTripStatus = response.entry.status

                // In cases where TripStatus.coordinates is (0,0), we don't want to show it.
                var annotationsToShow = self.mapView.annotations
                annotationsToShow.removeAll(where: { $0.coordinate.isNullIsland })

                if !self.mapView.hasBeenTouched {
                    self.mapView.showAnnotations(annotationsToShow, animated: true)
                }

                if let arrivalDeparture = self.tripConvertible.arrivalDeparture {
                    let userDestinationStopTime = response.entry.stopTimes.filter { $0.stopID == arrivalDeparture.stopID }.first
                    self.selectedStopTime = userDestinationStopTime
                }

                self.floatingPanel.surfaceView.grabberHandle.isHidden = false

                if isProgrammatic && !self.mapView.hasBeenTouched {
                    self.floatingPanel.show(animated: true) {
                        self.floatingPanel.move(to: .half, animated: true)
                    }
                }
            }

            self.navigationItem.rightBarButtonItem = self.reloadButton
            self.tripDetailsController.progressView.isHidden = true
        }
        tripDetailsOperation = op

        self.tripDetailsController.progressView.isHidden = false
        self.tripDetailsController.progressView.observedProgress = op.progress
    }

    // MARK: - Map Data

    private var shapeOperation: DecodableOperation<RESTAPIResponse<PolylineEntity>>?
    private var routePolyline: MKPolyline?

    private func loadMapPolyline(isProgrammatic: Bool) {
        guard
            let apiService = application.restAPIService,
            routePolyline == nil // No need to reload the polyline if we already have it
        else {
            return
        }

        shapeOperation?.cancel()

        let op = apiService.getShape(id: tripConvertible.trip.shapeID)
        op.complete { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                self.application.displayError(error)
            case .success(let response):
                guard let polyline = response.entry.polyline else { return }
                self.routePolyline = polyline
                self.mapView.addOverlay(polyline)
                if !self.mapView.hasBeenTouched {
                    self.mapView.visibleMapRect = self.mapView.mapRectThatFits(polyline.boundingMapRect, edgePadding: UIEdgeInsets(top: 60, left: 20, bottom: 60, right: 20))
                }
            }
        }

        shapeOperation = op
    }

    // MARK: - Load Data

    @objc private func refresh(_ sender: Any) {
        loadData(isProgrammatic: false)
    }

    private func loadData(isProgrammatic: Bool) {
        loadTripDetails(isProgrammatic: isProgrammatic)
        loadMapPolyline(isProgrammatic: isProgrammatic)
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
        return map
    }()

    public func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard
            let stopTime = view.annotation as? TripStopTime,
            let selectedAnnotation = mapView.selectedAnnotations.first as? TripStopTime,
            stopTime != selectedAnnotation
        else { return }

        func mapViewAnnotationSelectionComplete() {
            if !self.mapView.hasBeenTouched {
                self.mapView.setCenter(stopTime.stop.coordinate, animated: true)
            }
            self.tripDetailsController.highlightStopInList(stopTime.stop)
        }

        if self.mapView.hasBeenTouched {
            mapViewAnnotationSelectionComplete()
        }
        else {
            floatingPanel.move(to: .half, animated: true, completion: mapViewAnnotationSelectionComplete)
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
        renderer.strokeColor = ThemeColors.shared.brand.withAlphaComponent(0.75)
        renderer.lineWidth = 3.0
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
