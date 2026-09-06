//
//  MapItemSheetView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import MapKit
import OBAKitCore

/// `AppSheetRoute.mapItem` — the place-detail card, at the medium detent so the map
/// stays visible behind it.
///
/// Wraps the shared `MapItemView` with sheet-native actions: Close pops the stacked
/// sheet, Nearby Stops pushes its own route, and the website opens in a local Safari
/// sheet rather than being presented from a view controller.
///
/// The searched place marker is drawn by `MapPanelRootView`, which drops it when this
/// route leaves the sheet stack — the sheet doesn't clear the map itself. See
/// `MapSearchDisplayModel.owner`.
struct MapItemSheetView: View {
    let application: Application
    let mapItem: MKMapItem

    @EnvironmentObject var coordinator: SheetCoordinator<AppSheetRoute>
    @Environment(\.dismiss) private var dismiss

    @State private var website: WebsiteLink?
    @State private var viewModel: MapItemViewModel?

    var body: some View {
        Group {
            if let viewModel {
                MapItemView(viewModel: viewModel, showsShareButton: false)
                    // Top-*leading*, matching where `MapItemView` puts Share in the
                    // UIKit host. `.topTrailing` would land on top of that view's
                    // own Close button and swallow its taps.
                    .overlay(alignment: .topLeading) {
                        if let shareURL = viewModel.shareURL {
                            ShareLink(item: shareURL)
                                .labelStyle(.iconOnly)
                                .padding()
                        }
                    }
            } else {
                Color.clear
            }
        }
        // Built here rather than in `init`: `MapItemViewModel.init` kicks off a Look
        // Around scene request, and `@State`'s initial value would be re-evaluated on
        // every body pass of the sheet container — one network request per detent
        // drag frame.
        .onAppear {
            guard viewModel == nil else { return }
            viewModel = MapItemViewModel(
                mapItem: mapItem,
                application: application,
                actions: MapItemActions(
                    openWebsite: { website = WebsiteLink(url: $0) },
                    showNearbyStops: { coordinator.push(.nearbyStops(coordinate: $0)) },
                    dismiss: { dismiss() }
                ),
                removePinHandler: nil,
                // Map-panel mode has no classic `MapViewController` to present the
                // OTP trip planner on. Leave `nil` so the Plan Trip button stays
                // hidden rather than shipping a no-op; wire when the panel can
                // host the planner (see #883 / StopPageActionPresenter).
                planTripHandler: nil
            )
        }
        .sheet(item: $website) { link in
            SafariSheetView(url: link.url)
        }
    }
}

/// `.sheet(item:)` needs an `Identifiable` payload. A local wrapper rather than a
/// retroactive `Identifiable` conformance on `URL` — protocol conformances aren't
/// access-controlled, so conforming a Foundation type here would make it OBAKit's
/// answer for every consumer of the framework and collide with any other module
/// (or a future Foundation version) that declares the same thing.
private struct WebsiteLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
