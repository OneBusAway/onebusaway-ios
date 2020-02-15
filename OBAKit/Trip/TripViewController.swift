//
//  TripViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 8/3/19.
//

import UIKit
import MapKit
import FloatingPanel
import OBAKitCore

class TripViewController: UIViewController,
    FloatingPanelControllerDelegate,
    Idleable,
    MKMapViewDelegate {

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

    override func viewDidLoad() {
        super.viewDidLoad()

        mapView.showsUserLocation = application.locationService.isLocationUseAuthorized
        mapView.showsTraffic = application.mapRegionManager.mapViewShowsTraffic
        mapView.showsScale = application.mapRegionManager.mapViewShowsScale
        application.mapRegionManager.registerAnnotationViews(mapView: mapView)

        navigationItem.titleView = titleView
        updateTitleView()

        navigationItem.rightBarButtonItem = UIBarButtonItem(image: Icons.refresh, style: .plain, target: self, action: #selector(refresh(_:)))

        view.addSubview(mapView)
        mapView.pinToSuperview(.edges)

        loadData()

        floatingPanel.addPanel(toParent: self)
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

    // MARK: - NSUserActivity

    /// Creates and assigns an `NSUserActivity` object corresponding to this trip.
    private func beginUserActivity() {
        guard
            let region = application.regionsService.currentRegion,
            let activity = application.userActivityBuilder.userActivity(for: tripConvertible, region: region)
        else {
            return
        }

        self.userActivity = activity
    }

    // MARK: - Idle Timer

    public var idleTimerFailsafe: Timer?

    // MARK: - Title View

    private let titleView = StackedMarqueeTitleView(width: 178.0)

    private func updateTitleView() {
        guard let tripStatus = tripConvertible.tripStatus else {
            titleView.topLabel.text = ""
            titleView.bottomLabel.text = ""
            return
        }

        if let vehicleID = tripStatus.vehicleID {
            titleView.topLabel.text = vehicleID
        }

        if let lastUpdate = tripStatus.lastUpdate {
            let format = OBALoc("trip_details_controller.last_report_fmt", value: "Last report: %@", comment: "Last report: <TIME>")
            let time = application.formatters.timeFormatter.string(from: lastUpdate)
            titleView.bottomLabel.text = String(format: format, time)
        }
    }

    // MARK: - Drawer/Trip Details UI

    private lazy var tripDetailsController = TripFloatingPanelController(
        application: application,
        tripConvertible: tripConvertible
    )

    /// The floating panel controller, which displays a drawer at the bottom of the map.
    private lazy var floatingPanel: FloatingPanelController = {
        let panel = FloatingPanelController(delegate: self)
        panel.isRemovalInteractionEnabled = false
        panel.surfaceView.cornerRadius = ThemeMetrics.cornerRadius

        // Set a content view controller.
        panel.set(contentViewController: tripDetailsController)

        return panel
    }()

    public func floatingPanel(_ vc: FloatingPanelController, layoutFor newCollection: UITraitCollection) -> FloatingPanelLayout? {
        return MapPanelLayout(initialPosition: .half)
    }

    func floatingPanelDidChangePosition(_ vc: FloatingPanel.FloatingPanelController) {
        if vc.position == .full {
            tripDetailsController.removeBottomInsetPadding()
        }
        else {
            tripDetailsController.addBottomInsetPadding()
        }
    }

    // MARK: - Trip Details Data

    private var tripDetailsOperation: TripDetailsModelOperation?

    private var currentTripStatus: TripStatus?

    private func loadTripDetails() {
        guard let apiService = application.restAPIModelService else {
            return
        }

        tripDetailsOperation?.cancel()

        let op = apiService.getTripDetails(tripID: tripConvertible.trip.id, vehicleID: tripConvertible.vehicleID, serviceDate: tripConvertible.serviceDate)
        op.then { [weak self] in
            guard
                let self = self,
                let tripDetails = op.tripDetails
            else { return }

            self.tripDetailsController.tripDetails = tripDetails
            self.mapView.updateAnnotations(with: tripDetails.stopTimes)

            if let currentTripStatus = self.currentTripStatus {
                self.mapView.removeAnnotation(currentTripStatus)
                self.currentTripStatus = nil
            }

            if let tripStatus = tripDetails.status {
                self.currentTripStatus = tripStatus
                self.mapView.addAnnotation(tripStatus)
            }
        }
        tripDetailsOperation = op
    }

    // MARK: - Map Data

    private var shapeOperation: ShapeModelOperation?
    private var routePolyline: MKPolyline?

    private func loadMapPolyline() {
        guard
            let apiService = application.restAPIModelService,
            routePolyline == nil // No need to reload the polyline if we already have it
        else {
            return
        }

        shapeOperation?.cancel()

        let op = apiService.getShape(id: tripConvertible.trip.shapeID)
        op.then { [weak self] in
            guard
                let self = self,
                let polyline = op.polyline
            else { return }

            self.routePolyline = polyline

            self.mapView.addOverlay(polyline)

            self.mapView.visibleMapRect = self.mapView.mapRectThatFits(polyline.boundingMapRect, edgePadding: UIEdgeInsets(top: 60, left: 20, bottom: 220, right: 20))
        }

        shapeOperation = op
    }

    // MARK: - Load Data

    @objc private func refresh(_ sender: Any) {
        loadData()
    }

    private func loadData() {
        loadTripDetails()
        loadMapPolyline()
    }

    // MARK: - Map View

    private lazy var mapView: MKMapView = {
        let map = MKMapView.autolayoutNew()
        map.delegate = self
        return map
    }()

    public func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard let stopTime = view.annotation as? TripStopTime else {
            return
        }

        tripDetailsController.highlightStopInList(stopTime.stop)
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

    public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let reuseIdentifier = reuseIdentifier(for: annotation) else {
            return nil
        }

        let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier, for: annotation)

        if let annotationView = annotationView as? PulsingVehicleAnnotationView {
            vehicleAnnotationView = annotationView
        }

        if let annotationView = annotationView as? PulsingAnnotationView {
            userLocationAnnotationView = annotationView
        }

        if let view = annotationView as? MinimalStopAnnotationView, let arrivalDeparture = tripConvertible.arrivalDeparture {
            view.selectedArrivalDeparture = arrivalDeparture
            view.canShowCallout = true
        }

        return annotationView
    }

    private func reuseIdentifier(for annotation: MKAnnotation) -> String? {
        switch annotation {
        case is MKUserLocation: return MKMapView.reuseIdentifier(for: PulsingAnnotationView.self)
        case is TripStopTime: return MKMapView.reuseIdentifier(for: MinimalStopAnnotationView.self)
        case is TripStatus: return MKMapView.reuseIdentifier(for: PulsingVehicleAnnotationView.self)
        default: return nil
        }
    }
}
