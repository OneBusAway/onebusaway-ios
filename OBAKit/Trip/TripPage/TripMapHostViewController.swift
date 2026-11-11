//
//  TripMapHostViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import FloatingPanel
import MapKit
import UIKit
import OBAKitCore

/// The trip page over a map of its own, for every screen that pushes a trip
/// full-screen with nothing behind it: shared trip links, alarms, My Trip,
/// vehicle search and the legacy stop page.
///
/// The second host the trip page design names (`docs/superpowers/specs/2026-07-31-trip-page-rethink-design.md`):
/// one page, two hosts, one map layer. The map tab's stop sheet and the map
/// panel already have a map, and host `TripPageViewController` directly. Here the
/// page sits in a floating panel, and a `TripFocusMapLayer` draws what it
/// publishes on this controller's `MKMapView`, as `MapViewController.wireTripFocus`
/// does on the map tab's.
///
/// The panel is an `OBAFloatingPanelController`, as the map tab's is, rather
/// than a `StopSheetPresenter` sheet. That presenter wraps its content in a
/// navigation controller of its own, so a stop tapped on the trip would open
/// inside the sheet and the page's Back would close the sheet instead of popping
/// this screen, and it hides the tab bar for a sheet over the map tab.
final class TripMapHostViewController: UIViewController,
    AppContext,
    FloatingPanelControllerDelegate,
    MKMapViewDelegate,
    Previewable {

    let application: Application

    /// The page in the panel. It owns the trip's loading, its actions and its
    /// way back; this controller only supplies the map and the panel.
    let tripPage: TripPageViewController

    /// The stop a shared trip link named as the sharer's exit, or `nil` for every
    /// other way into this screen.
    var destinationStopID: StopID? { tripPage.destinationStopID }

    /// - Parameter destinationStopID: Where the sharer said they will step off,
    ///   when this came from a shared trip link that named one. See #449.
    init(application: Application, tripConvertible: TripConvertible, destinationStopID: StopID? = nil) {
        self.application = application
        self.tripPage = TripPageViewController(
            application: application,
            tripConvertible: tripConvertible,
            destinationStopID: destinationStopID
        )

        super.init(nibName: nil, bundle: nil)

        tripPage.onMapFocusChanged = { [weak self] focus in
            self?.showOnMap(focus)
        }
    }

    convenience init(application: Application, arrivalDeparture: ArrivalDeparture, destinationStopID: StopID? = nil) {
        self.init(
            application: application,
            tripConvertible: TripConvertible(arrivalDeparture: arrivalDeparture),
            destinationStopID: destinationStopID
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        // Don't show the rider's location when accuracy is reduced: an imprecise
        // circle beside a precise trip reads as the app being wrong.
        mapView.showsUserLocation = application.locationService.isLocationUseAuthorized
            && application.locationService.accuracyAuthorization == .fullAccuracy
        mapView.showsTraffic = application.mapRegionManager.mapViewShowsTraffic
        mapView.showsScale = application.mapRegionManager.mapViewShowsScale
        // The vehicle and rider markers dequeue the app's shared annotation views.
        application.mapRegionManager.registerAnnotationViews(mapView: mapView)

        view.addSubview(mapView)
        mapView.pinToSuperview(.edges)

        tripLayer.cameraInsets = { [weak self] in self?.cameraInsets() ?? .zero }

        // Added in preview mode too, but hidden: the page has to be on screen to
        // load the trip and publish what the map draws.
        floatingPanel.addPanel(toParent: self)
        floatingPanel.view.isHidden = isBeingPreviewed
        tripPage.setAtTip(floatingPanel.state == .tip)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateMapLayoutMargins()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The map is hidden from VoiceOver, so the panel is the whole screen to a
        // VoiceOver user.
        if UIAccessibility.isVoiceOverRunning, !isBeingPreviewed {
            floatingPanel.move(to: .full, animated: true)
        }

        // A committed preview frames the trip again now that it has the screen.
        // Framed while still in the preview, it would fit a 320 pt glance.
        if needsReframeAfterPreview, let shownFocus {
            needsReframeAfterPreview = false
            showOnMap(shownFocus)
        }
    }

    // MARK: - Map

    private(set) lazy var mapView: MKMapView = {
        let map = MKMapView.autolayoutNew()
        map.delegate = self
        map.mapType = application.mapRegionManager.userSelectedMapType
        map.accessibilityElementsHidden = true
        return map
    }()

    /// Draws the trip the page publishes. Built against this controller's own map,
    /// so it never touches the map tab's.
    private(set) lazy var tripLayer = TripFocusMapLayer(mapView: mapView)

    /// What the map is drawing, kept so a committed preview can frame it again.
    private var shownFocus: TripMapFocus?

    private func showOnMap(_ focus: TripMapFocus?) {
        shownFocus = focus
        if let focus {
            tripLayer.begin(focus: focus)
        } else {
            tripLayer.end()
        }
    }

    /// The part of the map a trip is framed into: what the panel leaves uncovered.
    ///
    /// Computed rather than measured, as `MapViewController.sheetCameraInsets()`
    /// is: the trip frames once, on its first load, while the panel is still
    /// settling at the detent it opens at.
    private func cameraInsets() -> UIEdgeInsets {
        Self.cameraInsets(
            mapSize: mapView.bounds.size,
            safeArea: mapView.safeAreaInsets,
            safeAreaHeight: mapView.safeAreaLayoutGuide.layoutFrame.height,
            panelCoverage: isBeingPreviewed ? .none : (traitCollection.horizontalSizeClass == .regular ? .leading : .bottomHalf)
        )
    }

    /// Where the panel covers the map.
    enum PanelCoverage {
        /// No panel: a preview shows the map alone.
        case none
        /// `MapPanelLayout` at `.half`, where it opens.
        case bottomHalf
        /// `MapPanelLandscapeLayout`, a column pinned to the left.
        case leading
    }

    /// Internal for tests.
    static func cameraInsets(
        mapSize: CGSize,
        safeArea: UIEdgeInsets,
        safeAreaHeight: CGFloat,
        panelCoverage: PanelCoverage
    ) -> UIEdgeInsets {
        switch panelCoverage {
        case .none:
            return MapCameraInsets.insets(mapSize: mapSize, safeArea: safeArea)
        case .bottomHalf:
            // The stock `.half` anchor is half the safe area, not half the screen.
            // See `StopSheetLayout.halfDetentInset(safeAreaHeight:)`.
            let panel = safeArea.bottom + StopSheetLayout.halfDetentInset(safeAreaHeight: safeAreaHeight)
            return MapCameraInsets.insets(mapSize: mapSize, safeArea: safeArea, bottomObstruction: panel)
        case .leading:
            // `MapPanelLandscapeLayout` pins the panel to the physical left, 8 pt
            // in from the safe area, whatever the layout direction.
            let panel = safeArea.left + 8 + MapPanelLandscapeLayout.WidthSize
            return MapCameraInsets.insets(mapSize: mapSize, safeArea: safeArea, leftObstruction: panel)
        }
    }

    // MARK: - MKMapViewDelegate

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        tripLayer.renderer(for: overlay, in: mapView) ?? MKOverlayRenderer(overlay: overlay)
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation {
            return mapView.dequeueReusableAnnotationView(
                withIdentifier: MKMapView.reuseIdentifier(for: PulsingAnnotationView.self),
                for: annotation
            )
        }
        return tripLayer.annotationView(for: annotation, in: mapView)
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        tripLayer.viewportDidChange(mapView.visibleMapRect)
    }

    /// A stop's dot opens the stop, transfer context and all, as tapping its row does.
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard let stop = view.annotation as? TripStopAnnotation else { return }

        // Leaving the dot selected only strands a highlight: MapKit won't fire
        // `didSelect` for it again.
        mapView.deselectAnnotation(stop, animated: false)

        application.analytics?.reportEvent(
            pageURL: "app://localhost/trip",
            label: AnalyticsLabels.mapStopAnnotationTapped,
            value: nil
        )

        tripPage.openStop(stop.row)
    }

    // MARK: - Panel

    private(set) lazy var floatingPanel: OBAFloatingPanelController = {
        let panel = OBAFloatingPanelController(application, delegate: self)
        panel.isRemovalInteractionEnabled = false
        panel.surfaceView.appearance.cornerRadius = ThemeMetrics.cornerRadius
        // As `StopSheetPresenter` sets them, for the same page: `.fitToBounds`
        // keeps the page's pinned action bar on the panel's visible bottom edge
        // at every detent, and `.never` leaves the page's SwiftUI scroll view its
        // own insets.
        panel.contentMode = .fitToBounds
        panel.contentInsetAdjustmentBehavior = .never
        panel.set(contentViewController: tripPage)
        return panel
    }()

    /// Opens at `.half`, where the map tab's stop sheet opens a trip, rather than
    /// `.tip`: the page's collapsed form is only its back row, with nothing about
    /// the trip in it.
    func floatingPanel(_ vc: FloatingPanelController, layoutFor newCollection: UITraitCollection) -> FloatingPanelLayout {
        switch newCollection.horizontalSizeClass {
        case .regular:
            return MapPanelLandscapeLayout(initialState: .half)
        default:
            return MapPanelLayout(initialState: .half)
        }
    }

    /// At `.tip` the page drops its pinned action bar, which is taller than the
    /// detent. See `TripPageViewController.setAtTip(_:)`.
    func floatingPanelDidChangeState(_ fpc: FloatingPanelController) {
        tripPage.setAtTip(fpc.state == .tip)
        updateMapLayoutMargins()
    }

    /// Keeps the map's own furniture (the legal label, the scale, the compass)
    /// in the part of the map the panel leaves uncovered. Left alone at `.full`,
    /// where nothing of the map shows.
    private func updateMapLayoutMargins() {
        guard floatingPanel.state != .full else { return }
        mapView.layoutMargins = Self.mapLayoutMargins(
            panelState: floatingPanel.state,
            panelCoverage: isBeingPreviewed ? .none : (traitCollection.horizontalSizeClass == .regular ? .leading : .bottomHalf),
            safeAreaHeight: view.safeAreaLayoutGuide.layoutFrame.height
        )
    }

    /// Internal for tests. Physical rather than directional insets: the
    /// landscape panel sits on the left in either layout direction.
    static func mapLayoutMargins(
        panelState: FloatingPanelState,
        panelCoverage: PanelCoverage,
        safeAreaHeight: CGFloat
    ) -> UIEdgeInsets {
        switch panelCoverage {
        case .none:
            return .zero
        case .leading:
            return UIEdgeInsets(top: 0, left: MapPanelLandscapeLayout.WidthSize + ThemeMetrics.padding, bottom: 0, right: 0)
        case .bottomHalf:
            let bottom = panelState == .half ? safeAreaHeight / 2 : MapPanelLayout.EstimatedDrawerTipStateHeight
            return UIEdgeInsets(top: 0, left: 0, bottom: bottom, right: 0)
        }
    }

    // MARK: - Previewable

    /// Set before the view loads, by a context menu showing this as a preview.
    private(set) var isBeingPreviewed = false

    /// The map alone: the trip still loads and draws, because the page is on
    /// screen behind a hidden panel.
    func enterPreviewMode() {
        isBeingPreviewed = true
        if isViewLoaded {
            floatingPanel.view.isHidden = true
        }
    }

    /// Set when a preview is committed, so the trip is framed again once the
    /// host has the screen. See `viewDidAppear(_:)`.
    private var needsReframeAfterPreview = false

    /// Brings the panel up when a preview is committed and pushed. The panel
    /// is already at `.half` behind the hidden view, where it opened.
    func exitPreviewMode() {
        isBeingPreviewed = false
        guard isViewLoaded else { return }
        floatingPanel.view.isHidden = false
        needsReframeAfterPreview = true
        updateMapLayoutMargins()
    }
}
