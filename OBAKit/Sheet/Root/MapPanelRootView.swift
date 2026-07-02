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
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    private let factory: AppSheetViewFactory

    init(application: Application) {
        _coordinator = StateObject(wrappedValue: SheetCoordinator<AppSheetRoute>(root: .home))
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
        .floatingSheet(coordinator: coordinator) { route in
            factory.view(for: route)
        }
    }

    private var moreButton: some View {
        MoreButton {
            coordinator.push(.more)
        }
        .padding(ThemeMetrics.controllerMargin)
    }
}
