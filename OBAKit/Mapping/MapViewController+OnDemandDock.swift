//
//  MapViewController+OnDemandDock.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import MapKit
import OBAKitCore
import UIKit

// MARK: - On-demand dock (spec 2.4, classic shell)

extension MapViewController {

    /// Adds the dock above the search panel and binds the probe controller to
    /// the map, the layer and the highlight.
    func installOnDemandDock() {
        guard onDemandDockHost == nil else { return }
        let host = OnDemandDockHostController(
            controller: onDemandProbeController,
            actions: onDemandDockActions(),
            serviceColors: { [weak self] in self?.onDemandServiceColors ?? [:] }
        )
        addChild(host)
        view.insertSubview(host.view, belowSubview: floatingPanel.view)
        host.didMove(toParent: self)
        onDemandDockHost = host

        onDemandProbeController.$highlightedServiceID
            .removeDuplicates()
            .sink { [weak self] id in self?.mapLayerRegistrar?.onDemandLayer?.setHighlightedService(id) }
            .store(in: &host.cancellables)

        syncOnDemandLayerEnabled()
        updateOnDemandDockContext()
    }

    /// Hands the probe controller the layer's stored on/off state. Called
    /// again once the registrar has registered the layer: before that the
    /// layer's `true` default is not in UserDefaults' registration domain, so
    /// a fresh install reads false and the dock would stay hidden.
    func syncOnDemandLayerEnabled() {
        onDemandProbeController.setLayerEnabled(mapRegionManager.isMapLayerEnabled(id: OnDemandMapLayer.layerID))
    }

    /// Spec 2.4 "Nothing otherwise": a semi-modal panel, search results, the
    /// stop sheet, the survey card, or a sheet covering more than half the
    /// screen. Also re-pins the dock, whose placement follows the panel state.
    func updateOnDemandDockContext() {
        let hasFocus = hasSemiModalPanelPresented || isSearchListShown || isStopSheetPresented || isSurveyCardShown
        onDemandProbeController.setSurfaceFocus(hasFocus)

        // Read from the state, not the surface frame: the state changes before
        // the panel's move animation lays the surface out.
        let isCompact = traitCollection.horizontalSizeClass != .regular
        onDemandProbeController.setMapMostlyCovered(isCompact && floatingPanel.state == .full)
        layoutOnDemandDock()
    }

    /// Pins the dock for the current size class, anchor panel and that
    /// panel's state, and hides the planner card while its panel is full
    /// height. Runs from `viewDidLayoutSubviews` and on every planner panel
    /// state change, so it rebuilds constraints only when the placement or
    /// the anchor actually changes.
    func layoutOnDemandDock() {
        guard let host = onDemandDockHost else { return }
        // R11 over R5: the planner card anchors to the trip planner's own panel.
        let plannerPanel = semiModalTripPlannerController
        let anchoring = OnDemandDockAnchoring(
            dockState: onDemandProbeController.dockState,
            horizontalSizeClass: traitCollection.horizontalSizeClass,
            homePanelState: floatingPanel.state,
            plannerPanelState: plannerPanel?.state
        )
        host.view.isHidden = anchoring.isHidden
        let placement = anchoring.placement
        let surface: UIView = (anchoring.anchorsToPlanner ? plannerPanel?.surfaceView : nil) ?? floatingPanel.surfaceView
        guard placement != host.placement || surface !== host.placementSurface else { return }
        NSLayoutConstraint.deactivate(host.placementConstraints)
        host.placement = placement
        host.placementSurface = surface
        host.placementConstraints = placement.constraints(
            dockView: host.view,
            safeArea: view.safeAreaLayoutGuide,
            surface: surface
        )
        NSLayoutConstraint.activate(host.placementConstraints)
    }

    /// The zone colours the layer drew, so the dock and picker match the map.
    private var onDemandServiceColors: [String: UIColor] {
        mapLayerRegistrar?.onDemandLayer?.serviceColors ?? [:]
    }

