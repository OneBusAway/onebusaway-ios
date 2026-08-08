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
struct MapItemSheetView: View {
    let application: Application
    let mapItem: MKMapItem

    @EnvironmentObject var coordinator: SheetCoordinator<AppSheetRoute>
    @Environment(\.dismiss) private var dismiss

    @State private var websiteURL: URL?
    @State private var viewModel: MapItemViewModel?

    var body: some View {
        Group {
            if let viewModel {
                VStack(spacing: 0) {
                    MapItemView(viewModel: viewModel, showsShareButton: false)
                }
                .overlay(alignment: .topTrailing) {
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
        .onAppear {
            guard viewModel == nil else { return }
            viewModel = MapItemViewModel(
                mapItem: mapItem,
                application: application,
                actions: MapItemActions(
                    openWebsite: { websiteURL = $0 },
                    showNearbyStops: { coordinator.push(.nearbyStops(coordinate: $0)) },
                    dismiss: { dismiss() }
                ),
                removePinHandler: nil,
                // Trip planning has no SwiftUI route yet: the button renders for
                // layout parity and does nothing. Wire this up when the trip
                // planner lands on this surface.
                planTripHandler: { }
            )
        }
        .sheet(item: $websiteURL) { url in
            SafariSheetView(url: url)
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
