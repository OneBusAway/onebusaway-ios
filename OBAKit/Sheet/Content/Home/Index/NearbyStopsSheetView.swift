//
//  NearbyStopsSheetView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import CoreLocation
import OBAKitCore

/// The Nearby Stops index — `AppSheetRoute.nearbyAll` and
/// `AppSheetRoute.nearbyStops(coordinate:)`. Native replacement for
/// `NearbyStopsViewController`.
///
/// Split in two: this view owns the chrome and the "no anchor at all" case,
/// while `NearbyStopsSheetContent` owns the view model. A `@StateObject` can't
/// be created conditionally, and there is no honest coordinate to build one
/// with when the map hasn't settled, the device has no fix, and there is no
/// current region.
struct NearbyStopsSheetView: View {
    /// Nil when nothing could anchor the search. Stored (rather than resolved
    /// internally) so the factory's fallback chain is visible to tests.
    let coordinate: CLLocationCoordinate2D?
    let application: Application

    @Environment(\.dismiss) private var dismiss

    init(application: Application, coordinate: CLLocationCoordinate2D?) {
        self.application = application
        self.coordinate = coordinate
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text(Strings.nearbyStops))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(Strings.close) { dismiss() }
                    }
                }
        }
        .searchSheetBackground()
    }

    @ViewBuilder
    private var content: some View {
        if let coordinate {
            NearbyStopsSheetContent(
                viewModel: NearbyStopsViewModel(coordinate: coordinate, application: application)
            )
        } else {
            EmptyStateView(
                // Reuses OBAKitCore's shared title, already translated in every
                // locale, rather than minting a sheet-specific key for the same
                // two words.
                title: Strings.locationUnavailable,
                description: OBALoc(
                    "nearby_stops_sheet.no_location.body",
                    value: "Move the map or turn on location services to see stops near you.",
                    comment: "Body shown on the Nearby Stops index sheet when no map viewport, device location, or region is available to search around."
                ),
                systemImage: AppSymbol.locationUnavailable
            )
        }
    }
}

/// The list itself. Owns `NearbyStopsViewModel` so the parent can decline to
/// build one when there's no coordinate.
private struct NearbyStopsSheetContent: View {
    @StateObject private var viewModel: NearbyStopsViewModel
    @EnvironmentObject var coordinator: SheetCoordinator<AppSheetRoute>
    @State private var searchText = ""

    /// Whether `.task` has run to completion at least once.
    ///
    /// `viewModel.isLoading` alone can't drive the spinner: it is still `false`
    /// on the first render, because `.task` doesn't run until after the body has
    /// been evaluated. Keying only on it painted "No Nearby Stops" for a frame
    /// before the fetch had even started.
    @State private var hasCompletedFirstLoad = false

    init(viewModel: @autoclosure @escaping () -> NearbyStopsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    private var sections: [NearbyStopsIndexSection] {
        NearbyStopsIndexSection.sections(stops: viewModel.stops, filter: searchText)
    }

    /// Whether the user has actually typed something to filter by, as opposed to
    /// merely focusing the field. Drives the choice between the "no stops nearby"
    /// empty state and a no-search-results one.
    private var hasActiveQuery: Bool {
        String.normalizedSearchQuery(searchText) != nil
    }

    var body: some View {
        list
            .searchable(text: $searchText)
            .task {
                await viewModel.loadStops()
                hasCompletedFirstLoad = true
            }
    }

    @ViewBuilder
    private var list: some View {
        if let error = viewModel.operationError {
            // Inline rather than `application.displayError`: an app-level alert
            // over a stacked sheet is the wrong affordance, and this view holds
            // no `Application` to raise one with.
            EmptyStateView(
                title: Strings.error,
                description: error.localizedDescription,
                systemImage: AppSymbol.error
            ) {
                Button(Strings.retry) {
                    Task { await viewModel.loadStops() }
                }
            }
        } else if !hasCompletedFirstLoad || (viewModel.isLoading && viewModel.stops.isEmpty) {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if sections.isEmpty {
            if hasActiveQuery {
                // Distinct from "there are no stops here": the user filtered them
                // away. The system's own search-empty view says so in every
                // locale and quotes the query back.
                ContentUnavailableView.search(text: searchText)
            } else {
                // Reuses the UIKit Nearby Stops screen's already-translated
                // empty-set copy — same screen, same sentence.
                EmptyStateView(
                    title: OBALoc(
                        "nearby_stops_controller.empty_set.title",
                        value: "No Nearby Stops",
                        comment: "Title for the empty set indicator on the Nearby Stops controller."
                    ),
                    description: OBALoc(
                        "nearby_stops_controller.empty_set.body",
                        value: "There are no other stops in the vicinity.",
                        comment: "Body for the empty set indicator on the Nearby Stops controller."
                    ),
                    systemImage: AppSymbol.search
                )
            }
        } else {
            List {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.stops, id: \.id) { stop in
                            HomeStopRow(stop: stop) {
                                coordinator.push(.stopDetails(stopID: stop.id))
                            }
                        }
                    } header: {
                        Text(section.title)
                            .font(.headline)
                    }
                    .textCase(nil)
                }
            }
            .searchListChrome()
        }
    }
}
