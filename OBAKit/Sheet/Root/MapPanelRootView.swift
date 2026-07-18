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
/// floating map-control overlays (bottom-trailing cluster, top-center pill).
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

    // Measured height of the top-center status pill, used to offset the
    // weather button so the two don't overlap when the pill is visible.
    // Zero when the pill isn't rendered (`.hidden` state), which naturally
    // collapses the weather-button padding.
    @State private var pillHeight: CGFloat = 0

    // Location-permission alert presentation state. Owned by the root.
    @State private var permissionAlertState: MapViewModel.TopPillState?

    private let application: Application

    // Live sheet height, clamped to `[0, halfScreenHeight]`. Seeded to the
    // collapsed detent so overlays render at their resting position on the
    // first frame — before `.onGeometryChange` reports a value.
    @State private var sheetHeight: CGFloat = AppSheetRoute.homeCollapsedHeight
    @State private var toolbarsAnimationDuration: CGFloat = 0
    @State private var toolbarsOpacity: CGFloat = 1

    @State private var halfScreenHeight: CGFloat = 350

    /// Points of fade band immediately below the clamp ceiling. Toolbar
    /// opacity ramps from 1 → 0 across this window as the sheet approaches `halfScreenHeight`.
    private let toolbarFadeRange: CGFloat = 50

    private let factory: AppSheetViewFactory

    init(application: Application, factory: AppSheetViewFactory) {
        _coordinator = StateObject(wrappedValue: SheetCoordinator<AppSheetRoute>(root: .home))
        let initialMapType = MapBaseType(application.mapRegionManager.userSelectedMapType)
        _mapViewModel = StateObject(wrappedValue: MapViewModel(application: application, initialMapType: initialMapType))
        self.application = application
        self.factory = factory
    }

    var body: some View {
        // TODO: Wire this SwiftUI `Map` to `application.mapRegionManager`.
        // The UIKit `MapViewController` flow populates
        // `mapRegionManager.stops` via `MapRegionManager.requestStops`
        // whenever its MKMapView's region changes; both `RoutePickerViewModel`
        // and `CurrentTripViewModel` read from that cache before falling back
        // to a coordinate-based API call. Because this SwiftUI `Map` never
        // touches `MapRegionManager`, the cache stays empty here and the
        // pickers always hit the coordinate-fallback path — producing a
        // different (often larger) route list than the UIKit picker shows for
        // the same on-screen viewport. Fix is to observe `cameraPosition`
        // changes, convert to an `MKCoordinateRegion`, and feed it into
        // `MapRegionManager` so both surfaces agree on the cached stop set
        // (also unblocks rendering stop annotations on the SwiftUI map).
        Map(position: $cameraPosition) {
            UserAnnotation()
        }
        .mapStyle(mapViewModel.mapType == .standard ? .standard(emphasis: .muted) : .hybrid)
        .safeAreaPadding(.bottom, 180)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height / 2
        } action: { _, newValue in
            halfScreenHeight = newValue
        }
        // TODO: Detent-aware bottom padding. Pinned to the collapsed sheet
        // height today, so dragging the sheet up to `.medium` or
        // `largeDetent` lets the user-location annotation and any future map
        // overlays slip under the sheet.
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
            // Drive the "Zoom in for stops" pill from the same threshold the
            // UIKit map uses (`MapRegionManager.zoomInStatus`), so the SwiftUI
            // surface shows the warning — and its zoom-in action becomes
            // reachable — when the region is too broad to load stops.
            mapViewModel.updateZoomWarning(
                MapRegionManager.shouldShowZoomInWarning(forVisibleMapRectHeight: context.rect.height)
            )
        }
        .overlay(alignment: .top) {
            MapStatusPill(
                state: mapViewModel.topPillState,
                onZoomInForStops: zoomInForStops,
                onPermissionTap: handlePermissionTap
            )
            .padding(.top, ThemeMetrics.padding)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { _, newValue in
                // The pill collapses to `EmptyView` for `.hidden`, but the
                // enclosing padding modifier can still report a non-zero
                // height — force to zero here so overlays that offset off
                // `pillHeight` don't get a phantom top gap.
                pillHeight = mapViewModel.topPillState == .hidden ? 0 : newValue
            }
        }
        .overlay(alignment: .bottomTrailing) {
            mapControlsCluster
        }
        .overlay(alignment: .topTrailing) {
            moreButton
        }
        .overlay(alignment: .bottomLeading) {
            myTripButton
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
                // Bind the live alert state only on the base (non-stacking)
                // sheet layer. The `floatingSheet` content builder is re-invoked
                // for every stacked sheet, so binding the shared
                // `permissionAlertState` on all of them would fire multiple
                // concurrent `.alert(isPresented:)` presentations against one
                // value. The base sheet shows exactly one route at a time, so
                // this yields a single alert host.
                .mapPermissionAlert(
                    state: route.prefersStacking ? .constant(nil) : $permissionAlertState,
                    onAction: handleAlertAction
                )
                .onGeometryChange(for: CGFloat.self) { [halfScreenHeight] proxy in
                    // The transform closure is @Sendable; snapshot the @State value
                    // instead of reading main-actor view state inside it.
                    max(min(proxy.size.height, halfScreenHeight), 0)
                } action: { oldValue, newValue in
                    guard !route.prefersStacking else { return }

                    sheetHeight = newValue

                    /// Opacity calculation — fade band sits immediately
                    /// below `halfScreenHeight`.
                    let fadeStart = halfScreenHeight - toolbarFadeRange
                    let progress = max(min((newValue - fadeStart) / toolbarFadeRange, 1), 0)
                    toolbarsOpacity = 1 - progress

                    /// Animation duration
                    let diff = abs(newValue - oldValue)
                    let duration = max(min(diff / 100, 0.3), 0)
                    toolbarsAnimationDuration = duration
                }
                .ignoresSafeArea()
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
            .padding(.top, pillHeight)
            .animation(.smooth(duration: 0.3), value: pillHeight)
        }
    }

}

