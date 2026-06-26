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

// MARK: - MapPanelRootView

/// A pure-SwiftUI alternative to `MapViewController`: a full-screen SwiftUI
/// `Map` with the persistent floating sheet system layered on top.
///
/// This is the SwiftUI-native composition root for the sheet system:
/// `Application` enters the SwiftUI tree here. The coordinator is owned as a
/// `@StateObject`; the factory is a stateless `let`. Sheet content is rendered
/// over the SwiftUI `Map`.
struct MapPanelRootView: View {

    @StateObject private var coordinator: SheetCoordinator<AppSheetRoute>
    @StateObject private var mapViewModel: MapViewModel

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    /// Presentation state only. The popup reads its data from
    /// `mapViewModel.weatherDisplay` so a refresh that finishes while the card
    /// is open updates the displayed forecast in place.
    @State private var isWeatherPopupPresented = false

    @Environment(\.scenePhase) private var scenePhase

    private let factory: AppSheetViewFactory

    init(application: Application, factory: AppSheetViewFactory) {
        _coordinator = StateObject(wrappedValue: SheetCoordinator<AppSheetRoute>(root: .home))
        _mapViewModel = StateObject(wrappedValue: MapViewModel(application: application))
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
        // TODO: Detent-aware bottom padding. Pinned to the collapsed sheet
        // height today, so dragging the sheet up to `.medium` or
        // `largeDetent` lets the user-location annotation and any future map
        // overlays slip under the sheet.
        .safeAreaPadding(.bottom, AppSheetRoute.homeCollapsedHeight)
        .overlay(alignment: .topLeading) {
            weatherButton
        }
        .overlay(alignment: .bottomLeading) {
            MyTripButton {
                coordinator.push(.routePicker)
            }
            .padding(.leading, ThemeMetrics.controllerMargin)
            .padding(.bottom, AppSheetRoute.homeCollapsedHeight + ThemeMetrics.controllerMargin)
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
}
