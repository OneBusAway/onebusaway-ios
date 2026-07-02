//
//  MapPanelRootView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import SwiftUI
import OBAKitCore
import UIKit

// MARK: - MapPanelRootView

/// A pure-SwiftUI alternative to `MapViewController`: a full-screen SwiftUI
/// `Map` with the persistent floating sheet system layered on top plus the
/// floating map-control overlays (bottom-leading cluster, top-center pill).
struct MapPanelRootView: View {

    @StateObject private var coordinator: SheetCoordinator<AppSheetRoute>
    @StateObject private var mapViewModel: MapViewModel

    /// Presentation state only. The popup reads its data from
    /// `mapViewModel.weatherDisplay` so a refresh that finishes while the card
    /// is open updates the displayed forecast in place.
    @State private var isWeatherPopupPresented = false

    @Environment(\.scenePhase) private var scenePhase

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var mapSize: CGSize = .zero
    @State private var visibleRegion: MKCoordinateRegion?

    /// Location-permission dialog presentation state. Owned by the root
    @State private var permissionDialogState: MapViewModel.TopPillState?

    private let application: Application
    private let factory: AppSheetViewFactory

    init(application: Application) {
        _coordinator = StateObject(wrappedValue: SheetCoordinator<AppSheetRoute>(root: .home))
        let initialMapType: MapBaseType = application.mapRegionManager.userSelectedMapType == .mutedStandard ? .standard : .hybrid
        _mapViewModel = StateObject(wrappedValue: MapViewModel(application: application, initialMapType: initialMapType))
        self.application = application
        self.factory = AppSheetViewFactory(application: application)
    }

    var body: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()
        }
        .mapStyle(mapViewModel.mapType == .standard ? .standard : .hybrid)
        // TODO: Detent-aware bottom padding. Pinned to the collapsed sheet
        // height today, so dragging the sheet up to `.medium` or
        // `largeDetent` lets the user-location annotation and any future map
        // overlays slip under the sheet.
        .safeAreaPadding(.bottom, AppSheetRoute.homeCollapsedHeight)
        .overlay(alignment: .topLeading) {
            weatherButton
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { _, newValue in
            mapSize = newValue
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
        }
        .overlay(alignment: .top) {
            MapStatusPill(
                state: mapViewModel.topPillState,
                onZoomInForStops: zoomInForStops,
                onPermissionTap: handlePermissionTap
            )
            .padding(.top, ThemeMetrics.padding)
        }
        .overlay(alignment: .bottomTrailing) {
            MapControlsCluster(
                mapType: mapViewModel.mapType,
                isLocationButtonVisible: application.locationService.isLocationUseAuthorized,
                onToggleMapType: mapViewModel.toggleMapType,
                onCenterOnUser: centerOnUser
            )
            .padding(.trailing, ThemeMetrics.controllerMargin)
            .padding(.bottom, AppSheetRoute.homeCollapsedHeight + ThemeMetrics.padding)
        }
        .floatingSheet(coordinator: coordinator) { route in
            factory.view(for: route)
                .fullScreenCover(isPresented: $isWeatherPopupPresented) {
                    WeatherDetailPopup(
                        display: mapViewModel.weatherDisplay,
                        isPresented: $isWeatherPopupPresented
                    )
                    .presentationBackground(.clear)
                }
                .mapPermissionDialog(
                    state: $permissionDialogState,
                    onRequestAuthorization: mapViewModel.requestLocationAuthorization,
                    onOpenSettings: openSettings,
                    onRequestPreciseLocation: { mapViewModel.requestTemporaryFullAccuracy(purposeKey: "MapStatusView") }
                )
        }
        .onAppear {
            mapViewModel.start()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                mapViewModel.onAppBecameActive()
            }
        }
    }

    @ViewBuilder
    private var weatherButton: some View {
        if mapViewModel.isWeatherFeatureAvailable {
            WeatherButton(display: mapViewModel.weatherDisplay) { _ in
                isWeatherPopupPresented = true
            }
            .padding(ThemeMetrics.controllerMargin)
        }
    }

    // MARK: - Permission Tap

    /// Sets `permissionDialogState` so the `confirmationDialog` attached inside
    /// the floating sheet presents. We DO NOT invoke the OS permission APIs
    /// directly from the pill's tap: the confirmation dialog gives the user a
    /// chance to opt out ("Keep Location Off") before the native system alert
    /// fires, and — for `.locationServicesOff` and `.impreciseLocation` — the
    /// action list itself is the meaningful choice (there is no re-prompt path
    /// on iOS after the first denial).
    private func handlePermissionTap(_ state: MapViewModel.TopPillState) {
        switch state {
        case .notDetermined, .locationServicesOff, .impreciseLocation:
            permissionDialogState = state
        case .hidden, .zoomInForStops:
            break
        }
    }

    // MARK: - Actions

    private func centerOnUser() {
        guard let location = application.locationService.currentLocation else { return }
        let region = MKCoordinateRegion(
            centeredOn: location.coordinate,
            zoomLevel: mapViewModel.zoomLevelForCurrentLocation(),
            mapSize: mapSize
        )
        withAnimation {
            cameraPosition = .region(region)
        }
    }

    private func zoomInForStops() {
        // Reuse the currently-visible center by asking for the tracked visible
        // region; if the camera hasn't emitted a region yet (edge case on first
        // frame), fall back to the user location if known.
        let currentCenter: CLLocationCoordinate2D
        if let region = visibleRegion {
            currentCenter = region.center
        } else if let userLocation = application.locationService.currentLocation {
            currentCenter = userLocation.coordinate
        } else {
            return
        }
        let span = MKCoordinateSpan(
            latitudeDelta: MapViewModel.zoomInForStopsSpan,
            longitudeDelta: MapViewModel.zoomInForStopsSpan
        )
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(center: currentCenter, span: span))
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
