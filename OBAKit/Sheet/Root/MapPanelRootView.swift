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
    @StateObject private var stopsObserver: MapStopsObserver

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    /// Presentation state only. The popup reads its data from
    /// `mapViewModel.weatherDisplay` so a refresh that finishes while the card
    /// is open updates the displayed forecast in place.
    @State private var isWeatherPopupPresented = false

    /// The stop the user tapped, if any. Bound to the `Map`'s `selection`; cleared
    /// after pushing so re-tapping the same stop pushes again.
    @State private var selectedStopID: Stop.ID?

    @Environment(\.scenePhase) private var scenePhase

    @State private var sheetHeight: CGFloat = 0
    @State private var toolbarsAnimationDuration: CGFloat = 0
    @State private var toolbarsOpacity: CGFloat = 1

    @State private var halfScreenHeight: CGFloat = 350

    /// Points of fade band immediately below the clamp ceiling. Toolbar
    /// opacity ramps from 1 → 0 across this window as the sheet approaches `halfScreenHeight`.
    private let toolbarFadeRange: CGFloat = 50

    private let application: Application
    private let factory: AppSheetViewFactory

    init(application: Application, factory: AppSheetViewFactory) {
        _coordinator = StateObject(wrappedValue: SheetCoordinator<AppSheetRoute>(root: .home))
        _mapViewModel = StateObject(wrappedValue: MapViewModel(application: application))
        _stopsObserver = StateObject(wrappedValue: MapStopsObserver(mapRegionManager: application.mapRegionManager))
        self.application = application
        self.factory = factory
    }

    var body: some View {
        Map(position: $cameraPosition, selection: $selectedStopID) {
            UserAnnotation()
            ForEach(stopsObserver.stops) { stop in
                Annotation("", coordinate: stop.coordinate) {
                    Image(uiImage: application.stopIconFactory.buildSquircleIcon(for: stop))
                }
                .tag(stop.id)
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            application.mapRegionManager.scheduleStopsRequest(in: context.region)
        }
        .onChange(of: selectedStopID) { _, id in
            guard let id else { return }
            coordinator.push(.stopDetails(stopID: id))
            selectedStopID = nil
        }
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
        .safeAreaPadding(.bottom, AppSheetRoute.homeCollapsedHeight)
        .overlay(alignment: .topLeading) {
            weatherButton
        }
        .overlay(alignment: .topTrailing) {
            moreButton
        }
        .overlay(alignment: .bottomLeading) {
            bottomFloatingTripButton
        }
        .floatingSheet(coordinator: coordinator) { route in
            buildSheetContent(for: route)
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
    private func buildSheetContent(for route: AppSheetRoute) -> some View {
        factory.view(for: route)
            .fullScreenCover(isPresented: $isWeatherPopupPresented) {
                WeatherDetailPopup(
                    display: mapViewModel.weatherDisplay,
                    isPresented: $isWeatherPopupPresented
                )
                .presentationBackground(.clear)
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                max(min(proxy.size.height, halfScreenHeight), 0)
            } action: { oldValue, newValue in
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

    @ViewBuilder
    private var weatherButton: some View {
        if mapViewModel.isWeatherFeatureAvailable {
            WeatherButton(display: mapViewModel.weatherDisplay) { _ in
                isWeatherPopupPresented = true
            }
            .padding(ThemeMetrics.controllerMargin)
        }
    }

    private var bottomFloatingTripButton: some View {
        MyTripButton {
            coordinator.push(.routePicker)
        }
        .padding(.leading, ThemeMetrics.controllerMargin)
        .offset(y: -sheetHeight)
        .opacity(toolbarsOpacity)
        .animation(
            .interpolatingSpring(duration: toolbarsAnimationDuration, bounce: 0, initialVelocity: 0),
            value: sheetHeight
        )
    }

    private var moreButton: some View {
        MoreButton {
            coordinator.push(.more)
        }
        .padding(ThemeMetrics.controllerMargin)
    }
}
