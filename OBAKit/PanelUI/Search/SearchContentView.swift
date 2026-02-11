//
//  SearchContentView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import MapKit
import OBAKitCore

/// Container view that orchestrates search states: recent items, quick search, and results
struct SearchContentView: View {
    let searchText: String
    let application: Application
    @ObservedObject var viewModel: SearchViewModel
    let isVehicleSearchAvailable: Bool
    let brandColor: Color
    let onMapItemSelected: (MKMapItem) -> Void
    let onRouteSelected: (Route) -> Void
    let onStopSelected: (Stop) -> Void
    let onVehicleSelected: (AgencyVehicle) -> Void
    let onClearRecentSearches: () -> Void

    /// Determines what to show based on search state
    private enum ContentMode {
        case recentItems
        case quickSearch
        case searchResults
    }

    private var contentMode: ContentMode {
        switch viewModel.searchState {
        case .idle:
            return searchText.isEmpty ? .recentItems : .quickSearch
        case .searching, .results, .error:
            return .searchResults
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                switch contentMode {
                case .recentItems:
                    RecentMapItemsView(
                        application: application,
                        onMapItemSelected: onMapItemSelected,
                        onClearAll: onClearRecentSearches
                    )

                case .quickSearch:
                    QuickSearchView(
                        searchText: searchText,
                        isVehicleSearchAvailable: isVehicleSearchAvailable,
                        brandColor: brandColor
                    ) { searchType, query in
                        Task {
                            await viewModel.executeSearch(type: searchType, query: query)
                        }
                    }

                case .searchResults:
                    SearchResultsView(
                        viewModel: viewModel,
                        application: application,
                        brandColor: brandColor,
                        onRouteSelected: onRouteSelected,
                        onStopSelected: onStopSelected,
                        onMapItemSelected: onMapItemSelected,
                        onVehicleSelected: onVehicleSelected
                    )
                }
            }
        }
    }
}
