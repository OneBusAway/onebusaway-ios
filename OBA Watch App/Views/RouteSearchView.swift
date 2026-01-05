import SwiftUI
import CoreLocation
import Combine
import OBASharedCore

struct RouteSearchView: View {
    @StateObject private var viewModel: RouteSearchViewModel

    init(initialQuery: String) {
        _viewModel = StateObject(wrappedValue: RouteSearchViewModel(
            initialQuery: initialQuery,
            apiClient: WatchAppState.shared.apiClient,
            locationProvider: { WatchAppState.shared.currentLocation }
        ))
    }

    var body: some View {
        List {
            Section {
                TextField("Search routes", text: $viewModel.query)
                    .onSubmit { viewModel.performSearch() }
                    .onChange(of: viewModel.query) { _, newValue in
                        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            viewModel.performSearch()
                        } else {
                            viewModel.routes = []
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
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            } else if !viewModel.routes.isEmpty {
                Section("Routes") {
                    ForEach(viewModel.routes, id: \.id) { route in
                        NavigationLink {
                            RouteDetailView(route: route)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                if let short = route.shortName, !short.isEmpty {
                                    Text(short)
                                        .font(.headline)
                                }
                                if let long = route.longName, !long.isEmpty {
                                    Text(long)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                if let agency = route.agencyName, !agency.isEmpty {
                                    Text(agency)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            } else if !viewModel.query.isEmpty && !viewModel.isLoading {
                Section {
                    Text("No routes found.")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Routes")
        .onAppear {
            viewModel.performSearch()
        }
    }
}
