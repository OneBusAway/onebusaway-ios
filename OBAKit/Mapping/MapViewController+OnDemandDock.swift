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

        onDemandProbeController.setLayerEnabled(mapRegionManager.isMapLayerEnabled(id: OnDemandMapLayer.layerID))
        updateOnDemandDockContext()
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

    /// Pins the dock for the current size class and panel state. Runs from
    /// `viewDidLayoutSubviews`, so it rebuilds constraints only when the
    /// placement actually changes.
    func layoutOnDemandDock() {
        guard let host = onDemandDockHost else { return }
        let placement = OnDemandDockPlacement.placement(
            horizontalSizeClass: traitCollection.horizontalSizeClass,
            isPanelFullHeight: floatingPanel.state == .full
        )
        guard placement != host.placement else { return }
        NSLayoutConstraint.deactivate(host.placementConstraints)
        host.placement = placement
        host.placementConstraints = placement.constraints(
            dockView: host.view,
            safeArea: view.safeAreaLayoutGuide,
            surface: floatingPanel.surfaceView
        )
        NSLayoutConstraint.activate(host.placementConstraints)
    }

    /// The zone colours the layer drew, so the dock and picker match the map.
    private var onDemandServiceColors: [String: UIColor] {
        mapLayerRegistrar?.onDemandLayer?.serviceColors ?? [:]
    }

    private func onDemandDockActions() -> OnDemandDockActions {
        OnDemandDockActions(
            openDetail: { [weak self] match, _ in
                guard let self else { return }
                presentMediumSheet(OnDemandServiceViewController(application: application, service: match.service))
            },
            openPicker: { [weak self] request in self?.presentOnDemandPicker(request) },
            call: { [weak self] url in self?.application.open(url, options: [:], completionHandler: nil) },
            openURL: { [weak self] url in self?.application.open(url, options: [:], completionHandler: nil) },
            zoomOut: { [weak self] matches in self?.zoomOutToOnDemandZones(matches) },
            panTo: { [weak self] point in self?.mapRegionManager.mapView.setCenter(point, animated: true) }
        )
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
            let picker = OnDemandPickerViewController(application: application, model: model) { [weak self] id in
                self?.onDemandProbeController.highlightedServiceID = id
            }
            presentMediumSheet(picker)
        }
    }

    private func zoomOutToOnDemandZones(_ matches: [OnDemandServiceMatch]) {
        guard let probePoint = onDemandProbeController.probePoint else { return }
        let areas = matches.flatMap { onDemandProbeController.fullAreasByServiceID[$0.id] ?? $0.service.areas }
        guard let rect = OnDemandCameraTargets.zoomOutRect(areas: areas, probePoint: probePoint) else { return }
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
