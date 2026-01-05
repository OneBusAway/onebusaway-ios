import SwiftUI
import CoreLocation
import OBASharedCore

struct StopSearchResultsView: View {
    @StateObject private var viewModel: StopSearchViewModel

    init(initialQuery: String) {
        _viewModel = StateObject(wrappedValue: StopSearchViewModel(
            initialQuery: initialQuery,
            apiClient: WatchAppState.shared.apiClient,
            locationProvider: { WatchAppState.shared.currentLocation }
        ))
    }

    var body: some View {
        List {
            Section {
                TextField("Search stops", text: $viewModel.query)
                    .onSubmit { viewModel.performSearch() }
                    .onChange(of: viewModel.query) { _, newValue in
                        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            viewModel.performSearch()
                        } else {
                            viewModel.stops = []
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
            } else if !viewModel.stops.isEmpty {
                Section("Stops") {
                    ForEach(viewModel.stops) { stop in
                        NavigationLink {
                            StopArrivalsView(stopID: stop.id, stopName: stop.name)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(stop.name)
                                    .font(.headline)
                                    .lineLimit(2)
                                
                                if let code = stop.code {
                                    Text("Stop \(code)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            } else if viewModel.stops.isEmpty && !viewModel.isLoading {
                Section {
                    Text("No stops found.")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Stops")
        .onAppear {
            viewModel.performSearch()
        }
    }
}
