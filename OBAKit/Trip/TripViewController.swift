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

    private let arrivalDeparture: ArrivalDeparture

    init(application: Application, arrivalDeparture: ArrivalDeparture) {
        self.application = application
        self.arrivalDeparture = arrivalDeparture

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

        view.addSubview(mapView)
        mapView.pinToSuperview(.edges)

        loadTripDetails()
        loadMapPolyline()

        floatingPanel.addPanel(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        disableIdleTimer()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        enableIdleTimer()
    }

    // MARK: - Idle Timer

    public var idleTimerFailsafe: Timer?

    // MARK: - Title View

    private let titleView = StackedMarqueeTitleView(width: 178.0)

    private func updateTitleView() {
        if let vehicleID = arrivalDeparture.tripStatus?.vehicleID {
            titleView.topLabel.text = vehicleID
        }
        else {
            titleView.topLabel.text = ""
        }

        if let tripStatus = arrivalDeparture.tripStatus, let lastUpdate = tripStatus.lastUpdate {
            let format = NSLocalizedString("trip_details_controller.last_report_fmt", value: "Last report: %@", comment: "Last report: <TIME>")
            let time = application.formatters.timeFormatter.string(from: lastUpdate)
            titleView.bottomLabel.text = String(format: format, time)
        }
    }

    // MARK: - Drawer/Trip Details UI

    private lazy var tripDetailsController: TripDetailsController = {
        let controller = TripDetailsController(application: application, arrivalDeparture: arrivalDeparture)
        return controller
    }()

    /// The floating panel controller, which displays a drawer at the bottom of the map.
    private lazy var floatingPanel: FloatingPanelController = {
        let panel = FloatingPanelController(delegate: self)
        panel.isRemovalInteractionEnabled = false
        panel.surfaceView.cornerRadius = ThemeMetrics.cornerRadius

        // Set a content view controller.
        panel.set(contentViewController: tripDetailsController)

        // Track a scroll view(or the siblings) in the content view controller.
        panel.track(scrollView: tripDetailsController.collectionController.collectionView)

        return panel
    }()

    public func floatingPanel(_ vc: FloatingPanelController, layoutFor newCollection: UITraitCollection) -> FloatingPanelLayout? {
        return MapPanelLayout(initialPosition: .half)
    }

    // MARK: - Trip Details Data

    private var tripDetailsOperation: TripDetailsModelOperation?

    private func loadTripDetails() {
        guard let apiService = application.restAPIModelService else {
            return
        }

        tripDetailsOperation?.cancel()

        let op = apiService.getTripDetails(tripID: arrivalDeparture.tripID, vehicleID: arrivalDeparture.vehicleID, serviceDate: arrivalDeparture.serviceDate)
        op.then { [weak self] in
            guard
                let self = self,
                let tripDetails = op.tripDetails
            else { return }

            self.tripDetailsController.tripDetails = tripDetails
            self.mapView.removeAllAnnotations()
            let stops = tripDetails.stopTimes.map { $0.stop }
            self.mapView.addAnnotations(stops)
        }
        tripDetailsOperation = op
    }

    // MARK: - Map Data

    private var shapeOperation: ShapeModelOperation?

    private func loadMapPolyline() {
        guard let apiService = application.restAPIModelService else {
            return
        }

        shapeOperation?.cancel()

        let op = apiService.getShape(id: arrivalDeparture.trip.shapeID)
        op.then { [weak self] in
            guard
                let self = self,
                let polyline = op.polyline
            else { return }

            self.mapView.addOverlay(polyline)

            self.mapView.visibleMapRect = self.mapView.mapRectThatFits(polyline.boundingMapRect, edgePadding: UIEdgeInsets(top: 60, left: 20, bottom: 220, right: 20))
        }

        shapeOperation = op
    }

    // MARK: - Map View

    private lazy var mapView: MKMapView = {
        let map = MKMapView.autolayoutNew()
        map.delegate = self
        return map
    }()

    // MARK: - DRY up with MapRegionManager

    public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        let renderer = MKPolylineRenderer(polyline: overlay as! MKPolyline) // swiftlint:disable:this force_cast
        renderer.strokeColor = ThemeColors.shared.primary.withAlphaComponent(0.75)
        renderer.lineWidth = 3.0
        renderer.lineCap = .round

        return renderer
    }

    private var userLocationAnnotationView: PulsingAnnotationView?

    public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let reuseIdentifier = reuseIdentifier(for: annotation) else {
            return nil
        }

        let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier, for: annotation)

        if self.userLocationAnnotationView == nil, let userLocation = annotationView as? PulsingAnnotationView {
            self.userLocationAnnotationView = userLocation
        }

        return annotationView
    }

    private func reuseIdentifier(for annotation: MKAnnotation) -> String? {
        switch annotation {
        case is MKUserLocation: return MKMapView.reuseIdentifier(for: PulsingAnnotationView.self)
        case is Stop: return MKMapView.reuseIdentifier(for: StopAnnotationView.self)
        default: return nil
        }
    }
}