extension MapPanelRootView {

    // MARK: - Permission Tap

    /// Sets `permissionAlertState` so the `.alert` attached inside the
    /// floating sheet presents. We DO NOT invoke the OS permission APIs
    /// directly from the pill's tap: the alert gives the user a chance to opt
    /// out ("Keep Location Off") before the native system prompt fires, and —
    /// for `.locationServicesOff` and `.impreciseLocation` — the action list
    /// itself is the meaningful choice (there is no re-prompt path on iOS
    /// after the first denial). `.hidden` and `.zoomInForStops` are routed
    /// elsewhere by `MapStatusPill` and never reach this handler.
    private func handlePermissionTap(_ state: MapViewModel.TopPillState) {
        switch state {
        case .notDetermined, .locationServicesOff, .impreciseLocation:
            permissionAlertState = state
        case .hidden, .zoomInForStops, .locationServicesUnavailable:
            break
        }
    }

    /// Fans out an alert action to the concrete side effect. Kept as its own
    /// dispatcher so the caller-side switch stays exhaustive over
    /// `MapPermissionAlert.Action` — adding a case surfaces as a compile
    /// error rather than a silently-unhandled tap.
    private func handleAlertAction(_ action: MapPermissionAlert.Action) {
        switch action {
        case .requestAuthorization:
            mapViewModel.requestLocationAuthorization()
        case .openSettings:
            openSettings()
        case .requestPreciseLocation:
            mapViewModel.requestTemporaryFullAccuracy(purposeKey: "MapStatusView")
        }
    }

}

extension MapPanelRootView {

    // MARK: - Actions

    private func centerOnUser() {
        guard let location = application.locationService.currentLocation else { return }
        // `mapSize` is `.zero` until `.onGeometryChange` reports the first
        // layout. Building a region from a zero size yields a zero-span
        // `MKCoordinateSpan` and animates the Map to a degenerate zoom, so skip
        // until we have a real size (the next tap, post-layout, works).
        guard mapSize != .zero else { return }
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

    private var moreButton: some View {
        MoreButton {
            coordinator.push(.more)
        }
        .padding(ThemeMetrics.controllerMargin)
        .padding(.top, pillHeight)
        .animation(.smooth(duration: 0.3), value: pillHeight)
    }

    private var myTripButton: some View {
        MyTripButton {
            coordinator.push(.routePicker)
        }
        .padding(.leading, ThemeMetrics.controllerMargin)
        .floatingOverSheet(height: sheetHeight, opacity: toolbarsOpacity, duration: toolbarsAnimationDuration)
    }

    private var mapControlsCluster: some View {
        MapControlsCluster(
            mapType: mapViewModel.mapType,
            isLocationButtonVisible: application.locationService.isLocationUseAuthorized,
            onToggleMapType: mapViewModel.toggleMapType,
            onCenterOnUser: centerOnUser
        )
        .padding(.trailing, ThemeMetrics.controllerMargin)
        .floatingOverSheet(height: sheetHeight, opacity: toolbarsOpacity, duration: toolbarsAnimationDuration)
    }

}
