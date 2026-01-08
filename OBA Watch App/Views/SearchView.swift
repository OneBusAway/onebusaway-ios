//
//  SearchView.swift
//  OBAWatch Watch App
//
//  Created by Prince Yadav on 31/12/25.
//

import SwiftUI
import OBASharedCore

struct SearchView: View {
    @StateObject private var viewModel: SearchViewModel
    
    init() {
        _viewModel = StateObject(wrappedValue: SearchViewModel(
            apiClientProvider: { WatchAppState.shared.apiClient },
            locationProvider: { WatchAppState.shared.currentLocation }
        ))
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.searchText.isEmpty {
                    recentOrEmptyState
                } else {
                    searchResultsList
                }
            }
            .navigationTitle("Search")
        }
        .onChange(of: viewModel.searchText) { _, newValue in
            let trimmed = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                viewModel.performSearch()
            } else {
                viewModel.searchResults = []
                viewModel.bookmarkResults = []
                viewModel.errorMessage = nil
            }
        }
    }
    
    private var recentOrEmptyState: some View {
        VStack(spacing: 0) {
            if viewModel.recentStops.isEmpty && viewModel.recentSearchTerms.isEmpty {
                emptySearchState
            } else {
                recentStopsList
            }
        }
    }

    private var emptySearchState: some View {
        List {
            Section {
                TextField("Search routes, stops...", text: $viewModel.searchText)
                    .submitLabel(.search)
                    .onSubmit {
                        viewModel.performSearch()
                    }
            }

            Section {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Search for Stops")
                        .font(.headline)
                    Text("Enter a stop name or code")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical)
            }
        }
    }
    
    private var noResultsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30))
                .foregroundColor(.secondary)
            Text("No Results")
                .font(.headline)
            Text("Try a different search term")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
    
    private var recentStopsList: some View {
        List {
            Section {
                TextField("Search routes, stops...", text: $viewModel.searchText)
                    .submitLabel(.search)
                    .onSubmit {
                        viewModel.performSearch()
                    }
            }

            if !viewModel.recentSearchTerms.isEmpty {
                Section(header: Text("Recent Searches")) {
                    ForEach(viewModel.recentSearchTerms, id: \.self) { term in
                        Button {
                            viewModel.selectRecentSearchTerm(term)
                        } label: {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 14))
                                Text(term)
                                    .font(.subheadline)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 10))
                            }
                        }
                    }
                    
                    Button {
                        viewModel.clearRecentSearchTerms()
                    } label: {
                        Text("Clear Recent")
                            .font(.caption2)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }

            if !viewModel.recentStops.isEmpty {
                Section(header: Text("Recent Stops")) {
                    ForEach(viewModel.recentStops) { stop in
                        NavigationLink {
                            StopArrivalsView(stopID: stop.id, stopName: stop.name)
                        } label: {
                            SearchResultRow(stop: stop)
                        }
                    }
                }
            }
        }
    }

    private var searchResultsList: some View {
        List {
            Section {
                TextField("Search routes, stops...", text: $viewModel.searchText)
                    .submitLabel(.search)
                    .onSubmit {
                        viewModel.performSearch()
                    }
            }

            let trimmed = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                Section("Quick Search") {
                    NavigationLink {
                        RouteSearchView(initialQuery: viewModel.searchText)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "bus.fill")
                                .foregroundColor(.green)
                            Text("Route: ")
                            Text(viewModel.searchText)
                                .fontWeight(.semibold)
                        }
                    }

                    NavigationLink {
                        AddressSearchView(initialQuery: viewModel.searchText)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundColor(.blue)
                            Text("Address: ")
                            Text(viewModel.searchText)
                                .fontWeight(.semibold)
                        }
                    }

                    NavigationLink {
                        StopSearchResultsView(initialQuery: viewModel.searchText)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "tram.fill")
                                .foregroundColor(.orange)
                            Text("Stop: ")
                            Text(viewModel.searchText)
                                .fontWeight(.semibold)
                        }
                    }

                    NavigationLink {
                        VehicleSearchView(initialQuery: viewModel.searchText)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "car.fill")
                                .foregroundColor(.purple)
                            Text("Vehicle: ")
                            Text(viewModel.searchText)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }

            if viewModel.isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption2)
                }
            } else if !viewModel.bookmarkResults.isEmpty || !viewModel.searchResults.isEmpty {
                if !viewModel.bookmarkResults.isEmpty {
                    Section("Bookmarks") {
                        ForEach(viewModel.bookmarkResults) { bm in
                            NavigationLink {
                                StopArrivalsView(stopID: bm.stopID, stopName: bm.name)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(bm.name)
                                        .font(.headline)
                                        .lineLimit(2)
                                    HStack(spacing: 6) {
                                        if let route = bm.routeShortName, !route.isEmpty {
                                            Text(route)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        if let headsign = bm.tripHeadsign, !headsign.isEmpty {
                                            Text(headsign)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                if !viewModel.searchResults.isEmpty {
                    Section("Stops") {
                        ForEach(viewModel.searchResults) { stop in
                            NavigationLink {
                                StopArrivalsView(stopID: stop.id, stopName: stop.name)
                                    .onAppear {
                                        viewModel.recordRecent(stop: stop)
                                    }
                            } label: {
                                SearchResultRow(stop: stop)
                            }
                        }
                    }
                }
            } else if !trimmed.isEmpty {
                Section {
                    noResultsState
                }
            }
        }
    }
}

struct SearchResultRow: View {
    let stop: OBAStop
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.red.gradient)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(stop.name)
                    .font(.headline)
                    .lineLimit(2)
                
                if let code = stop.code {
                    Text("Stop \(code)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

#Preview {
    SearchView()
}