    private func onDemandDockActions() -> OnDemandDockActions {
        OnDemandDockActions(
            openDetail: { [weak self] match, check in self?.presentOnDemandDetail(match, check: check) },
            openPicker: { [weak self] request in self?.presentOnDemandPicker(request) },
            call: { [weak self] url in self?.application.open(url, options: [:], completionHandler: nil) },
            openURL: { [weak self] url in self?.application.open(url, options: [:], completionHandler: nil) },
            zoomOut: { [weak self] matches in self?.zoomOutToOnDemandZones(matches) },
            panTo: { [weak self] point in self?.mapRegionManager.mapView.setCenter(point, animated: true) }
        )
    }

    /// Resolves the locality (at most one second), which the dock's check
    /// lacks, and presents the service page with the location row.
    private func presentOnDemandDetail(_ match: OnDemandServiceMatch, check: OnDemandLocationCheck) {
        Task { [weak self] in
            let locality = await OnDemandLocalityResolver().locality(for: check.coordinate)
            guard let self else { return }
            let resolved = OnDemandLocationCheck(source: check.source, isInside: check.isInside, locality: locality, coordinate: check.coordinate)
            presentOnDemandServicePage(makeOnDemandServicePage(match.service, check: resolved))
        }
    }

    /// The address check's exact probe (spec 3.7); nil once the deployment is
    /// known to lack `/api/ondemand`.
    var onDemandCoverageProbe: OnDemandCoverageProbe? {
        guard !onDemandProbeController.isUnsupported else { return nil }
        return { [weak self] coordinate in
            guard let self else { return [] }
            return try await onDemandProbeController.probeExact(at: coordinate)
        }
    }

    /// Opens the zone detail a map item's coverage line names. The check
    /// already carries the map item's locality, so no lookup is needed.
    func openOnDemandDetail(_ match: OnDemandServiceMatch, check: OnDemandLocationCheck) {
        presentOnDemandServicePage(makeOnDemandServicePage(match.service, check: check))
    }

    /// A service page that draws the probe's full geometry when `service`
    /// came from the point probe, which carries none.
    func makeOnDemandServicePage(_ service: OnDemandService, check: OnDemandLocationCheck?) -> OnDemandServiceViewController {
        OnDemandServiceViewController(
            application: application,
            service: service,
            locationCheck: check,
            geometry: onDemandProbeController.detailGeometry(forServiceID: service.id)
        )
    }

    /// Presents a service page that keeps the zone highlight while it is open
    /// and clears it once the page closes (spec 2.3, ruling F15).
    func presentOnDemandServicePage(_ detail: OnDemandServiceViewController) {
        detail.onDismiss = { [weak self] in self?.onDemandProbeController.highlightedServiceID = nil }
        presentMediumSheet(detail)
    }

    /// Resolves the locality (at most one second) and presents the picker sheet.
    func presentOnDemandPicker(_ request: OnDemandPickerRequest) {
        Task { [weak self] in
            let locality = await OnDemandLocalityResolver().locality(for: request.coordinate)
            guard let self else { return }
            let model = OnDemandPickerModel(
                request: request,
                locality: locality,
                colors: onDemandServiceColors,
                copy: OnDemandCopy(timeZone: request.matches.first?.service.timeZone ?? .current, now: onDemandProbeController.now())
            )
            let picker = OnDemandPickerViewController(
                model: model,
                makeDetail: { [weak self] match, check in self?.makeOnDemandServicePage(match.service, check: check) },
                onHighlight: { [weak self] id in self?.onDemandProbeController.highlightedServiceID = id }
            )
            presentMediumSheet(picker)
        }
    }

    private func zoomOutToOnDemandZones(_ matches: [OnDemandServiceMatch]) {
        guard let probePoint = onDemandProbeController.probePoint else { return }
        let areas = matches.flatMap { onDemandProbeController.fullAreasByServiceID[$0.id] ?? $0.service.areas }
        guard let rect = OnDemandCameraTargets.zoomOutRect(areas: areas, probePoint: probePoint, viewportSize: mapRegionManager.mapView.bounds.size) else { return }
        mapRegionManager.mapView.setVisibleMapRect(rect, animated: true)
    }
}

// MARK: - Viewport settle

extension MapViewController {
    public func mapRegionManager(_ manager: MapRegionManager, viewportDidSettle rect: MKMapRect) {
        onDemandProbeController.mapDidSettle(
            center: manager.mapView.centerCoordinate,
            zoomLevel: OnDemandZoomLevel.level(forVisibleHeight: rect.height)
        )
    }
}
