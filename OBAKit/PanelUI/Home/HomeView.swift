//
//  HomeView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import MapKit
import OBAKitCore

/// The main panel view for the home screen, combining nearby stops, recent stops, and bookmarks.
/// Modeled on the Apple Maps panel experience.
struct HomeView: View {
    let application: Application
    let nearbyStops: [Stop]
    let onStopSelected: (Stop) -> Void

    // Search state
    @Binding var searchText: String
    @FocusState.Binding var isSearchFocused: Bool
    @ObservedObject var searchViewModel: SearchViewModel

    let onSearchFocused: () -> Void
    let onSearchCancelled: () -> Void
    let onMapItemSelected: (MKMapItem) -> Void
    let onRouteSelected: (Route) -> Void
    let onVehicleSelected: (AgencyVehicle) -> Void
    let onClearRecentSearches: () -> Void

    private var isVehicleSearchAvailable: Bool {
        application.obacoService != nil
    }

    private var brandColor: Color {
        Color(ThemeColors.shared.brand)
    }

    private var searchPlaceholder: String {
        if let region = application.regionsService.currentRegion {
            return Formatters.searchPlaceholderText(region: region)
        }
        return OBALoc("search_controller.searchbar.placeholder", value: "Search", comment: "Default search bar placeholder text")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field (always visible at top)
            SearchFieldView(
                text: $searchText,
                isFocused: $isSearchFocused,
                placeholder: searchPlaceholder,
                onCancel: {
                    searchViewModel.clearResults()
                    onSearchCancelled()
                }
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .onChange(of: isSearchFocused) { _, focused in
                if focused {
                    onSearchFocused()
                }
            }
            .onChange(of: searchText) { _, _ in
                // Clear results when search text changes (user is typing new query)
                if searchViewModel.searchState != .idle {
                    searchViewModel.clearResults()
                }
            }

            Divider()

            // Content: search mode or normal mode
            if isSearchFocused {
                SearchContentView(
                    searchText: searchText,
                    application: application,
                    viewModel: searchViewModel,
                    isVehicleSearchAvailable: isVehicleSearchAvailable,
                    brandColor: brandColor,
                    onMapItemSelected: { mapItem in
                        application.userDataStore.addRecentMapItem(mapItem)
                        onMapItemSelected(mapItem)
                    },
                    onRouteSelected: onRouteSelected,
                    onStopSelected: onStopSelected,
                    onVehicleSelected: onVehicleSelected,
                    onClearRecentSearches: onClearRecentSearches
                )
            } else {
                // Normal home content
                ScrollView {
                    VStack(spacing: 0) {
                        // Nearby Stops section
                        StopListView(
                            title: "Nearby Stops",
                            stops: nearbyStops,
                            onStopSelected: onStopSelected
                        )

                        // Recent Stops section
                        RecentStopsView(application: application, onStopSelected: onStopSelected)

                        // Bookmarks section
                        BookmarksView(application: application, onStopSelected: onStopSelected)
                    }
                }
            }
        }
    }
}
