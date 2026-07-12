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

    init(application: Application) {
        _coordinator = StateObject(wrappedValue: SheetCoordinator<AppSheetRoute>(root: .home))
        _mapViewModel = StateObject(wrappedValue: MapViewModel(application: application))
        factory = AppSheetViewFactory(application: application)
    }

    var body: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()
        }
        // TODO: Detent-aware bottom padding. Pinned to the collapsed sheet
        // height today, so dragging the sheet up to `.medium` or
        // `largeDetent` lets the user-location annotation and any future map
        // overlays slip under the sheet.
        .safeAreaPadding(.bottom, AppSheetRoute.homeCollapsedHeight)
        .overlay(alignment: .topTrailing) {
            moreButton
        }
        .overlay(alignment: .topLeading) {
            weatherButton
        }
        .onAppear {
            mapViewModel.start()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                mapViewModel.onAppBecameActive()
            }
        }
        // The popup cover is attached INSIDE the sheet content so it's
        // presented from the floating sheet's `UISheetPresentationController` —
        // a host-level `.fullScreenCover` ends up under the sheet because the
        // sheet owns the topmost presentation context. `.presentationBackground(.clear)`
        // keeps the map and sheet visible behind the dim+card.
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

    private var moreButton: some View {
        MoreButton {
            coordinator.push(.more)
        }
        .padding(ThemeMetrics.controllerMargin)
    }
}
